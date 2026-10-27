import AppKit
import SwiftUI

/// 锁定期间覆盖所有屏幕的浮层。层级高于普通窗口，永远点得到解锁按钮。
final class OverlayWindow {

    static let shared = OverlayWindow()

    private var panels: [NSPanel] = []

    private init() {}

    func show() {
        hide()

        let screens = NSScreen.screens.isEmpty ? [] : NSScreen.screens
        let targets = screens.isEmpty ? [nil] : screens.map(Optional.init)

        for target in targets {
            let frame = target?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: OverlayView())
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}

struct OverlayView: View {

    @ObservedObject private var manager = LockManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.9))
                    Text("键盘已锁定")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                    Text("鼠标和触控板仍可正常使用")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }

                countdown

                HoldToUnlockButton(style: .large, enabled: true) {
                    manager.unlock(reason: .button)
                }

                VStack(spacing: 4) {
                    Text(Settings.unlockPhrase.hint)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
                    Text("按钮要按住 0.8 秒才生效，蹭到触控板也不会解锁")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    @ViewBuilder
    private var countdown: some View {
        let seconds = max(0, Int(manager.remaining.rounded(.up)))
        VStack(spacing: 6) {
            Text(timeString(seconds))
                .font(.system(size: 46, weight: .medium).monospacedDigit())
                .foregroundColor(.white)
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var description: String {
        if manager.scheduledDuration >= LockManager.hardCapSeconds {
            return "安全兜底将在 10 分钟后自动解锁"
        }
        return "倒计时结束后自动解锁"
    }
}
