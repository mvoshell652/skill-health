import Foundation

/// ~/.claude/skill-health/plugin.json, written by the plugin's SessionStart hook on every run:
/// `{"version": "0.4.0", "readAt": "2026-10-04T18:00:00Z"}`. How the app knows the plugin is
/// connected, and whether it's new enough for the commands the menu opens.
public struct PluginHandshake: Codable, Sendable, Equatable {
    public let version: String
    public let readAt: Date

    public init(version: String, readAt: Date) {
        self.version = version
        self.readAt = readAt
    }

    /// The oldest plugin whose commands this app's menu opens (/skill-health:check, fix, update, undo).
    public static let minimumVersion = "0.4.0"

    /// Numeric, part by part: "0.10.0" is newer than "0.9.1". A part that isn't a number counts as 0.
    public var isAtLeastMinimum: Bool { Self.compare(version, Self.minimumVersion) >= 0 }

    public static func compare(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }
}
