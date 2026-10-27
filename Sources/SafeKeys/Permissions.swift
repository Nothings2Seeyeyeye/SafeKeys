import ApplicationServices
import AppKit
import Foundation

enum Permissions {
    /// 是否已经获得辅助功能权限（CGEventTap 拦截的前提）
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统授权弹窗并返回当前状态
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}
