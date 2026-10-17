import AppKit

extension Notification.Name {
    /// Posted when Skill Health is opened again while it is running and no window is showing.
    static let skillHealthReopened = Notification.Name("skillHealth.reopened")
}

/// A Window-first SwiftUI app quits when its last window closes. Skill Health lives on in the menu
/// bar (and keeps status.json current for the hook), so closing the window must not quit it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening Skill Health again (Finder, Spotlight, the Dock) while it runs with every window closed
    /// brings the settings window back: with the menu bar icon hidden it is the only way in. A
    /// delegate can't open a SwiftUI window itself, so it says so and `WindowActivation`, which holds
    /// the app's window-opening action, does it. Always true: the system's own handling still runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The flag can count windows a person can't use (the menu bar's own), so ask for a real one.
        let showing = sender.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if !showing { NotificationCenter.default.post(name: .skillHealthReopened, object: nil) }
        return true
    }
}
