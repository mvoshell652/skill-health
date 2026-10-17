import AppKit
import Observation
import SwiftUI

/// Where in the settings window the person should land.
enum SettingsTarget {
    /// The plugin row: what "Set Up Claude Code Plugin…" and "Update Claude Code Plugin…" in the menu are for.
    case plugin
}

/// A menu bar app has no Dock icon (LSUIElement). While a real window is open it must be
/// a regular app so the window can take focus and appear in Cmd-Tab. Rather than count
/// opens and closes (a missed onDisappear would leave a Dock icon forever), it looks at
/// which titled windows are actually visible every time something opens or closes.
@Observable
final class WindowActivation {
    /// Set by whatever opens the settings window, and cleared by the window once it has scrolled
    /// there. Observed, so a window that is already open follows it.
    var settingsTarget: SettingsTarget?

    /// The app's window-opening action, kept from the first view that had it, so the app delegate
    /// can open the settings window when Skill Health is opened again with none showing.
    @ObservationIgnored private var openWindow: OpenWindowAction?
    @ObservationIgnored private var reopens: Task<Void, Never>?

    init() {
        reopens = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .skillHealthReopened) {
                self?.reopen()
            }
        }
    }

    func remember(_ action: OpenWindowAction) {
        openWindow = action
    }

    /// Opens the settings window, or brings it forward, scrolled to `target` when there is one.
    func showSettings(_ target: SettingsTarget? = nil, using openWindow: OpenWindowAction) {
        remember(openWindow)
        settingsTarget = target
        NSApplication.shared.activate()
        openWindow(id: "main")
    }

    private func reopen() {
        if let openWindow { showSettings(using: openWindow) }
        // The kept action may be one that can't reach a scene, or there may be none yet: if no
        // window has come up a moment later, do what ⌘, does instead.
        Task {
            if openWindow != nil { try? await Task.sleep(for: .milliseconds(500)) }
            if !Self.titledWindowIsVisible { pressSettingsInTheAppMenu() }
        }
    }

    private static var titledWindowIsVisible: Bool {
        NSApplication.shared.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    /// Before any view has handed over the action (the icon is hidden and the window was never
    /// opened this run), do what ⌘, does: press Settings… in the app menu, which opens the window.
    private func pressSettingsInTheAppMenu() {
        NSApplication.shared.activate()
        guard let menu = NSApplication.shared.mainMenu?.items.first?.submenu,
              let item = menu.items.first(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command) })
        else { return }
        menu.performActionForItem(at: menu.index(of: item))
    }

    func windowOpened() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    func windowClosed() {
        Task {
            // Let AppKit finish closing the window before looking.
            await Task.yield()
            if !Self.titledWindowIsVisible { NSApplication.shared.setActivationPolicy(.accessory) }
        }
    }
}

/// Hands the window-opening action of whatever scene this view is in to `WindowActivation`.
private struct RemembersOpenWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(WindowActivation.self) private var windows

    func body(content: Content) -> some View {
        content.onAppear { windows.remember(openWindow) }
    }
}

extension View {
    func remembersOpenWindow() -> some View {
        modifier(RemembersOpenWindow())
    }
}
