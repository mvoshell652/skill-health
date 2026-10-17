import Accessibility
import SwiftUI
import SkillHealthCore

/// The one-time offer to open Skill Health at login, shown in the setup window once a real folder is ready. It
/// is a plain choice: "Open at Login" turns it on, "No Thanks" is remembered so the offer is never made
/// again (the switch under "On this Mac" stays for later). Both buttons are ordinary: the window's one
/// filled button is the step its top line names (Choose Folder, Copy Command), and this side question
/// must not compete with it or answer Return meant for it. If macOS needs the person's approval, or
/// refuses, the switch's row below says so, and speaks it: it reads the same state.
struct LoginOfferRow: View {
    @Environment(LoginItem.self) private var loginItem
    @Binding var answered: Bool

    /// A debug launch (-debugShowLoginOffer YES) shows the offer to check its layout. Its buttons do nothing
    /// then: a sample must not be able to register the person's real login item.
    private var inert: Bool {
        #if DEBUG
        DebugSnapshot.showsLoginOffer
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(SettingsText.loginOfferTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(SettingsText.loginOfferNote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(SettingsText.loginOfferDecline) {
                    guard !inert else { return }
                    answered = true
                }
                Button(SettingsText.loginOfferAccept) {
                    guard !inert else { return }
                    loginItem.set(true)
                    answered = true
                    if loginItem.isOn { AccessibilityNotification.Announcement(SettingsText.launchAtLoginOn).post() }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
