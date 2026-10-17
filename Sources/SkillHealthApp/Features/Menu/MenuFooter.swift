import SwiftUI

/// What every state of the menu ends with: Settings… (⌘,) and Quit Skill Health (⌘Q).
struct MenuFooter: View {
    /// A header with no items of its own, set directly above Settings….
    let leadingHeader: String?
    let showSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        if let leadingHeader {
            Section(leadingHeader) { SettingsMenuButton(show: showSettings) }
        } else {
            Section { SettingsMenuButton(show: showSettings) }
        }
        Section {
            Button("Quit Skill Health", action: quit)
                .keyboardShortcut("q")
        }
    }
}
