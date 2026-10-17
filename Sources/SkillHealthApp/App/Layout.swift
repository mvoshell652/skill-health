import AppKit

/// Default window sizes in one place. Everything inside the windows flexes.
enum Layout {
    /// The main window is as tall as its steps; only its width is set.
    static let mainWindowWidth = 520.0
    /// Past this the window stops growing and its form scrolls, so Done stays on screen.
    static var mainWindowMaxHeight: Double {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.8
    }
    /// The evidence window for one skill.
    static let evidenceWindowWidth = 560.0
}
