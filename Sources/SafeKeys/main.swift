import AppKit
import Dispatch
import Foundation

// `--selftest`：验证解锁口令引擎的判定规则，不涉及任何系统权限
if CommandLine.arguments.contains("--selftest") {
    Selftest.run()
    exit(0)
}

// `--uninstall`：命令行自我清理，清完立即退出，不启动界面
if CommandLine.arguments.contains("--uninstall") {
    Uninstaller.clean(verbose: true)
    let left = Uninstaller.leftovers()
    if left.isEmpty {
        print("\nSafeKeys 配置与授权记录已全部清除。")
    } else {
        print("\n以下项目需要手动处理：")
        for item in left { print("  - \(item)") }
    }
    exit(0)
}

// MARK: - 兜底：任何正常/异常退出路径都释放事件劫持
// Event tap 是进程资源，进程消亡时内核必然回收；这里是双保险，
// 保证在退出流程尚未走到 endpoint 时键盘就已经恢复。

atexit {
    KeyBlocker.shared.emergencyRelease()
}

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        KeyBlocker.shared.emergencyRelease()
        NSApp.terminate(nil)
    }
    source.resume()
    signalSources.append(source)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
