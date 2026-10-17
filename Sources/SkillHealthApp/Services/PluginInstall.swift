import Foundation

/// How a person installs the Skill Health plugin. The app never installs it: the person runs this in
/// Terminal (App Review 2.4.5 and 2.5.2: an app may not install code into another tool).
enum PluginInstall {
    /// The marketplace holding the plugin: a GitHub repository once it's published; this
    /// package's own folder in a debug build, so the plugin can be tried before then.
    static var marketplace: String {
        #if DEBUG
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().path(percentEncoded: false)
        return root.hasSuffix("/") ? String(root.dropLast()) : root
        #else
        "mvoshell652/skill-health"
        #endif
    }

    /// One line for Terminal. The command-line form works on every Claude Code version; the
    /// in-session /plugin install with a marketplace needs a newer one.
    static var command: String {
        "claude plugin marketplace add \(quoted(marketplace)) && claude plugin install skill-health@skill-health"
    }

    /// What to run when the plugin is older than the app needs. Same shell, same plugin.
    static let updateCommand = "claude plugin update skill-health@skill-health"

    private static func quoted(_ text: String) -> String {
        text.contains(" ") ? "'\(text.replacing("'", with: "'\\''"))'" : text
    }
}
