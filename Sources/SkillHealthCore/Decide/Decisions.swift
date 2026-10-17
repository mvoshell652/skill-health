import Foundation

/// ~/.claude/skill-health/decisions.json: where the person decided each finding stands (spec flow F).
/// Written only by the app, and kept apart from findings.json, which audits write, so a new
/// audit can never undo a decision.
public struct DecisionsFile: Codable, Sendable, Equatable {
    public var version = 1
    /// Finding id (uuidString) to its decision.
    public var decisions: [String: Decision] = [:]

    public init() {}

    public subscript(id: UUID) -> Decision? {
        get { decisions[id.uuidString] }
        set { decisions[id.uuidString] = newValue }
    }
}

public struct Decision: Codable, Sendable, Equatable {
    public var status: FindingStatus
    public var decidedAt: Date
    /// Set when the line was patched: what undo needs to put the file back byte for byte.
    public var patch: PatchRecord?
    /// "Until the next update": the source's files for this skill when the finding was set
    /// aside. When they change, the finding comes back, or at its date, whichever is first.
    public var untilSourceChanges: String?
    /// When the person drafted an issue for the author. Noted, but it doesn't close the
    /// finding: the line is still wrong on this Mac.
    public var reportedAt: Date?

    public init(status: FindingStatus, decidedAt: Date, patch: PatchRecord? = nil,
                untilSourceChanges: String? = nil, reportedAt: Date? = nil) {
        self.status = status
        self.decidedAt = decidedAt
        self.patch = patch
        self.untilSourceChanges = untilSourceChanges
        self.reportedAt = reportedAt
    }
}

/// A patch, as written: the file, where the original went, and both versions' git blob ids.
public struct PatchRecord: Codable, Sendable, Equatable {
    public let file: String
    public let backup: String
    public let original: String
    public let written: String

    public init(file: String, backup: String, original: String, written: String) {
        self.file = file
        self.backup = backup
        self.original = original
        self.written = written
    }
}

extension FindingsFile {
    /// The audit's findings with the person's decisions joined in. A finding set aside until the
    /// next update comes back as soon as its skill's source files change, and a patched one comes
    /// back when its file says the wrong line again (an update or a restore can bring it back).
    public func deciding(with decisions: DecisionsFile, sourceFingerprints: [String: String],
                         quoteIsBack: (Finding) -> Bool = { _ in false }) -> FindingsFile {
        var joined = self
        joined.findings = findings.map { finding in
            var decided = finding
            guard let decision = decisions[finding.id] else { return decided }
            decided.status = decision.status
            if let fingerprint = decision.untilSourceChanges,
               let now = sourceFingerprints[finding.skillName], now != fingerprint {
                decided.status = .open
            }
            if case .patched = decision.status, quoteIsBack(finding) {
                decided.status = .open
            }
            return decided
        }
        return joined
    }
}

extension CompareFile.Copy {
    /// One string for the source's files of this skill, to notice when they change.
    public var sourceFingerprint: String {
        (source ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }
}
