import Foundation

/// How Skill Health reaches Claude Code: the plugin, installed by the person from Claude Code itself.
public struct ClaudeCodeLink: Sendable, Equatable {
    public let installed: Bool
    /// When the plugin's hook last ran, which is when Claude Code last read Skill Health's notes.
    public let lastRead: Date?

    public init(installed: Bool, lastRead: Date?) {
        self.installed = installed
        self.lastRead = lastRead
    }

    public var isConnected: Bool { lastRead != nil }
}
