import Foundation

/// The switches that change what Skill Health does on its own. Stored in ~/.claude/skill-health/settings.json,
/// not in the app's defaults, so the command-line tool reads the same choices the person made in the app.
public struct Settings: Codable, Sendable, Hashable {
    /// Kept so a settings.json written by an older Skill Health still decodes and is written back as it
    /// was. Unused: the plugin's own option (`session_note`) decides now, and the app always renders
    /// the note.
    public var sessionNote = true
    /// Kept for older files, like `sessionNote`. Unused: the plugin's `corrections_for_claude`
    /// option decides now, and the app always renders the corrections.
    public var correctionsForClaude = true
    /// Compare with GitHub once a day, after the person has made the first comparison.
    public var dailyCheck = true

    public init(sessionNote: Bool = true, correctionsForClaude: Bool = true, dailyCheck: Bool = true) {
        self.sessionNote = sessionNote
        self.correctionsForClaude = correctionsForClaude
        self.dailyCheck = dailyCheck
    }

    /// A settings file written before a switch existed keeps its choices and gets the new
    /// switch's default, instead of failing to load.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        sessionNote = try values.decodeIfPresent(Bool.self, forKey: .sessionNote) ?? defaults.sessionNote
        correctionsForClaude = try values.decodeIfPresent(Bool.self, forKey: .correctionsForClaude) ?? defaults.correctionsForClaude
        dailyCheck = try values.decodeIfPresent(Bool.self, forKey: .dailyCheck) ?? defaults.dailyCheck
    }
}
