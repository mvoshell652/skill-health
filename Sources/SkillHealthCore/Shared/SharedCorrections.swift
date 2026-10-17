import Foundation

/// Shared corrections: findings tied to a skill file's exact contents, so one audit corrects every
/// identical copy, on any Mac, with no tokens spent and no plugin. A snapshot ships inside the app;
/// a published list can refresh it. A finding applies to a skill when the file it names has exactly
/// the git blob id the correction was found in, so a folder name, a missing install record or an
/// unrelated edit elsewhere in the skill doesn't matter. Skill folders checked whole and found clean
/// are listed too, so an identical copy can honestly count as checked.
public struct SharedCorrections: Codable, Sendable, Equatable {
    public struct Correction: Codable, Sendable, Equatable {
        /// Git blob id of the file the quote is in: the whole match key.
        public let blob: String
        public let file: String
        /// Where it was found, for the person to see: the skill's folder name and its source.
        public let skill: String
        public let repo: String?
        public let severity: Severity
        public let skillSays: String
        public let trueNow: String
        public let source: URL
        /// undated, written:YYYY-MM-DD or since:YYYY-MM-DD, as the audit dated it.
        public let wrongSince: String?
        public let suggestedText: String?
        public let checkedOn: Date
        public let keptBySecondCheck: Bool
    }

    /// A skill folder checked whole: the fingerprint of its files, and when.
    public struct Checked: Codable, Sendable, Equatable {
        public let tree: String
        public let skill: String
        public let checkedOn: Date
    }

    public var version = 1
    public var updatedAt: Date
    public var corrections: [Correction]
    public var checked: [Checked]

    /// One string for a skill folder's files (path=blob, sorted), the key for "checked whole".
    public static func tree(of files: [String: String]) -> String {
        GitBlob.id(of: Data(files.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n").utf8))
    }

    /// The findings and checks that apply to one installed skill, from its files as they are now.
    public func matches(skill: Skill, files: [String: String]) -> (findings: [Finding], checkedOn: Date?) {
        let findings = corrections.filter { files[$0.file] == $0.blob }.map { correction in
            Finding(id: FindingID.make(skill: skill.name, file: correction.file, quote: correction.skillSays),
                    skillName: skill.name, severity: correction.severity, skillSays: correction.skillSays,
                    trueNow: correction.trueNow, source: correction.source, foundOn: correction.checkedOn,
                    wrongSince: WrongSince(label: correction.wrongSince), file: correction.file == "SKILL.md" ? nil : correction.file,
                    suggestedText: correction.suggestedText, keptBySecondCheck: correction.keptBySecondCheck,
                    sharedFrom: [correction.repo, correction.skill].compactMap(\.self).joined(separator: " · "))
        }
        let tree = Self.tree(of: files)
        let checkedOn = checked.filter { $0.tree == tree }.map(\.checkedOn).max()
        return (findings, checkedOn)
    }
}

extension WrongSince {
    /// From the audit's label: written:YYYY-MM-DD, installed:YYYY-MM-DD, since:YYYY-MM-DD, or anything else as undated.
    public init(label: String?) {
        let parts = (label ?? "").split(separator: ":", maxSplits: 1).map(String.init)
        let date = parts.count == 2 ? try? Date(parts[1] + "T00:00:00Z", strategy: .iso8601) : nil
        switch (parts.first, date) {
        case ("written", let date?): self = .written(on: date)
        case ("installed", let date?): self = .installed(on: date)
        case ("since", let date?): self = .since(date: date)
        default: self = .undated
        }
    }
}
