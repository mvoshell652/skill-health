import SwiftUI

/// Settings… (⌘,) in the app menu opens Skill Health's one window: there is no separate Settings scene.
/// The window activation is handed in: commands don't see the environment the window's content gets.
struct SettingsCommand: View {
    let windows: WindowActivation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            windows.showSettings(using: openWindow)
        }
        .keyboardShortcut(",")
    }
}
