import CoreGraphics
import Foundation

/// 用户偏好，持久化在标准 UserDefaults
enum Settings {
    private enum Key {
        static let lockDuration = "SafeKeys.lockDurationSeconds"
        static let tapLocation = "SafeKeys.tapLocation"
        static let unlockPhrase = "SafeKeys.unlockPhrase"
    }

    /// 0 表示"不限时"，会被硬上限覆盖
    static var lockDurationSeconds: Double {
        get {
            UserDefaults.standard.object(forKey: Key.lockDuration) as? Double ?? 90
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.lockDuration)
        }
    }

    /// hid = 更底层，能拦住 Cmd+Tab 等系统快捷键；session = 备选，用于对照测试
    static var usesHIDTap: Bool {
        get {
            UserDefaults.standard.object(forKey: Key.tapLocation) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.tapLocation)
        }
    }

    static var unlockPhrase: UnlockPhrase {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.unlockPhrase),
                  let phrase = UnlockPhrase(rawValue: raw) else {
                return .escapeFour
            }
            return phrase
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.unlockPhrase)
        }
    }
}

// MARK: - 解锁口令

/// 键盘解锁口令。
///
/// 设计约束有四条，任意一条不满足都不放行：
///   1. 必须是**多个**按键；
///   2. 相邻的两次间隔要在 0.1–0.8 秒之间 —— 太快是划过去的连击，太慢不像口令；
///   3. 序列中间不能掺杂任何其他按键 —— 擦键盘往往是好几个键一起被蹭到，
///      而人刻意敲口令时只会碰到口令里那几个键；
///   4. 按住不放产生的系统重复事件（autorepeat）不计一次新按下。
///
/// 四条叠加之后，随机擦拭几乎凑不出合法口令，而人看着屏幕提示能明确做出来。
enum UnlockPhrase: String, CaseIterable, Identifiable {
    /// 连按 Esc 四次
    case escapeFour = "esc4"
    /// Tab → Esc → Tab → Esc 交替，随机更难凑
    case alternateTabEscape = "tabEsc"
    /// Cmd + Option + U
    case commandOptionU = "cmdOptU"
    /// 彻底关闭键盘解锁，只剩按钮和倒计时
    case disabled = "off"

    var id: String { rawValue }

    /// 下拉菜单里的短标签
    var label: String {
        switch self {
        case .escapeFour: return "Esc ×4"
        case .alternateTabEscape: return "Tab·Esc 交替"
        case .commandOptionU: return "⌘⌥U"
        case .disabled: return "不用键盘"
        }
    }

    /// 界面上告诉用户该怎么做的完整文案
    var hint: String {
        switch self {
        case .escapeFour:
            return "或连贯地连按 Esc 四次（中间不能碰到别的键）"
        case .alternateTabEscape:
            return "或依次按 Tab → Esc → Tab → Esc"
        case .commandOptionU:
            return "或按住 ⌘⌥ 再按 U"
        case .disabled:
            return "键盘解锁已关闭：只能用下面的按钮，或等倒计时"
        }
    }

    /// 需要按顺序匹配的 keyCode 序列；空数组表示不使用序列模式
    var keySequence: [Int64] {
        switch self {
        case .escapeFour: return [53, 53, 53, 53]          // Esc = 53
        case .alternateTabEscape: return [48, 53, 48, 53]  // Tab = 48, Esc = 53
        case .commandOptionU, .disabled: return []
        }
    }

    /// 组合键模式：(主键, 必须同时按下的修饰键)
    var combination: (keyCode: Int64, flags: CGEventFlags)? {
        switch self {
        case .commandOptionU:
            return (32, [.maskCommand, .maskAlternate])    // U = 32
        default:
            return nil
        }
    }
}

/// 可选的锁定时长
enum DurationChoice: Double, CaseIterable, Identifiable {
    case seconds30 = 30
    case seconds60 = 60
    case seconds90 = 90
    case seconds120 = 120
    case unlimited = 0

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .seconds30: return "30 秒"
        case .seconds60: return "60 秒"
        case .seconds90: return "90 秒"
        case .seconds120: return "2 分钟"
        case .unlimited: return "不限时"
        }
    }
}
