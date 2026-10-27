import AppKit

/// 用代码构建主菜单栏。
///
/// **为什么必须手写**：本 App 由 SwiftPM 组装 bundle，Resources 里没有 MainMenu.nib。
/// 而 macOS 的 Cmd+Q / Cmd+W 并不是 AppKit 内建的开关——它们来自菜单栏里
///「退出」「关闭窗口」菜单项上绑定的 keyEquivalent。没有主菜单，AppKit 就
/// 没有任何东西去响应这组按键，表现就是"点红叉能退、按 Cmd+Q 毫无反应"。
///
/// 每条快捷键的归属见 `Selftest.mainMenuShortcuts`，改这里要一起改自检。
enum MainMenuBuilder {

    /// 纯构建，不触碰 NSApp —— 这样命令行自检（早于 NSApplication 创建）也能调用它。
    static func build() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu()
        main.addItem(appItem)

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu()
        main.addItem(editItem)

        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu()
        main.addItem(windowItem)

        return main
    }

    /// 挂到 App 上。涉及 NSApp 的部分只放在这里。
    static func install() {
        let menu = build()
        NSApp.mainMenu = menu
        // 让「窗口」菜单自动列出当前窗口。到这一步 NSApplication 一定已存在。
        NSApp.windowsMenu = menu.item(withTitle: "窗口")?.submenu
    }

    // MARK: - 子菜单

    private static func appMenu() -> NSMenu {
        let menu = NSMenu()
        let name = ProcessInfo.processInfo.processName
        menu.addItem(NSMenuItem(
            title: "退出 \(name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"      // 小写字母自动附加 Command 修饰键
        ))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu()
        // 这些标准编辑动作属于 NSStandardKeyBindingResponding，Swift 里不作为
        // NSResponder 的成员暴露（#selector(NSResponder.copy(_:)) 编译不过），
        // 用字符串构造 Selector 是该场景下的标准写法。
        menu.addItem(item("撤销", Selector("undo:"), "z"))
        menu.addItem(item("重做", Selector("redo:"), "Z"))   // 大写 = Cmd+Shift+Z
        menu.addItem(.separator())
        menu.addItem(item("剪切", Selector("cut:"), "x"))
        menu.addItem(item("拷贝", Selector("copy:"), "c"))
        menu.addItem(item("粘贴", Selector("paste:"), "v"))
        menu.addItem(item("全选", Selector("selectAll:"), "a"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        menu.addItem(NSMenuItem(
            title: "关闭窗口",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
