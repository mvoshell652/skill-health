import Foundation

/// The contents of ~/.claude/skill-health/status.json: the only thing the plugin's
/// SessionStart hook reads. Small and versioned so the hook never has to guess.
public struct StatusSnapshot: Codable, Sendable, Hashable {
    public static let currentVersion = 1

    public let version: Int
    public let writtenAt: Date
    /// One line for the person, or nil for silence (never an "all clear").
    public let sessionNote: String?
    /// At most five: failing findings in skills used in the last 90 days.
    public let corrections: [Correction]

    public init(writtenAt: Date = .now, sessionNote: String?, corrections: [Correction]) {
        self.version = Self.currentVersion
        self.writtenAt = writtenAt
        self.sessionNote = sessionNote
        self.corrections = Array(corrections.prefix(5))
    }

    /// Same content apart from when it was written: no need to rewrite the file.
    public func sameContent(as other: StatusSnapshot) -> Bool {
        sessionNote == other.sessionNote && corrections == other.corrections
    }

    /// The note's last sentence when something fails. The plugin's SessionStart hook removes it,
    /// word for word, when the person has turned Corrections for Claude off (a test keeps the two equal).
    public static let correctionsTail = "Claude gets the corrections at the start of every session."

    /// Built from `Urgency`, the same rule as the menu bar icon. The note and the corrections are
    /// always both rendered: whether the person sees the note and whether Claude gets the corrections
    /// is the plugin's call now (its two options, `/plugin configure skill-health`), so the app no longer
    /// withholds either.
    public static func make(findings: [Finding], skills: [Skill], now: Date = .now) -> StatusSnapshot {
        let urgent = Urgency.findings(findings, skills: skills, now: now)
        let failing = urgent.filter { $0.severity == .breaks }
        let deprecated = urgent.filter { $0.severity == .deprecated }

        // The same wrong line quoted from two files of one skill is one correction for Claude.
        var seen: Set<[String]> = []
        let corrections = failing
            .filter { seen.insert([$0.skillName, $0.skillSays]).inserted }
            .map { Correction(skillName: $0.skillName, skillSays: $0.skillSays, trueNow: $0.trueNow, source: $0.source) }

        let note: String? = if !failing.isEmpty {
            noteLine(failing, predicate: "instructions that now fail", tail: correctionsTail)
        } else if !deprecated.isEmpty {
            noteLine(deprecated, predicate: "deprecated instructions", tail: nil)
        } else {
            nil
        }
        return StatusSnapshot(writtenAt: now, sessionNote: note, corrections: corrections)
    }

    /// The same, from before the plugin's options replaced the app's two switches. The settings are
    /// ignored: both the note and the corrections are always rendered.
    @available(*, deprecated, message: "The app no longer withholds the note or the corrections; call make(findings:skills:now:).")
    public static func make(findings: [Finding], skills: [Skill], settings: Settings, now: Date = .now) -> StatusSnapshot {
        make(findings: findings, skills: skills, now: now)
    }

    /// "skill-health: 2 skills you use have instructions that now fail (gcp-cloud-run, supabase). Run
    /// /skill-health:fix to go through them." Names in alphabetical order, so the line doesn't change
    /// when findings.json is rewritten in another order.
    private static func noteLine(_ findings: [Finding], predicate: String, tail: String?) -> String {
        let (subject, list) = SkillCount.parts(findings.map(\.skillName).sorted(), verb: ("has", "have"))
        let sentence = "skill-health: \(subject) \(predicate) \(list)."
        return [sentence, "Run /skill-health:fix to go through them.", tail].compactMap(\.self).joined(separator: " ")
    }
}
