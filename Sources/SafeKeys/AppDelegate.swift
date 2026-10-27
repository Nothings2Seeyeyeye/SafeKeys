import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 必须在建窗口之前：没有主菜单就没有 Cmd+Q / Cmd+W 的绑定点
        MainMenuBuilder.install()
        buildMainWindow()
        LockManager.shared.startServices()
    }

    /// 关闭最后一个窗口即终止进程。
    ///
    /// 这不只是省内存：本 App 的唯一职责是临时劫持键盘，用完必须彻底消失，
    /// 不能变成常驻后台的隐形进程。返回 true 后，关闭窗口等同于 Cmd+Q ——
    /// 终端里的进程也随之消失，不留下任何占用。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindow?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 先解锁再拆掉后台设施。顺序不能反：
        // 解锁依赖 KeyBlocker 与 OverlayWindow，二者必须在 teardown 之前完成收尾。
        LockManager.shared.unlock(reason: .quitting)
        LockManager.shared.teardown()
        mainWindow?.contentView = nil
        mainWindow = nil
    }

    // MARK: - 窗口

    private func buildMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SafeKeys"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: ContentView())
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 关于面板

    /// 菜单栏「关于 SafeKeys」的入口。
    /// 这里不写 target：菜单项顺着 responder chain 找到 AppDelegate 来响应。
    @objc func showAbout(_ sender: Any?) {
        AboutPanel.show()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 绝不允许"窗口关了但键盘还锁着"
        if LockManager.shared.phase == .locked {
            LockManager.shared.unlock(reason: .windowClosing)
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // 只处理主窗口；关于面板另外管理，关它不该连带把 App 退掉。
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        // 不等 AppKit 的隐式策略，窗口一关自己走退出流程。
        //
        // applicationShouldTerminateAfterLastWindowClosed = true 已经足够表达意图，
        // 但它是框架在窗口管理内部触发的；这里再显式 terminate 一次，保证无论
        // activationPolicy、Spaces 还是窗口动画处于什么状态，进程都一定退干净。
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        mainWindow = nil
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
