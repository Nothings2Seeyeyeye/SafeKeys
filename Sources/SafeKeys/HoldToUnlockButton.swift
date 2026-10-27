import SwiftUI

/// 按住才会解锁的按钮。
///
/// 为什么不用普通点击：锁定浮层铺满整屏，解锁按钮就在屏幕正中，
/// 而清洁过程中触控板经常被蹭到 —— 单击、双击都可能被随机点中而意外解锁。
/// 改成"按住 0.8 秒"之后，偶发的误触再也不会把锁打开，
/// 而真正想解锁的人看着进度条也能确定地做到。
struct HoldToUnlockButton: View {

    /// 按住多久才判定为解锁意图
    static let holdSeconds: Double = 0.8

    enum Style {
        case large      // 浮层里的主按钮
        case compact    // 主窗口里的按钮

        var height: CGFloat { self == .large ? 54 : 34 }
        var width: CGFloat? { self == .large ? 240 : nil }
        var radius: CGFloat { self == .large ? 12 : 8 }
        var font: Font { self == .large ? .system(size: 17, weight: .medium) : .system(size: 14, weight: .medium) }
    }

    var style: Style
    var enabled: Bool
    var onUnlock: () -> Void

    /// 按压进度与计时都交给它。
    ///
    /// 计时器**只在按住期间存在**：早期版本用一个 static 的 30Hz TimerPublisher
    /// 被 .onReceive 无条件订阅，结果 App 什么都不做也每秒被 RunLoop 唤醒 30 次。
    /// 对"用完就该彻底安静"的工具来说，这是实打实的能耗浪费。
    @StateObject private var tracker = HoldTracker()

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: style.radius, style: .continuous))
            // 关键：明确声明整块矩形都是命中区域。
            // SwiftUI 里 .background() 只负责绘制、不参与命中测试，
            // 少了这一行就只有文字那一点能点。
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in tracker.begin() }
                    .onEnded { _ in tracker.cancel() }
            )
            .disabled(!enabled)
            .onAppear { tracker.onUnlock = onUnlock }
    }

    private var content: some View {
        let bar = GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(baseFill)
                Rectangle()
                    .fill(progressFill)
                    .frame(width: geo.size.width * tracker.progress)
            }
            .overlay {
                Text("按住解锁")
                    .font(style.font)
                    .foregroundColor(enabled ? .white : .secondary)
                    .allowsHitTesting(false)
            }
        }

        return Group {
            if let width = style.width {
                bar.frame(width: width, height: style.height)
            } else {
                bar.frame(maxWidth: .infinity, maxHeight: style.height)
            }
        }
    }

    private var baseFill: Color {
        enabled ? Color.red.opacity(0.45) : Color(NSColor.controlBackgroundColor)
    }

    private var progressFill: Color {
        enabled ? Color.red.opacity(0.95) : Color.clear
    }
}

// MARK: - 按压计时

/// 按住期间驱动进度条，松手立刻销毁计时器，不留任何后台轮询。
private final class HoldTracker: ObservableObject {

    @Published private(set) var progress: CGFloat = 0
    var onUnlock: (() -> Void)?

    private var timer: Timer?
    private var startedAt: Date?

    func begin() {
        guard timer == nil else { return }
        startedAt = Date()
        let ticker = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.advance()
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        if progress != 0 { progress = 0 }
    }

    private func advance() {
        guard let start = startedAt else { return }
        let elapsed = Date().timeIntervalSince(start) / HoldToUnlockButton.holdSeconds
        if elapsed >= 1 {
            cancel()
            onUnlock?()
        } else {
            progress = min(1, CGFloat(elapsed))
        }
    }

    deinit {
        timer?.invalidate()
    }
}
