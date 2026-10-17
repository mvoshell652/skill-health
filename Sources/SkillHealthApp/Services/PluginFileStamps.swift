import Foundation
import SkillHealthCore

/// When each file the plugin writes in ~/.claude/skill-health was last modified. Skill Health writes into the
/// same folder (status.json, the hook's files, its settings and usage cache), so a change somewhere
/// in it proves nothing; a change to one of these five does. Comparing against the stamps last seen
/// is how the app notices Claude Code's work, and never refreshes itself in a loop.
struct PluginFileStamps: Equatable {
    var findings: Date?
    var decisions: Date?
    var updates: Date?
    var compare: Date?
    var handshake: Date?

    init(paths: SkillHealthPaths) {
        findings = Self.modified(paths.findings)
        decisions = Self.modified(paths.decisions)
        updates = Self.modified(paths.updateRecords)
        compare = Self.modified(paths.compare)
        handshake = Self.modified(paths.pluginHandshake)
    }

    private static func modified(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)))?[.modificationDate] as? Date
    }
}
