import Foundation

/// Where the Claude Code plugin stands, as far as Skill Health can tell. Only the plugin's own hook can
/// prove it is connected, so this is built from what the hook leaves behind.
public enum PluginState: Sendable, Equatable {
    /// Claude Code has no Skill Health plugin and has never run its hook.
    case notInstalled
    /// Claude Code lists the plugin, but its hook hasn't run yet: it connects the next time Claude
    /// Code starts, which opening a command from the menu does.
    case installedNotConnected
    /// The hook has run and the plugin is new enough for the commands the menu opens.
    case connected
    /// The hook has run, but the plugin is older than this app's menu needs.
    case older

    /// - Parameters:
    ///   - installed: Claude Code's own record lists the plugin (only a hint: an internal format).
    ///   - lastRead: when `hook-read` was last touched, which every plugin version does.
    ///   - handshake: plugin.json, which a plugin from 0.4.0 on writes.
    public init(installed: Bool, lastRead: Date?, handshake: PluginHandshake?) {
        if let handshake {
            self = handshake.isAtLeastMinimum ? .connected : .older
        } else if lastRead != nil {
            // An older plugin touched hook-read but knew nothing of plugin.json.
            self = .older
        } else if installed {
            self = .installedNotConnected
        } else {
            self = .notInstalled
        }
    }

    /// Whether the menu may open Claude Code with a command. An installed plugin that hasn't connected
    /// yet counts: the new session the command opens is what connects it.
    public var canHandOff: Bool { self == .connected || self == .installedNotConnected }
}
