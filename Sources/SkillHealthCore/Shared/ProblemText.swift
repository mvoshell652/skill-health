import Foundation

/// The words for Skill Health's own files being unreadable, one place for the app, the tool and the
/// errors, so a person sees the same sentence wherever it shows up. Each says what is wrong, where,
/// and what to do; the system's reason comes last, since it can be long.
public enum ProblemText {
    /// The skills folder can't be listed. Without the list, "no skills" and "nothing to fix" would be untrue.
    public static func skillsUnreadable(_ folder: String, _ why: String) -> String {
        "Skill Health couldn't list the skills in \(folder), so it can't say what needs fixing. Check that it is a folder you can read. \(why)"
    }

    /// findings.json can't be read as a whole.
    public static func resultsUnreadable(_ why: String) -> String {
        "Skill Health couldn't read the results of earlier checks (~/.claude/skill-health/findings.json). Move the file aside, then run /skill-health:check again. \(why)"
    }

    /// Some entries of findings.json can't be read; the rest can.
    public static func resultsPartlyUnreadable(_ count: Int) -> String {
        count == 1 ? "1 instruction in the results of earlier checks couldn't be read, so it isn't shown."
            : "\(count.formatted()) instructions in the results of earlier checks couldn't be read, so they aren't shown."
    }

    /// decisions.json can't be read: what the person fixed or set aside. Moving it aside costs
    /// something, so the remedy says what.
    public static func decisionsUnreadable(_ why: String) -> String {
        "Skill Health couldn't read what you fixed or set aside (~/.claude/skill-health/decisions.json), so it won't change it until it can. Moving the file aside starts over: what you set aside opens again, and Skill Health can no longer undo its fixes (the old files stay in ~/.claude/skill-health/backups). \(why)"
    }

    /// compare.json can't be read: the last comparison with GitHub.
    public static func compareUnreadable(_ why: String) -> String {
        "Skill Health couldn't read its last comparison with GitHub (~/.claude/skill-health/compare.json), so newer copies aren't known. Comparing again replaces it. \(why)"
    }

    /// Why a file of Skill Health's couldn't be read, in words: the system's own sentence for a JSON
    /// problem ("The data couldn't be read because it is missing") names nothing.
    public static func reason(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        func place(_ path: [any CodingKey]) -> String {
            path.reduce("") { text, key in key.intValue.map { "\(text)[\($0)]" } ?? (text.isEmpty ? key.stringValue : "\(text).\(key.stringValue)") }
        }
        switch error {
        case .keyNotFound(let key, let context):
            let at = place(context.codingPath)
            return at.isEmpty ? "It has no \(key.stringValue)." : "\(at) has no \(key.stringValue)."
        case .valueNotFound(_, let context), .typeMismatch(_, let context):
            let at = place(context.codingPath)
            return at.isEmpty ? "It isn't in the form Skill Health writes." : "\(at) isn't the kind of value Skill Health writes."
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty ? "It isn't valid JSON." : "\(place(context.codingPath)) isn't a value Skill Health writes."
        @unknown default:
            return "It isn't in the form Skill Health writes."
        }
    }
}
