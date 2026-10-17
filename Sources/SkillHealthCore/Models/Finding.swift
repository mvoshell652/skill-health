import Foundation

/// One instruction in one skill that isn't true, with its evidence.
public struct Finding: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let skillName: String
    public let severity: Severity
    /// The exact quote from SKILL.md. Never paraphrased.
    public let skillSays: String
    public let trueNow: String
    public let source: URL
    public let foundOn: Date
    public let wrongSince: WrongSince
    /// Where the person decided this finding stands. Not part of the audit's file: the app
    /// keeps decisions apart (decisions.json) and joins them in when it reads findings.
    public var status: FindingStatus
    /// The file inside the skill that holds the quote; nil means SKILL.md.
    public let file: String?
    /// What the audit suggests the quoted text should say instead. Patching needs it.
    public let suggestedText: String?
    /// An installed skill that already covers this correctly, when the audit found one.
    public let alternative: String?
    /// A second check tried to disprove this finding and couldn't.
    public let keptBySecondCheck: Bool?
    /// Set when the finding comes from the shared corrections: where it was first found (source and
    /// skill). The person's copy of the file is identical to that one, byte for byte.
    public let sharedFrom: String?

    public init(id: UUID = UUID(), skillName: String, severity: Severity, skillSays: String,
                trueNow: String, source: URL, foundOn: Date, wrongSince: WrongSince,
                status: FindingStatus = .open, file: String? = nil, suggestedText: String? = nil,
                alternative: String? = nil, keptBySecondCheck: Bool? = nil, sharedFrom: String? = nil) {
        self.id = id
        self.skillName = skillName
        self.severity = severity
        self.skillSays = skillSays
        self.trueNow = trueNow
        self.source = source
        self.foundOn = foundOn
        self.wrongSince = wrongSince
        self.status = status
        self.file = file
        self.suggestedText = suggestedText
        self.alternative = alternative
        self.keptBySecondCheck = keptBySecondCheck
        self.sharedFrom = sharedFrom
    }

    /// The quote's file inside the skill folder.
    public var filePath: String { file ?? "SKILL.md" }

    enum CodingKeys: String, CodingKey {
        case id, skillName, severity, skillSays, trueNow, source, foundOn, wrongSince, status
        case file, suggestedText, alternative, keptBySecondCheck, sharedFrom
    }

    /// An audit writes findings without a status; every finding starts open.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        skillName = try values.decode(String.self, forKey: .skillName)
        severity = try values.decode(Severity.self, forKey: .severity)
        skillSays = try values.decode(String.self, forKey: .skillSays)
        trueNow = try values.decode(String.self, forKey: .trueNow)
        source = try values.decode(URL.self, forKey: .source)
        foundOn = try values.decode(Date.self, forKey: .foundOn)
        // A date that can't be read costs the finding its date, never the finding.
        wrongSince = (try? values.decodeIfPresent(WrongSince.self, forKey: .wrongSince)) ?? .undated
        status = try values.decodeIfPresent(FindingStatus.self, forKey: .status) ?? .open
        file = try values.decodeIfPresent(String.self, forKey: .file)
        suggestedText = try values.decodeIfPresent(String.self, forKey: .suggestedText)
        alternative = try values.decodeIfPresent(String.self, forKey: .alternative)
        keptBySecondCheck = try values.decodeIfPresent(Bool.self, forKey: .keptBySecondCheck)
        sharedFrom = try values.decodeIfPresent(String.self, forKey: .sharedFrom)
    }

    /// Open, or set aside until a date that has passed: a set-aside comes back on its own.
    public func isOpen(at now: Date = .now) -> Bool {
        switch status {
        case .open: true
        case .setAside(let until): until <= now
        case .patched, .usingAnotherSkill, .notForThisProject: false
        }
    }
}
