import AppKit
import SwiftUI

/// 「关于 SafeKeys」面板。
///
/// 除了常规的署名与版本，这里刻意放三样实用信息：快捷键、解锁通道、卸载入口。
/// 因为这是个"用到才想起"的工具 —— 真到了要卸载时，能不能当场找到命令，
/// 比介绍它有多了不起重要得多。
enum AboutPanel {

    static let identifier = NSUserInterfaceItemIdentifier("SafeKeys.about")

    static func show() {
        if let existing = NSApp.windows.first(where: { $0.identifier == identifier }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.identifier = identifier
        panel.title = "关于 SafeKeys"
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: AboutView())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutView: View {

    private static let repository = URL(string: "https://github.com/Nothings2Seeyeyeye/SafeKeys")!

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            shortcuts
            unlock
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 340)
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 76, height: 76)
            }
            Text("SafeKeys")
                .font(.system(size: 20, weight: .semibold))
            Text("版本 \(version)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("清洁 Mac 时锁定键盘，鼠标与触控板照常可用")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("快捷键")
            row("Cmd + Q", "退出（自动解锁）")
            row("Cmd + W", "关闭窗口（自动解锁）")
            row("Cmd + M", "最小化")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("解锁通道")
            Text("按住解锁按钮 0.8 秒 · 口令 · 倒计时 · pkill -x SafeKeys")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("事件拦截是进程资源，进程终止即恢复键盘。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link("GitHub 仓库", destination: Self.repository)
                .font(.system(size: 12))
            Text("彻底卸载：scripts/uninstall.sh 或 App --uninstall")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            Text("MIT License · 自签名未公证")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
    }

    private func row(_ key: String, _ description: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(width: 78, alignment: .leading)
            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
