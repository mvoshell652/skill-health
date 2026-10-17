import Foundation

/// Renders what the plugin's SessionStart hook prints. The app always renders both the note and the
/// corrections; the plugin's two options (`session_note`, `corrections_for_claude`) decide what the
/// hook prints of them. Corrections go to Claude at every session start; the line the person sees is
/// capped at once a day (the hook script applies the cap, choosing between the two files the app
/// renders), and it says corrections run every session, so a quiet session never hides that they're
/// in effect.
public enum SessionStartHook {
    public static let noteInterval: Duration = .seconds(24 * 60 * 60)

    /// Returns nil for silence. `showsNote` tells the caller to record when the note was shown.
    public static func output(snapshot: StatusSnapshot?, lastNoteAt: Date?, now: Date = .now)
        -> (output: HookOutput, showsNote: Bool)? {
        guard let snapshot else { return nil }
        let noteDue = lastNoteAt.map { .seconds(now.timeIntervalSince($0)) >= noteInterval } ?? true
        let note = noteDue ? snapshot.sessionNote : nil
        let context = correctionsText(snapshot)
        guard note != nil || context != nil else { return nil }
        let specific = context.map { HookOutput.SpecificOutput(additionalContext: $0) }
        return (HookOutput(systemMessage: note, hookSpecificOutput: specific), note != nil)
    }

    /// What Claude is told is true now, cut here. 600 keeps the failing corrections that ship with the
    /// plugin whole (many were cut at the old 300; a test checks they fit), and auditors are asked for
    /// under 400. Still one bounded line, so a hostile finding can't take more room.
    static let trueNowLimit = 600

    /// Dated by when the app wrote the list, not by when each skill was checked: "as of", never "checked".
    static func correctionsText(_ snapshot: StatusSnapshot) -> String? {
        guard !snapshot.corrections.isEmpty else { return nil }
        let asOf = snapshot.writtenAt.formatted(.dateTime.day().month(.abbreviated).year())
        let lines = snapshot.corrections.map {
            "- \(oneLine($0.skillName, 80)) says \"\(oneLine($0.skillSays, 200))\". \(oneLine($0.trueNow, trueNowLimit)) Evidence: \(oneLine($0.source.absoluteString, 200))"
        }
        return (["Skill Health corrections as of \(asOf). If you use these skills, prefer the correction. Mention this only if it becomes relevant."] + lines)
            .joined(separator: "\n")
    }

    /// Correction text comes from audits, which read skill files and web pages. Each field is
    /// kept to one bounded line, so it can't add lines of its own to what Claude is told.
    static func oneLine(_ text: String, _ limit: Int) -> String {
        // Hidden characters go first: tag characters ride on a visible letter and would slip past
        // the length cap, carrying text the person never sees into every session.
        let flat = HiddenText.stripped(text).split(whereSeparator: \.isNewline).joined(separator: " ")
            .filter { !$0.isASCII || $0.asciiValue! >= 0x20 }
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }
}
