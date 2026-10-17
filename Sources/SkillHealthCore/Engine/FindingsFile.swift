import Foundation

/// ~/.claude/skill-health/findings.json. Versioned, and it records which skills were audited
/// and when, so a clean report can say what it covered.
public struct FindingsFile: Codable, Sendable, Hashable {
    public static let currentVersion = 1

    public var version = Self.currentVersion
    public var findings: [Finding]
    /// Skill name to the date of its last audit.
    public var audited: [String: Date]
    /// Skill name to the fingerprint of its files when that audit was saved (`SharedCorrections.tree`),
    /// so a check can leave out a skill whose files haven't changed since. Missing for checks saved
    /// before Skill Health 0.4.2: such a skill counts as changed.
    public var trees: [String: String] = [:]

    /// Findings in the file that couldn't be read, so they're left out. Not written back.
    public var unreadable = 0

    public init(findings: [Finding] = [], audited: [String: Date] = [:], trees: [String: String] = [:]) {
        self.findings = findings
        self.audited = audited
        self.trees = trees
    }

    enum CodingKeys: String, CodingKey { case version, findings, audited, trees }

    /// One bad finding costs that finding, not the file: every other skill's findings still load.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        audited = try values.decodeIfPresent([String: Date].self, forKey: .audited) ?? [:]
        trees = (try? values.decodeIfPresent([String: String].self, forKey: .trees)) ?? [:]
        var list = try values.nestedUnkeyedContainer(forKey: .findings)
        var findings: [Finding] = []
        while !list.isAtEnd {
            if let finding = try? list.decode(Finding.self) {
                findings.append(finding)
            } else {
                _ = try? list.decode(Skipped.self)
                unreadable += 1
            }
        }
        self.findings = findings
    }

    private struct Skipped: Decodable {}
}
