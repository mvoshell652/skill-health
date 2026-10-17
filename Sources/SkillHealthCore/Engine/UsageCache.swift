import Foundation

/// ~/.claude/skill-health/usage-cache.json: per session file, the loads found last time it was read.
/// A cache written under other counting rules is discarded, never trusted.
struct UsageCache: Codable, Sendable {
    /// Bump whenever what counts as a load, or what an entry holds, changes.
    static let currentVersion = 2

    /// One successful skill load: the id of the line Claude Code wrote for it (replays of a
    /// resumed or forked session repeat that id), the skill folder's name, and when.
    struct Load: Codable, Sendable, Hashable {
        let id: String
        let skill: String
        let at: Date
    }

    struct Entry: Codable, Sendable {
        let size: Int
        let modified: Date
        /// Nil when the file holds no loads, which is most of them; keeps the cache small.
        let loads: [Load]?
    }

    var version = UsageCache.currentVersion
    var files: [String: Entry] = [:]
}
