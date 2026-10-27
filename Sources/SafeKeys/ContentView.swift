import SwiftUI

struct ContentView: View {

    @ObservedObject private var manager = LockManager.shared
    @State private var durationChoice: Double = Settings.lockDurationSeconds
    @State private var phraseChoice: String = Settings.unlockPhrase.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader
            actionArea
            Divider()
            durationRow
            phraseRow
            permissionRow
            if let notice = manager.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footnote
        }
        .padding(18)
        .frame(width: 340)
    }

    // MARK: - 子视图

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(manager.phase == .locked ? Color.red : Color.green)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.phase == .locked ? "键盘已锁定" : "键盘正常")
                    .font(.system(size: 15, weight: .medium))
                Text(manager.phase == .locked ? "按键输入已被全部丢弃" : "所有按键输入正在生效")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if manager.phase == .locked {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(countdownText)
                        .font(.system(size: 20, weight: .medium).monospacedDigit())
                    Text("按住解锁")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var actionArea: some View {
        VStack(spacing: 8) {
            ActionButton(
                title: "锁定键盘",
                symbol: "lock.fill",
                tint: .accentColor,
                enabled: manager.phase == .unlocked && manager.permissionGranted
            ) {
                manager.lock()
            }

            HoldToUnlockButton(
                style: .compact,
                enabled: manager.phase == .locked
            ) {
                manager.unlock(reason: .button)
            }
        }
    }

    private var durationRow: some View {
        HStack(spacing: 8) {
            Text("自动解锁")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Picker("", selection: $durationChoice) {
                ForEach(DurationChoice.allCases) { choice in
                    Text(choice.label).tag(choice.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .onChange(of: durationChoice) { newValue in
                Settings.lockDurationSeconds = newValue
            }
            Spacer()
        }
    }

    private var phraseRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("解锁口令")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Picker("", selection: $phraseChoice) {
                    ForEach(UnlockPhrase.allCases) { phrase in
                        Text(phrase.label).tag(phrase.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .onChange(of: phraseChoice) { newValue in
                    Settings.unlockPhrase = UnlockPhrase(rawValue: newValue) ?? .escapeFour
                }
                Spacer()
            }
            Text(Settings.unlockPhrase.hint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .id(phraseChoice)
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: manager.permissionGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundColor(manager.permissionGranted ? .green : .orange)
            Text(manager.permissionGranted ? "辅助功能已授权" : "需要辅助功能权限")
                .font(.system(size: 12))
                .foregroundColor(manager.permissionGranted ? .primary : .orange)
            Spacer()
            if !manager.permissionGranted {
                Button("去设置") {
                    Permissions.requestTrust()
                    Permissions.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
        }
    }

    private var footnote: some View {
        Text("解锁按住按钮 0.8 秒才生效，误点不会解锁。口令要连贯、且中间不能碰到别的键。无论怎么设置，10 分钟是强制解锁上限。")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var countdownText: String {
        let seconds = max(0, Int(manager.remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// 普通点击按钮。
///
/// 命中区域 = 整块矩形：背景必须画在 label 内部，并且显式声明 contentShape。
/// SwiftUI 里追加在外层的 .background() 只负责绘制、不参与命中测试，
/// 结果就是"只有文字那一小块能点"。
private struct ActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(enabled ? tint : Color(NSColor.controlBackgroundColor))
            .foregroundColor(enabled ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .frame(height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .disabled(!enabled)
    }
}
