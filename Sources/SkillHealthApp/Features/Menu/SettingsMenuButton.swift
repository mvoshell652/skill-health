import SwiftUI

/// Settings… (⌘,) as the menu shows it.
struct SettingsMenuButton: View {
    let show: () -> Void

    var body: some View {
        Button("Settings…", action: show)
            .keyboardShortcut(",")
    }
}
