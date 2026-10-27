import Foundation

/// 主线程监护人。
///
/// Event tap 的回调运行在主线程 RunLoop 上。一旦主线程死锁或陷入死循环，
/// 回调不再被调用，全系统键盘输入随之卡死，而且 UI 也点不动了 ——
/// 这是唯一真正收不了场的灾难场景。
///
/// 因此起一条完全独立于 RunLoop 的线程，只做一件事：
/// 盯着主线程心跳，停了就先释放 tap、再让进程退出（退出即解锁）。
final class Watchdog {

    static let shared = Watchdog()

    /// 心跳超过这个秒数即判定主线程已经无法响应
    private static let stallThreshold: TimeInterval = 3.0
    private static let pollInterval: TimeInterval = 0.5

    private let lock = NSLock()
    private var lastBeatAt: TimeInterval = 0
    private var thread: Thread?
    private var running = false

    var onStall: (() -> Void)?

    private init() {}

    func start() {
        guard thread == nil else { return }
        running = true
        beat()

        let worker = Thread { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: Self.pollInterval)
                guard let self = self else { return }
                if !self.running { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - self.latestBeat()
                if elapsed > Self.stallThreshold {
                    self.onStall?()
                    Thread.sleep(forTimeInterval: 0.3)
                    exit(88)
                }
            }
        }
        worker.name = "SafeKeys.watchdog"
        worker.stackSize = 1 << 19
        thread = worker
        worker.start()
    }

    func stop() {
        running = false
    }

    /// 主线程 RunLoop 每轮都要调用
    func beat() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        lastBeatAt = now
        lock.unlock()
    }

    private func latestBeat() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return lastBeatAt
    }
}
