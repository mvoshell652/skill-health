import Foundation
import Testing
@testable import SkillHealthCore

@Suite("The SessionStart hook is quiet unless it has something true to say")
struct SessionStartHookTests {
    let snapshot = StatusSnapshot(
        sessionNote: "skill-health: 1 skill you use has instructions that now fail (supabase). Run /skill-health:fix to go through them. Claude gets the corrections at the start of every session.",
        corrections: [Correction(skillName: "supabase", skillSays: "npm install -g supabase",
                                 trueNow: "The Supabase CLI refuses global installs.",
                                 source: URL(string: "https://github.com/supabase/cli/issues/4496")!)])

    @Test func noStatusFileMeansSilence() {
        #expect(SessionStartHook.output(snapshot: nil, lastNoteAt: nil) == nil)
    }

    @Test func noteAtMostOnceADayButCorrectionsEverySession() throws {
        let now = Date.now
        let first = try #require(SessionStartHook.output(snapshot: snapshot, lastNoteAt: nil, now: now))
        #expect(first.showsNote)
        #expect(first.output.systemMessage != nil)
        let later = try #require(SessionStartHook.output(snapshot: snapshot, lastNoteAt: now, now: now.addingTimeInterval(3600)))
        #expect(!later.showsNote)
        #expect(later.output.systemMessage == nil)
        #expect(later.output.hookSpecificOutput?.additionalContext.contains("npm install -g supabase") == true)
    }

    @Test func jsonUsesClaudeCodesFieldNames() throws {
        let result = try #require(SessionStartHook.output(snapshot: snapshot, lastNoteAt: nil))
        let json = String(decoding: try JSONEncoder().encode(result.output), as: UTF8.self)
        #expect(json.contains("\"systemMessage\""))
        #expect(json.contains("\"hookEventName\":\"SessionStart\""))
        #expect(json.contains("\"additionalContext\""))
    }

    @Test func correctionsGiveTheEvidenceLinkAsEvidenceNotSource() throws {
        let result = try #require(SessionStartHook.output(snapshot: snapshot, lastNoteAt: nil))
        let context = try #require(result.output.hookSpecificOutput?.additionalContext)
        #expect(context.contains("Evidence: https://github.com/supabase/cli/issues/4496"))
        #expect(!context.contains("Source:"))
    }

    @Test func aSnapshotWithOnlyCorrectionsStillReachesClaudeWithoutANote() throws {
        let quiet = StatusSnapshot(sessionNote: nil, corrections: snapshot.corrections)
        let result = try #require(SessionStartHook.output(snapshot: quiet, lastNoteAt: nil))
        #expect(!result.showsNote)
        #expect(result.output.systemMessage == nil)
        #expect(result.output.hookSpecificOutput != nil)
    }

    /// The shipped corrections run up to 601 characters; the hook used to cut at 300, which left 15 of the 56
    /// failing ones ending mid-sentence. Whole up to the limit, one bounded line beyond it.
    @Test func aCorrectionIsToldWholeUpToTheLimitAndCutBeyondIt() throws {
        func told(_ trueNow: String) throws -> String {
            let one = StatusSnapshot(sessionNote: nil, corrections: [Correction(
                skillName: "s", skillSays: "x", trueNow: trueNow, source: URL(string: "https://example.com/a")!)])
            return try #require(SessionStartHook.correctionsText(one))
        }
        let limit = SessionStartHook.trueNowLimit
        let whole = String(repeating: "a", count: limit)
        #expect(try told(whole).contains(whole + " Evidence:"))
        let cut = try told(whole + "b")
        #expect(!cut.contains(whole + "b"))
        #expect(cut.contains(String(whole.dropLast()) + "… Evidence:"))
        #expect(try told("One.\nTwo.").contains("One. Two. Evidence:"))
    }

    func shippedCorrections() throws -> SharedCorrections {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SharedCorrections.self, from: Data(contentsOf: PluginFiles.plugin.appending(path: "data/corrections.json")))
    }

    @Test func everyShippedFailingCorrectionIsToldWhole() throws {
        let failing = try shippedCorrections().corrections.filter { $0.severity == .breaks }
        #expect(failing.count > 40)
        let over = failing.filter { $0.trueNow.count > SessionStartHook.trueNowLimit }
        #expect(over.isEmpty, "\(over.map(\.skill))")
    }

    /// Claude is told each failing correction as a fact, under "prefer the correction". An audit's own voice
    /// ("I did not run it", "the Node half of the previous finding", "severity lowered by the second check")
    /// is not a fact about the skill's subject, and went out that way once.
    @Test func noShippedCorrectionSpeaksInTheVoiceOfItsAudit() throws {
        let narration = try NSRegularExpression(pattern: #"\b(the|previous|next|this) finding\b|\bsecond (check|look)\b|\bthe audit\b|\bseverity (raised|lowered)\b|\binstalled gcloud\b|\bclaims checked\b|\bI (did|could|inferred|have|am|think)\b|\bmy own\b"#)
        for correction in try shippedCorrections().corrections {
            let text = correction.trueNow
            #expect(narration.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil, "\(correction.skill): \(text)")
        }
    }
}
