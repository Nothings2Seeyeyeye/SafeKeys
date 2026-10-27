import AppKit
import CoreGraphics
import Foundation

/// 解锁口令引擎的自检。
///
/// 这段逻辑直接关系到"会不会误解锁"，靠人肉推演不可靠，
/// 所以做成可以在命令行跑的断言：`SafeKeys --selftest`
enum Selftest {

    private static let esc: Int64 = 53
    private static let tab: Int64 = 48
    private static let u: Int64 = 32
    private static let a: Int64 = 0

    /// armedAt = 0，冷却期 2 秒，所以有效输入从 t = 3.0 开始
    private static let start = 3.0

    static func run() {
        var failures: [String] = []

        print("解锁口令引擎自检")
        print("────────────────────────────────")

        escapeFour(&failures)
        alternate(&failures)
        combination(&failures)
        disabled(&failures)
        mainMenuShortcuts(&failures)

        print("────────────────────────────────")
        if failures.isEmpty {
            print("全部通过")
        } else {
            print("失败 \(failures.count) 项：")
            for item in failures { print("  - \(item)") }
        }
    }

    // MARK: - 用例

    private static func escapeFour(_ failures: inout [String]) {
        print("Esc ×4")

        expect(tag("正确口令解锁"), true, feed(.escapeFour, [esc, esc, esc, esc]), &failures)
        expect(tag("只按三次不放行"), false, feed(.escapeFour, [esc, esc, esc]), &failures)
        expect(tag("按五次也能解锁（多按不算错）"), true, feed(.escapeFour, [esc, esc, esc, esc, esc]), &failures)
        expect(tag("中间碰到别的键要重来"), false, feed(.escapeFour, [esc, a, esc, esc, esc]), &failures)
        expect(tag("间隔太慢不算"), false, feed(.escapeFour, [esc, esc, esc], gaps: [0.4, 0.4, 1.2]), &failures)
        expect(tag("间隔太快要重来"), false, feed(.escapeFour, [esc, esc, esc, esc], gaps: [0.05]), &failures)
        expect(tag("按住不放的重复事件不算"), false, feed(.escapeFour, [esc, esc, esc, esc], repeats: [1]), &failures)

        // 冷却期内的按键直接忽略
        var m1 = UnlockPhraseMatcher(phrase: .escapeFour, armedAt: 0)
        let early = m1.feed(key(esc, at: 1.0))
        expect(tag("冷却期内不接受口令"), false, early, &failures)

        // 修饰键打断序列
        var m2 = UnlockPhraseMatcher(phrase: .escapeFour, armedAt: 0)
        _ = m2.feed(key(esc, at: start))
        _ = m2.feed(key(esc, at: start + 0.2))
        m2.interrupt()
        _ = m2.feed(key(esc, at: start + 0.4))
        expect(tag("修饰键打断序列后要重新输入"), false, m2.feed(key(esc, at: start + 0.6)), &failures)
    }

    private static func alternate(_ failures: inout [String]) {
        print("Tab · Esc 交替")

        expect(tag("正确口令解锁"), true, feed(.alternateTabEscape, [tab, esc, tab, esc]), &failures)
        expect(tag("顺序错不放行"), false, feed(.alternateTabEscape, [tab, tab, esc, esc]), &failures)
        expect(tag("只敲 Tab 不放行"), false, feed(.alternateTabEscape, [tab, tab, tab, tab]), &failures)
    }

    private static func combination(_ failures: inout [String]) {
        print("⌘⌥U")

        var m1 = UnlockPhraseMatcher(phrase: .commandOptionU, armedAt: 0)
        expect(
            tag("修饰键齐全才解锁"),
            true,
            m1.feed(key(u, flags: [.maskCommand, .maskAlternate], at: start)),
            &failures
        )

        var m2 = UnlockPhraseMatcher(phrase: .commandOptionU, armedAt: 0)
        expect(
            tag("缺 Option 不放行"),
            false,
            m2.feed(key(u, flags: [.maskCommand], at: start)),
            &failures
        )

        var m3 = UnlockPhraseMatcher(phrase: .commandOptionU, armedAt: 0)
        expect(
            tag("只有修饰键没有主键不放行"),
            false,
            m3.feed(key(a, flags: [.maskCommand, .maskAlternate], at: start)),
            &failures
        )
    }

    private static func disabled(_ failures: inout [String]) {
        print("关闭键盘解锁")

        var m = UnlockPhraseMatcher(phrase: .disabled, armedAt: 0)
        expect(tag("任何按键都不解锁"), false, m.feed(key(esc, at: start)), &failures)
        expect(tag("连按也不解锁"), false, m.feed(key(u, flags: [.maskCommand, .maskAlternate], at: start + 0.2)), &failures)
    }

    // MARK: - 工具

    /// 菜单栏快捷键。
    ///
    /// 这条检查存在的理由：macOS 的 Cmd+Q 不是 AppKit 内建的，它来自菜单栏里
    ///「退出」菜单项上挂的 keyEquivalent。纯 SwiftPM bundle 没有 MainMenu.nib，
    /// 一旦忘了在代码里装配主菜单，表现就是"只能点红叉、按 Cmd+Q 没反应"——
    /// 而且不报错、不崩溃，安静得很容易漏掉。
    private static func mainMenuShortcuts(_ failures: inout [String]) {
        print("菜单栏快捷键")

        let main = MainMenuBuilder.build()
        let items = flatten(main)

        let quit = items.first { $0.keyEquivalent == "q" }
        expect(
            tag("Cmd+Q 绑定到 terminate:"),
            true,
            quit?.action == #selector(NSApplication.terminate(_:)),
            &failures
        )

        let close = items.first { $0.keyEquivalent == "w" }
        expect(
            tag("Cmd+W 绑定到 performClose:"),
            true,
            close?.action == #selector(NSWindow.performClose(_:)),
            &failures
        )

        // 应用菜单若没有自己的 title，菜单栏第一格会显示成空白
        expect(
            tag("应用菜单有标题"),
            true,
            !(main.item(at: 0)?.submenu?.title ?? "").isEmpty,
            &failures
        )

        expect(
            tag("存在「关于」菜单项"),
            true,
            items.contains { $0.title.hasPrefix("关于") && $0.action == #selector(AppDelegate.showAbout(_:)) },
            &failures
        )
    }

    private static func flatten(_ menu: NSMenu) -> [NSMenuItem] {
        var collected: [NSMenuItem] = []
        for item in menu.items {
            collected.append(item)
            if let submenu = item.submenu {
                collected.append(contentsOf: flatten(submenu))
            }
        }
        return collected
    }

    private static func tag(_ name: String) -> String { name }

    private static func expect(_ name: String, _ expected: Bool, _ actual: Bool, _ failures: inout [String]) {
        if actual == expected {
            print("  ✓ \(name)")
        } else {
            print("  ✗ \(name)（期望 \(expected)，实际 \(actual)）")
            failures.append(name)
        }
    }

    private static func key(
        _ code: Int64,
        flags: CGEventFlags = [],
        isRepeat: Bool = false,
        at time: Double
    ) -> UnlockPhraseMatcher.Key {
        UnlockPhraseMatcher.Key(keyCode: code, flags: flags, isRepeat: isRepeat, timestamp: time)
    }

    /// 依次喂入一串按键，返回过程中是否解锁过。
    ///
    /// 用"过程中任意一次命中"而不是"最后一次结果"作为口径，是因为真实场景里
    /// 一旦命中即刻解锁，后续按键不会再进入这段判定 —— 多敲一下不该被判成失败。
    /// gaps 覆盖相邻间隔，repeats 指定哪些序号是 autorepeat 事件。
    private static func feed(
        _ phrase: UnlockPhrase,
        _ codes: [Int64],
        gaps: [Double] = Array(repeating: 0.2, count: 8),
        repeats: Set<Int> = []
    ) -> Bool {
        var matcher = UnlockPhraseMatcher(phrase: phrase, armedAt: 0)
        var time = start
        var unlocked = false
        for (index, code) in codes.enumerated() {
            if index > 0 {
                time += gaps[min(index - 1, gaps.count - 1)]
            }
            if matcher.feed(key(code, isRepeat: repeats.contains(index), at: time)) {
                unlocked = true
            }
        }
        return unlocked
    }
}
