import Foundation

/// ~/.claude/skill-health/updates.json: the commit Skill Health updated each skill to. After an update this is
/// the only record that the copy came from a later commit than its install, so it lives in its
/// own file, written per skill the moment that skill's files land, and never rebuilt by a check
/// (compare.json can be reset or overwritten; this can't be reconstructed). A record holds for
/// the install it was made against: a reinstall writes a new receipt and voids it.
public struct UpdateRecords: Codable, Sendable, Equatable {
    public struct Record: Codable, Sendable, Equatable {
        public let repo: String
        public let subpath: String
        /// The receipt's install time when the update was made.
        public let installedAt: Date
        public let commit: String
        public let updatedAt: Date

        public init(repo: String, subpath: String, installedAt: Date, commit: String, updatedAt: Date) {
            self.repo = repo
            self.subpath = subpath
            self.installedAt = installedAt
            self.commit = commit
            self.updatedAt = updatedAt
        }

        /// Still describes this copy: same source, and not reinstalled since (receipt times round
        /// to the second when stored, so within a second is the same install).
        func holds(for origin: Origin) -> Bool {
            repo == origin.repo && subpath == origin.subpath
                && abs(installedAt.timeIntervalSince(origin.installedAt)) < 1
        }
    }

    public var version = 1
    public var records: [String: Record] = [:]

    public init() {}

    /// The commit this skill's copy came from, when Skill Health updated it and it hasn't been
    /// reinstalled or removed since.
    public func commit(for skill: Skill) -> String? {
        guard let origin = skill.origin, let record = records[skill.name], record.holds(for: origin) else { return nil }
        return record.commit
    }

    /// Only the records that still hold for an installed skill.
    public func kept(for skills: [Skill]) -> UpdateRecords {
        var kept = self
        kept.records = records.filter { name, record in
            skills.contains { $0.name == name && $0.origin.map(record.holds) == true }
        }
        return kept
    }
}
