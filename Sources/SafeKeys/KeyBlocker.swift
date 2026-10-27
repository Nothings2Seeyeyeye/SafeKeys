import CoreGraphics
import Dispatch
import Foundation

/// 键盘拦截核心。
///
/// 原理：在系统 HID 事件层面插入一个 event tap，回调返回 nil 表示"事件已被消费，
/// 不再向下传递"，从而实现全系统级别的按键丢弃。
///
/// 生命周期：tap 属于进程资源，进程一旦消亡，内核必然回收，键盘必然恢复。
final class KeyBlocker {

    static let shared = KeyBlocker()

    // MARK: - 事件掩码

    /// NX_SYSDEFINED：媒体键（亮度/音量/播放）与部分功能键走这条系统自定义通道，
    /// 不纳入掩码就会漏掉 F1–F12。
    private static let systemDefined = CGEventType(rawValue: 14)!

    private static let eventMask: CGEventMask = {
        func bit(_ type: CGEventType) -> CGEventMask { CGEventMask(1 << type.rawValue) }
        return bit(.keyDown)
            | bit(.keyUp)
            | bit(.flagsChanged)          // Cmd / Shift / Option / Ctrl / CapsLock
            | CGEventMask(1 << KeyBlocker.systemDefined.rawValue)
    }()

    // MARK: - 状态

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private(set) var isBlocking = false

    /// 检测到合法解锁口令
    var onUnlockHotkey: (() -> Void)?

    // MARK: - 口令判定状态
    //
    // 全部使用固定标量与定长数组，不在热路径上做任何堆分配 ——
    // 每个按键都会经过这里，一次分配都可能让全系统输入产生可感知的抖动。

    /// 口令判定实例，只在锁定期间存在。
    /// 本身不持有 CGEvent，输入已被压成标量，便于命令行自检。
    private var matcher: UnlockPhraseMatcher?

    /// 注入位置。
    /// 直接用 rawValue，避免不同 macOS SDK 上 Swift 导入名不一致的问题：
    /// 0 = kCGHIDEventTap（最早的用户态注入点，能拦住 Cmd+Tab 等系统快捷键）
    /// 1 = kCGSessionEventTap（较浅，作为对照）
    private static let hidTapLocation = CGEventTapLocation(rawValue: 0)!
    private static let sessionTapLocation = CGEventTapLocation(rawValue: 1)!

    private init() {}

    // MARK: - 安装 / 卸载 tap

    /// 安装 tap 并开始拦截。返回 false 通常意味着缺少辅助功能权限。
    @discardableResult
    func startBlocking() -> Bool {
        guard eventTap == nil else { return true }

        guard let tap = CGEvent.tapCreate(
            tap: Settings.usesHIDTap ? Self.hidTapLocation : Self.sessionTapLocation,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: Self.tapCallback,
            userInfo: nil
        ) else {
            return false
        }

        matcher = UnlockPhraseMatcher(phrase: Settings.unlockPhrase, armedAt: CFAbsoluteTimeGetCurrent())

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isBlocking = true
        return true
    }

    func stopBlocking() {
        isBlocking = false
        matcher = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// 只做一件事：立刻停止拦截。
    /// 供 watchdog 线程与退出钩子调用 —— 不做任何 UI 操作、不触碰 RunLoop，
    /// 因此在主线程不可用的情况下也安全。
    func emergencyRelease() {
        isBlocking = false
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    // MARK: - 回调

    private static let tapCallback: CGEventTapCallBack = { _, type, event, _ in
        KeyBlocker.shared.handle(type: type, event: event)
    }

    /// 运行在主线程 RunLoop 上。必须极轻量，任何耗时操作都会造成全系统输入卡顿。
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS 检测到回调响应过慢会自动禁用 tap。
            if isBlocking, let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil

        case .keyDown:
            let key = UnlockPhraseMatcher.Key(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                timestamp: CFAbsoluteTimeGetCurrent()
            )
            var unlocked = false
            if var matcher {
                unlocked = matcher.feed(key)
                self.matcher = matcher
            }
            if unlocked {
                DispatchQueue.main.async { [weak self] in
                    self?.onUnlockHotkey?()
                }
            }
            return nil

        case .flagsChanged:
            // 按下任何修饰键都视为口令被中断
            matcher?.interrupt()
            return nil

        case .keyUp:
            return nil

        default:
            if type.rawValue == Self.systemDefined.rawValue {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
    }

}
