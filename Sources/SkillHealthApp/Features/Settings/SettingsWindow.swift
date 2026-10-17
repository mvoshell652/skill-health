import SwiftUI

/// Skill Health's one window: setting it up, and its settings afterwards. Opened by Settings… (⌘,)
/// in the menu, at first launch, and whenever Skill Health is opened with no menu bar icon to reach.
struct SettingsWindow: View {
    @Environment(WindowActivation.self) private var windows

    var body: some View {
        SettingsForm()
            .frame(width: Layout.mainWindowWidth)
            // As tall as its contents, up to a cap; past it the form scrolls and Not Now stays put.
            .frame(maxHeight: Layout.mainWindowMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear(perform: windows.windowOpened)
            .onDisappear(perform: windows.windowClosed)
            .remembersOpenWindow()
    }
}
