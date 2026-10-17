import Foundation

/// ~/.claude/skill-health/audit-plan.json: what /skill-health:audit offers to check and what it would cost,
/// written by the app (which knows usage and sizes) for the skill in Claude Code to ask with.
/// The skill asks scope, then cost, then runs; this file only informs the questions.
public struct AuditPlanFile: Codable, Sendable, Equatable {
    public struct Candidate: Codable, Sendable, Equatable {
        public let name: String
        public let folder: String
        public let loads: Int
        public let files: Int
        public let bytes: Int
        public let lastAudited: Date?
        public let repo: String?
        /// When the copy was installed, from its receipt: what the auditor dates `written:` from.
        public let installedAt: Date?
    }

    public var version = 1
    public let writtenAt: Date
    public let skillsFolder: String
    public let tokensPerSkill: Int
    /// The spec's first scope option: the most-used skills never audited, at most six.
    public let mostUsedNeverAudited: [String]
    /// Every skill used in the last 90 days, most loads first.
    public let used: [Candidate]

    public static func make(skills: [Skill], audited: [String: Date], skillsFolder: URL, now: Date = .now) -> AuditPlanFile {
        let used = skills.filter(\.isUsed).sorted { ($0.usesLast90Days, $1.name) > ($1.usesLast90Days, $0.name) }
        let candidates = used.map { skill in
            let sizes = Self.sizes(of: skill.folder)
            return Candidate(name: skill.name, folder: skill.folder.path(percentEncoded: false), loads: skill.usesLast90Days,
                             files: sizes.files, bytes: sizes.bytes, lastAudited: audited[skill.name], repo: skill.origin?.repo,
                             installedAt: skill.origin?.installedAt)
        }
        return AuditPlanFile(writtenAt: now, skillsFolder: skillsFolder.path(percentEncoded: false),
                             tokensPerSkill: AuditPlan.tokensPerSkill,
                             mostUsedNeverAudited: Array(candidates.filter { $0.lastAudited == nil }.prefix(6).map(\.name)),
                             used: candidates)
    }

    public static func sizes(of folder: URL) -> (files: Int, bytes: Int) {
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return (0, 0) }
        var files = 0, bytes = 0
        for case let file as URL in walk {
            if file.pathComponents.contains(".git") { continue }
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            files += 1
            bytes += values.fileSize ?? 0
        }
        return (files, bytes)
    }
}
