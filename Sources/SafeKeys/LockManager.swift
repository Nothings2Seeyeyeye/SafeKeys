import AppKit
import Combine
import Foundation

/// 锁定 / 解锁的唯一状态机。所有 UI 都只读它。
final class LockManager: ObservableObject {

    static let shared = LockManager()

    enum Phase: Equatable {
        case unlocked
        case locked
    }

    enum UnlockReason {
        case button
        case hotkey
        case timeout
        case permissionRevoked
        case systemEvent
        case windowClosing
        case quitting
    }

    /// 无论用户怎么设置，超过这个时长强制解锁。
    /// 防止"设成不限时然后忘了自己在锁定状态"。
    static let hardCapSeconds: TimeInterval = 600

    @Published var phase: Phase = .unlocked
    @Published var remaining: TimeInterval = 0
    @Published var scheduledDuration: TimeInterval = 0
    @Published var permissionGranted = false
    @Published var notice: String?

    private var deadline: Date?
    private var timer: Timer?
    private var permissionTick = 0
    private var napActivity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    // MARK: - 启动

    func startServices() {
        permissionGranted = Permissions.isTrusted()

        KeyBlocker.shared.onUnlockHotkey = { [weak self] in
            self?.unlock(reason: .hotkey)
        }

        Watchdog.shared.onStall = {
            KeyBlocker.shared.emergencyRelease()
        }
        Watchdog.shared.start()

        // 用 Timer(timeInterval:) 而非 scheduledTimer：
        // scheduledTimer 会自动注册进 default mode，再手动加 common 会重复注册同一个
        // timer，导致 tick() 在同一个 RunLoop 周期里被触发两次。
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Watchdog.shared.beat()
            self.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        registerSystemWatchers()
    }

    /// 进程退出前拆掉一切后台设施。
    ///
    /// 严格说这些资源会在进程消亡时由内核回收，谈不上泄漏；但这个 App 的设计原则是
    /// "用完彻底消失"，退出前主动断开 RunLoop 与通知中心的引用，能保证退出路径干净、
    /// 且将来若改成常驻形态也不会积累。
    func teardown() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        Watchdog.shared.stop()
    }

    private func registerSystemWatchers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.unlock(reason: .systemEvent)
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.unlock(reason: .systemEvent)
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.unlock(reason: .systemEvent)
        })

        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.unlock(reason: .systemEvent)
        })
    }

    // MARK: - 心跳节拍

    private func tick() {
        permissionTick += 1
        if permissionTick >= 4 {
            permissionTick = 0
            checkPermission()
        }

        guard phase == .locked, let deadline else { return }
        let left = deadline.timeIntervalSinceNow
        if left <= 0 {
            unlock(reason: .timeout)
        } else {
            remaining = left
        }
    }

    private func checkPermission() {
        let trusted = Permissions.isTrusted()
        if trusted != permissionGranted {
            permissionGranted = trusted
            if !trusted, phase == .locked {
                unlock(reason: .permissionRevoked)
            }
        }
    }

    // MARK: - 锁定

    func lock() {
        guard phase == .unlocked else { return }

        guard Permissions.isTrusted() else {
            Permissions.requestTrust()
            notice = "还没有辅助功能权限。请在系统设置 → 隐私与安全性 → 辅助功能里勾选 SafeKeys，然后重启本 App。"
            return
        }

        guard KeyBlocker.shared.startBlocking() else {
            notice = "事件拦截通道创建失败。请确认已授权「辅助功能」，必要时同时授权「输入监控」，然后重启 SafeKeys。"
            return
        }

        let requested = Settings.lockDurationSeconds
        let effective = requested <= 0 ? Self.hardCapSeconds : min(requested, Self.hardCapSeconds)

        phase = .locked
        scheduledDuration = effective
        remaining = effective
        deadline = Date(timeIntervalSinceNow: effective)
        notice = nil

        OverlayWindow.shared.show()
        beginNapSuppression()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 解锁

    func unlock(reason: UnlockReason) {
        KeyBlocker.shared.stopBlocking()
        deadline = nil
        endNapSuppression()

        guard phase == .locked else { return }

        phase = .unlocked
        scheduledDuration = 0
        remaining = 0
        OverlayWindow.shared.hide()

        switch reason {
        case .button:
            notice = nil
        case .hotkey:
            notice = "已通过 Esc ×3 解锁。"
        case .timeout:
            notice = "倒计时结束，键盘已自动解锁。"
        case .permissionRevoked:
            notice = "辅助功能权限被取消，已自动解锁以保证键盘可用。"
        case .systemEvent:
            notice = "检测到系统睡眠 / 锁屏 / 用户切换，已自动解锁。"
        case .windowClosing:
            notice = "窗口关闭时已自动解锁。"
        case .quitting:
            notice = nil
        }
    }

    // MARK: - App Nap 抑制

    private func beginNapSuppression() {
        guard napActivity == nil else { return }
        napActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "键盘锁定期间必须保持主线程响应"
        )
    }

    private func endNapSuppression() {
        guard let napActivity else { return }
        ProcessInfo.processInfo.endActivity(napActivity)
        self.napActivity = nil
    }
}
