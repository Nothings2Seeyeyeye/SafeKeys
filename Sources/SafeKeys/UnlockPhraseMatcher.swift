import CoreGraphics
import Foundation

/// 解锁口令判定。
///
/// 刻意不接收 CGEvent：输入被压成一个 keyCode、一组 flags、一个是否重复的标志和一个时间戳。
/// 这样这段逻辑可以在命令行用 `--selftest` 直接验证，不需要真的去按键，
/// 也方便将来调整口令时回归。
///
/// 判定规则（四条同时成立才放行）：
///   1. 必须完整地按下口令里的每一个键；
///   2. 相邻两次按键间隔在 0.1–0.8 秒之间 —— 太快是划过去的连击，太慢不像口令；
///   3. 序列中途任何别的键都会把它打断 —— 擦键盘往往好几个键一起蹭到，
///      而人照着提示敲口令时只会碰到口令里那几个；
///   4. 按住不放产生的系统重复事件不计一次新按下，并且直接打断序列；
///   5. 另有 2 秒冷却期，避开刚锁定、手还没离开键盘的那一下。
struct UnlockPhraseMatcher {

    struct Key {
        let keyCode: Int64
        let flags: CGEventFlags
        let isRepeat: Bool
        let timestamp: Double
    }

    /// 冷却期长度
    static let armingDelay: Double = 2.0
    /// 相邻按键的最小间隔
    static let minGap: Double = 0.10
    /// 相邻按键的最大间隔
    static let maxGap: Double = 0.80

    private let sequence: [Int64]
    private let combination: (keyCode: Int64, flags: CGEventFlags)?

    /// 已匹配的键数
    private(set) var matchedIndex = 0
    private var lastMatchTime: Double = 0
    private let armedAt: Double

    init(phrase: UnlockPhrase, armedAt: Double) {
        self.sequence = phrase.keySequence
        self.combination = phrase.combination
        self.armedAt = armedAt
    }

    /// 喂入一次按键。返回 true 表示口令完成、应当解锁。
    mutating func feed(_ key: Key) -> Bool {
        guard key.timestamp - armedAt > Self.armingDelay else { return false }

        if let combination {
            return matchesCombination(key, with: combination)
        }
        return matchesSequence(key)
    }

    /// 序列被外部事件打断（比如按下了某个修饰键）
    mutating func interrupt() {
        matchedIndex = 0
        lastMatchTime = 0
    }

    // MARK: - 内部判定

    private mutating func matchesSequence(_ key: Key) -> Bool {
        let count = sequence.count
        guard count > 0 else { return false }

        // 4. autorepeat 不计，并且直接打断
        if key.isRepeat {
            interrupt()
            return false
        }

        let code = key.keyCode

        guard code == sequence[matchedIndex] else {
            // 3. 打断了。如果当前键恰好是首键就从头再计，否则彻底归零
            restartOrReset(at: code, now: key.timestamp)
            return false
        }

        if matchedIndex > 0 {
            // 2. 间隔窗口
            let gap = key.timestamp - lastMatchTime
            guard gap >= Self.minGap, gap <= Self.maxGap else {
                restartOrReset(at: code, now: key.timestamp)
                return false
            }
        }

        lastMatchTime = key.timestamp
        matchedIndex += 1

        // 1. 全部匹配完成
        if matchedIndex == count {
            interrupt()
            return true
        }
        return false
    }

    private func matchesCombination(
        _ key: Key,
        with combination: (keyCode: Int64, flags: CGEventFlags)
    ) -> Bool {
        guard !key.isRepeat else { return false }
        guard key.keyCode == combination.keyCode else { return false }
        return key.flags.contains(combination.flags)
    }

    private mutating func restartOrReset(at code: Int64, now: Double) {
        if code == sequence[0] {
            matchedIndex = 1
            lastMatchTime = now
        } else {
            interrupt()
        }
    }
}
