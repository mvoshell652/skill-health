import Accessibility
import AppKit
import SwiftUI
import SkillHealthCore

/// Launch at login, including the state where macOS needs the person's approval in
/// System Settings: the switch can't fix that, so the row says so and links there. The status
/// is read again whenever Skill Health becomes active, which is how the person comes back from there.
struct LoginItemRow: View {
    @Environment(LoginItem.self) private var loginItem

    var body: some View {
        // Drawn from the real status every time, never from a copy that could be a frame behind.
        NotedToggle("Launch at login", note: SettingsText.launchAtLoginNote,
                    isOn: Binding(get: { loginItem.isOn }, set: loginItem.set))
            .onChange(of: loginItem.status) { old, new in
                // Approval was the last step; the person won't see the switch change otherwise.
                if old == .requiresApproval, new == .enabled {
                    AccessibilityNotification.Announcement(SettingsText.launchAtLoginOn).post()
                }
            }
            .onChange(of: loginItem.attempts) {
                // A refusal, or a needed approval, only adds a row below, and VoiceOver doesn't notice a
                // row appearing. Success is spoken by the switch itself, or by the offer's button.
                if let words = loginItem.lastError ?? (loginItem.needsApproval ? SettingsText.needsApproval : nil) {
                    AccessibilityNotification.Announcement(words).post()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                loginItem.reload()
            }
        if loginItem.needsApproval {
            LabeledContent {
                Button("Open Login Items", action: loginItem.openLoginItemsSettings)
            } label: {
                WarningLabel(SettingsText.needsApproval)
            }
        }
        if let message = loginItem.lastError {
            WarningLabel(message)
        }
    }
}
