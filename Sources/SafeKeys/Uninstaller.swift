import Foundation

/// 自我清理。
///
/// 目标是「卸载之后系统里找不出这个 App 存在过的痕迹」：
/// 除了 App 本体（由脚本删除），还包括 UserDefaults、缓存、存档状态、
/// 以及最容易被人忘记的 TCC 隐私授权记录（辅助功能 / 输入监控）。
enum Uninstaller {

    static let bundleID = "cn.open-book.SafeKeys"
    static let appName = "SafeKeys"

    // MARK: - 残留清单

    /// 所有可能的残留路径（白名单，不做任何通配搜索）
    static var residuePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lib = "\(home)/Library"
        return [
            "\(lib)/Preferences/\(bundleID).plist",
            "\(lib)/Application Support/\(appName)",
            "\(lib)/Application Support/\(bundleID)",
            "\(lib)/Caches/\(bundleID)",
            "\(lib)/Caches/\(bundleID).userDiagnosticReports",
            "\(lib)/HTTPStorages/\(bundleID)",
            "\(lib)/HTTPStorages/\(bundleID).binarycookies",
            "\(lib)/Saved Application State/\(bundleID).savedState",
            "\(lib)/Logs/\(appName)",
            "\(lib)/LaunchAgents/\(bundleID).plist",
            "\(lib)/LaunchAgents/\(bundleID).helper.plist",
            "\(lib)/Containers/\(bundleID)",
        ]
    }

    /// TCC 服务名：macOS 不同版本对「输入监控」的叫法不同，一并尝试
    static let tccServices = ["Accessibility", "InputMonitoring", "ListenEvent"]

    // MARK: - 执行

    /// 删除用户级残留，并重置隐私授权记录。返回删除失败的路径。
    @discardableResult
    static func clean(verbose: Bool = true) -> [String] {
        let fm = FileManager.default
        var failed: [String] = []

        if verbose { print("==> 清理用户数据与缓存") }

        for path in residuePaths {
            guard fm.fileExists(atPath: path) else { continue }
            do {
                try fm.removeItem(atPath: path)
                if verbose { print("    已删除 \(relative(path))") }
            } catch {
                failed.append(path)
                if verbose { print("    !! 无法删除 \(relative(path))：\(error.localizedDescription)") }
            }
        }

        if verbose { print("==> 重置隐私授权记录") }
        var tccOK = false
        for service in tccServices {
            let status = shell("/usr/bin/tccutil", ["reset", service, bundleID])
            if status == 0 { tccOK = true }
        }
        if verbose {
            print(tccOK
                  ? "    已清除辅助功能 / 输入监控授权条目"
                  : "    未找到可清除的授权条目（可能本来就没授权过，或需要用户输入密码）")
        }

        return failed
    }

    /// 校验清单，返回仍然存在的项目
    static func leftovers() -> [String] {
        residuePaths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    private static func relative(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    @discardableResult
    private static func shell(_ executable: String, _ args: [String]) -> Int32 {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return -1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
