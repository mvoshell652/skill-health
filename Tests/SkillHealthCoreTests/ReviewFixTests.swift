import Foundation
import Testing
@testable import SkillHealthCore

/// The M4/M5 review's confirmed findings, each pinned: what the script and the app refuse, what a
/// bad file costs, and when a decided finding comes back.
extension SaveFindingsTests {
    /// Fields the script and the app both refuse: a date that doesn't exist, and characters that
    /// change what Claude reads without showing.
    @Test func refusesImpossibleDatesAndHiddenCharactersInBothPlaces() throws {
        let bad = [
            supabase.replacing("written:2026-02-18", with: "since:2026-13-45"),
            supabase.replacing("written:2026-02-18", with: "since:2026-02-30"),
            supabase.replacing("written:2026-02-18", with: "written:2026-06-00"),
            supabase.replacing("refuses global installs.", with: "refuses global\\u200b installs."),
            supabase.replacing("npx supabase --help", with: "npx supabase --help\\udb40\\udc41\\udb40\\udc42"),
            supabase.replacing("refuses global installs.", with: "refuses \\u202eglobal installs."),
        ]
        for finding in bad {
            let result = try save(#"{"audited":["supabase"],"findings":[\#(finding)]}"#)
            #expect(result.status != 0, "script accepted: \(finding)")
            let decoded = try JSONDecoder().decode(Probe.self, from: Data(finding.utf8))
            #expect(AuditResults.problem(of: decoded.kept) != nil, "app accepted: \(finding)")
        }
        let leap = supabase.replacing("written:2026-02-18", with: "since:2024-02-29")
        #expect(try save(#"{"audited":["supabase"],"findings":[\#(leap)]}"#).status == 0)
    }

    @Test func theSameLineReportedTwiceIsSavedOnce() async throws {
        let result = try save(#"{"audited":["supabase"],"findings":[\#(supabase),\#(supabase)]}"#)
        #expect(result.status == 0, "\(result.output)")
        #expect(try saved().findings.count == 1)
        let kept = AuditResults.Kept(skillName: "supabase", severity: .breaks, skillSays: "npm install -g supabase",
                                     trueNow: "t", source: URL(string: "https://example.com/x")!)
        let merged = AuditResults(audited: ["supabase"], findings: [kept, kept]).merged(into: FindingsFile(), now: .now)
        #expect(merged.findings.count == 1)
    }
}

/// A finding as the save script reads it, for checking the app's rules on the same JSON.
private struct Probe: Decodable {
    let skillName: String, severity: Severity, skillSays: String, trueNow: String, source: URL
    let wrongSince: String?, suggestedText: String?
    var kept: AuditResults.Kept {
        .init(skillName: skillName, severity: severity, skillSays: skillSays, trueNow: trueNow, source: source,
              wrongSince: wrongSince, suggestedText: suggestedText)
    }
}

@Suite("What a bad file costs")
struct BadFileTests {
    @Test func oneUnreadableFindingCostsThatFindingNotTheFile() throws {
        let json = #"""
        {"version":1,"audited":{"vite":"2026-10-01T00:00:00Z"},"findings":[
          {"id":"00000000-0000-4000-8000-000000000001","skillName":"vite","severity":"breaks","skillSays":"a","trueNow":"b","source":"https://example.com/x","foundOn":"2026-10-01T00:00:00Z","wrongSince":{"since":{"date":"2026-13-45T00:00:00Z"}}},
          {"id":"not a uuid","skillName":"vite","severity":"breaks","skillSays":"c","trueNow":"d","source":"https://example.com/y","foundOn":"2026-10-01T00:00:00Z"}
        ]}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(FindingsFile.self, from: Data(json.utf8))
        #expect(file.findings.count == 1)
        #expect(file.findings.first?.wrongSince == .undated)   // its date was unreadable, the finding wasn't
        #expect(file.unreadable == 1)
        #expect(file.audited["vite"] != nil)
    }

    @Test func anUnreadableDecisionsFileIsNeverWrittenOver() async throws {
        let home = URL.temporaryDirectory.appending(path: "skill-health-decisions-\(UUID().uuidString)")
        let engine = Engine(paths: SkillHealthPaths(claudeHome: home))
        try FileManager.default.createDirectory(at: engine.paths.home, withIntermediateDirectories: true)
        #expect(try await engine.loadDecisions() == DecisionsFile())   // no file: no decisions
        try "{half a file".write(to: engine.paths.decisions, atomically: true, encoding: .utf8)
        await #expect(throws: SkillHealthError.self) { try await engine.loadDecisions() }
        await #expect(throws: SkillHealthError.self) {
            try await engine.record(Decision(status: .notForThisProject, decidedAt: .now), for: UUID())
        }
        #expect(try String(contentsOf: engine.paths.decisions, encoding: .utf8) == "{half a file")
    }
}

@Suite("Decided findings")
struct DecidedFindingTests {
    let finding = Finding(skillName: "supabase", severity: .breaks, skillSays: "npm install -g supabase", trueNow: "t",
                          source: URL(string: "https://example.com")!, foundOn: .now, wrongSince: .undated)

    @Test func aPatchedFindingComesBackWhenItsLineDoes() {
        var decisions = DecisionsFile()
        decisions[finding.id] = Decision(status: .patched(on: .now), decidedAt: .now,
                                         patch: PatchRecord(file: "f", backup: "b", original: "o", written: "w"))
        let file = FindingsFile(findings: [finding])
        #expect(file.deciding(with: decisions, sourceFingerprints: [:]).findings[0].status != .open)
        #expect(file.deciding(with: decisions, sourceFingerprints: [:]) { _ in false }.findings[0].status != .open)
        #expect(file.deciding(with: decisions, sourceFingerprints: [:]) { _ in true }.findings[0].status == .open)
    }

    @Test func aDiffShowsHiddenCharactersAndTheSessionNoteDropsThem() {
        #expect(HiddenText.revealed("npx\u{200B} supabase") == "npx⟨U+200B⟩ supabase")
        #expect(HiddenText.revealed("tag\u{E0041}") == "tag⟨U+E0041⟩")
        #expect(HiddenText.revealed("plain 👍🏽") == "plain 👍🏽")
        // A selector after its own character is ordinary text; a run of them can carry a message.
        #expect(HiddenText.revealed("warn \u{26A0}\u{FE0F}") == "warn \u{26A0}\u{FE0F}")
        #expect(HiddenText.revealed("x\u{E0100}\u{E0101}") == "x\u{E0100}⟨U+E0101⟩")
        #expect(HiddenText.revealed("esc\u{1B}[8m") == "esc⟨U+001B⟩[8m")
        #expect(HiddenText.revealed("a\r\nb") == "a\r\nb")
        #expect(HiddenText.revealed("a\rb") == "a⟨U+000D⟩b")
        #expect(HiddenText.revealed("soft\u{00AD}") == "soft⟨U+00AD⟩")
        // Every character Unicode calls a format character or default-ignorable is hidden, so a new
        // Unicode version can't open a gap unnoticed. Variation selectors are judged by what precedes them.
        var missed: [UInt32] = []
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value), scalar.properties.isDefaultIgnorableCodePoint || scalar.properties.generalCategory == .format,
                  !HiddenText.isSelector(scalar) else { continue }
            if !HiddenText.contains("a" + String(scalar)) { missed.append(value) }
        }
        #expect(missed.isEmpty, "\(missed.map { String($0, radix: 16) })")
        let long = "A" + String(repeating: "\u{E0041}", count: 500)
        #expect(SessionStartHook.oneLine(long, 40) == "A")
    }

    @Test func aSkillFolderThatLinksElsewhereIsRefusedBeforeAnyDiff() async throws {
        let home = URL.temporaryDirectory.appending(path: "skill-health-link-\(UUID().uuidString)")
        let elsewhere = home.appending(path: "elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try "npm install -g supabase\n".write(to: elsewhere.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let skills = home.appending(path: "claude/skills")
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: skills.appending(path: "supabase"), withDestinationURL: elsewhere)
        let engine = Engine(paths: SkillHealthPaths(claudeHome: home.appending(path: "claude")))
        var patched = finding
        patched = Finding(id: finding.id, skillName: "supabase", severity: .breaks, skillSays: finding.skillSays, trueNow: "t",
                          source: finding.source, foundOn: .now, wrongSince: .undated, suggestedText: "npx supabase")
        await #expect(throws: SkillHealthError.self) {
            try await engine.proposePatch(for: patched, in: Skill(name: "supabase", folder: skills.appending(path: "supabase")))
        }
    }
}

// MARK: The write path: diffs, plans, names

@Suite("What a diff shows")
struct DiffShowsTests {
    let file = URL(filePath: "/tmp/SKILL.md")

    /// Swift compares strings by canonical equivalence, so the Kelvin sign equals K and the Greek
    /// question mark equals a semicolon: a change from one to the other was no change at all in the
    /// diff, and was still written. Lines are compared by their scalars.
    @Test(arguments: [("K", "\u{212A}"), (";", "\u{037E}"), ("e\u{301}", "\u{E9}")])
    func aChangeBetweenCanonicallyEquivalentTextsShows(old: String, new: String) throws {
        let proposal = ProposedWrite(file: file, before: "x \(old) y\nsame", after: "x \(new) y\nsame")
        #expect(proposal.diff == "-1: x \(old) y\n+1: x \(new) y")
        #expect(proposal.condensedDiff == proposal.diff)
        _ = try proposal.approve(shownDiff: proposal.diff)
    }

    @Test func aDiffThatSpellsTheLineTheOtherWayIsNotTheDiffThatWasShown() {
        let proposal = ProposedWrite(file: file, before: "K", after: "\u{212A}")
        // Equal as Swift strings, different scalars: not what the person was shown.
        #expect(throws: SkillHealthError.diffNotShown) { try proposal.approve(shownDiff: "-1: K\n+1: K") }
    }

    @Test func aLongLineIsShownCutAroundTheChange() {
        let head = String(repeating: "a", count: 3_000), tail = String(repeating: "b", count: 3_000)
        let proposal = ProposedWrite(file: file, before: "start\n\(head)X\(tail)\nend", after: "start\n\(head)Y\(tail)\nend")
        let note = "⟨… 2,940 unchanged characters …⟩"
        let around = (String(repeating: "a", count: 60), String(repeating: "b", count: 60))
        #expect(proposal.condensedDiff == "-2: \(note)\(around.0)X\(around.1)\(note)\n+2: \(note)\(around.0)Y\(around.1)\(note)")
        // Only what is the same in both lines is left out; the full diff is whole.
        #expect(proposal.diff == "-2: \(head)X\(tail)\n+2: \(head)Y\(tail)")
        // The same text again, so apply can rebuild what the prompt showed.
        #expect(proposal.condensedDiff == ProposedWrite(file: file, before: proposal.before, after: proposal.after).condensedDiff)
    }

    @Test func aChangeAtTheStartOrEndOfALongLineCutsOnlyTheOtherSide() {
        let rest = String(repeating: "z", count: 500)
        let start = ProposedWrite(file: file, before: "old\(rest)", after: "new\(rest)")
        #expect(start.condensedDiff == "-1: old\(String(repeating: "z", count: 60))⟨… 440 unchanged characters …⟩\n+1: new\(String(repeating: "z", count: 60))⟨… 440 unchanged characters …⟩")
        let end = ProposedWrite(file: file, before: "\(rest)old", after: "\(rest)new")
        #expect(end.condensedDiff == "-1: ⟨… 440 unchanged characters …⟩\(String(repeating: "z", count: 60))old\n+1: ⟨… 440 unchanged characters …⟩\(String(repeating: "z", count: 60))new")
    }

    /// Counted on scalars, the unit a file is compared in: 2,000 letters with an accent each are
    /// 4,000 scalars.
    @Test func theCutIsCountedInScalars() {
        let accented = String(repeating: "e\u{301}", count: 2_000)
        let proposal = ProposedWrite(file: file, before: "\(accented)X", after: "\(accented)Y")
        let kept = String(repeating: "e\u{301}", count: 30)
        #expect(proposal.condensedDiff == "-1: ⟨… 3,940 unchanged characters …⟩\(kept)X\n+1: ⟨… 3,940 unchanged characters …⟩\(kept)Y")
    }

    @Test func shortLinesAndPureAdditionsAreNeverCut() {
        let short = ProposedWrite(file: file, before: "a\nb\nc", after: "a\nB\nc")
        #expect(short.condensedDiff == short.diff)
        let long = String(repeating: "q", count: 1_000)
        let added = ProposedWrite(file: file, before: "a", after: "a\n\(long)")
        #expect(added.condensedDiff == "+2: \(long)")
        // A line a few characters past the margin isn't cut for a note that would save nothing.
        let barely = String(repeating: "m", count: 120)
        let near = ProposedWrite(file: file, before: "\(barely)1", after: "\(barely)2")
        #expect(near.condensedDiff == near.diff)
    }

    /// A file saved with a byte-order mark has it on its first line before and after: a fix to
    /// that line adds nothing hidden.
    @Test func aByteOrderMarkOnTheChangedLineIsNotAnAddedHiddenCharacter() {
        let kept = ProposedWrite(file: file, before: "\u{FEFF}# Supa\nx", after: "\u{FEFF}# Supabase\nx")
        #expect(!kept.diff.isEmpty)
        #expect(!kept.addsHiddenCharacters)
        // One that the removed lines didn't have is an addition: an accent mark is ordinary after a
        // letter and hidden after a space, so putting a space there hides it.
        let added = ProposedWrite(file: file, before: "ab\u{FE0F}", after: "a \u{FE0F}")
        #expect(added.addsHiddenCharacters)
        // A second one of the same kind counts too.
        #expect(ProposedWrite(file: file, before: "a\u{200B}b", after: "a\u{200B}b\u{200B}").addsHiddenCharacters)
        #expect(!ProposedWrite(file: file, before: "a\u{200B}b", after: "a\u{200B}c").addsHiddenCharacters)
        #expect(!ProposedWrite(file: file, before: "plain", after: "also plain").addsHiddenCharacters)
    }
}

@Suite("What a plan says it shows")
struct PlanSummaryTests {
    /// The gate hook (jq) cuts the summary at 3,000 unicode scalars. A summary the tool let through
    /// at 3,000 characters could be cut there without the person knowing.
    @Test func aSummaryIsCountedAndCutInScalars() {
        let accented = String(repeating: "e\u{301}", count: 2_000)   // 2,000 characters, 4,000 scalars
        let plan = PendingPlan(kind: .fix, summary: accented)
        #expect(plan.summary.unicodeScalars.count == PendingPlan.summaryLimit)
        #expect(plan.summary.hasSuffix("(cut short here; the full change was shown above)"))
        let exact = String(repeating: "x", count: PendingPlan.summaryLimit)
        #expect(PendingPlan.fitted(exact) == exact)
        #expect(PendingPlan.fitted(exact + "x").unicodeScalars.count == PendingPlan.summaryLimit)
    }
}

@Suite("Plans on disk")
struct PlanFileTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-plans-\(UUID().uuidString)")
    var store: PlanStore { PlanStore(paths: SkillHealthPaths(claudeHome: home)) }

    func newPlan() -> PendingPlan {
        PendingPlan(kind: .fix, summary: "Fix a, SKILL.md\n\n-1: x\n+1: y",
                    fix: .init(finding: UUID(), skill: "a", file: "/x/SKILL.md", before: "b", after: "c"))
    }

    /// jq (the gate) takes the last of a key given twice, Swift's decoder the first: the prompt
    /// would show one change and apply would write another.
    @Test func aPlanFileWithAKeyTwiceIsRefused() throws {
        let plan = newPlan()
        try store.save(plan)
        let url = store.url(for: plan.id)
        let text = try String(contentsOf: url, encoding: .utf8)
        let doubled = text.replacing("\"summary\" : \"Fix a, SKILL.md", with: "\"summary\" : \"Fix b, SKILL.md\",\n  \"summary\" : \"Fix a, SKILL.md")
        #expect(doubled != text)
        try doubled.write(to: url, atomically: true, encoding: .utf8)
        // The two readers do disagree about this file.
        #expect(try PlanStore.decoder.decode(PendingPlan.self, from: Data(doubled.utf8)).summary == "Fix b, SKILL.md")
        #expect(throws: SkillHealthError.planAltered) { try store.ready(plan.id, kind: .fix) }
        // Written back as the tool writes it, it is ready.
        try text.write(to: url, atomically: true, encoding: .utf8)
        #expect(try store.ready(plan.id, kind: .fix).id == plan.id)
    }

    @Test func aPlanFiledUnderAnotherIdIsRefused() throws {
        let plan = newPlan(), other = newPlan()
        try store.save(plan)
        try store.save(other)
        // The bytes of one plan, in the other's file: it would be marked used under the wrong id.
        try Data(contentsOf: store.url(for: plan.id)).write(to: store.url(for: other.id))
        #expect(throws: SkillHealthError.planAltered) { try store.ready(other.id, kind: .fix) }
        #expect(try store.ready(plan.id, kind: .fix).id == plan.id)
    }

    @Test func aPlanThatCantBeMarkedUsedIsDeletedSoItCantRunAgain() throws {
        let plan = newPlan()
        try store.save(plan)
        let failing = PlanStore(folder: store.folder) { _, _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(failing.retire(plan))
        #expect(!FileManager.default.fileExists(atPath: store.url(for: plan.id).path(percentEncoded: false)))
        #expect(throws: SkillHealthError.planNotFound) { try store.ready(plan.id, kind: .fix) }
    }

    @Test func aPlanThatCantBeMarkedUsedOrDeletedSaysSo() throws {
        let plan = newPlan()
        try store.save(plan)
        let path = store.url(for: plan.id).path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }
        let failing = PlanStore(folder: store.folder) { _, _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(!failing.retire(plan))
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func anOrdinaryPlanIsMarkedUsed() throws {
        let plan = newPlan()
        try store.save(plan)
        #expect(store.retire(plan))
        #expect(throws: SkillHealthError.planUsed) { try store.ready(plan.id, kind: .fix) }
    }
}

@Suite("Names the person can't read")
struct HiddenNameTests {
    let folder = URL(filePath: "/tmp/skills/a")

    @Test func aPathWithAHiddenCharacterInAnyPartIsRefused() {
        #expect(throws: SkillHealthError.hiddenInPath("refs/n\u{200B}ew.md")) { try Engine.inside(folder, "refs/n\u{200B}ew.md") }
        #expect(throws: SkillHealthError.hiddenInPath("re\u{202E}fs/new.md")) { try Engine.inside(folder, "re\u{202E}fs/new.md") }
        #expect((try? Engine.inside(folder, "refs/new.md")) == folder.appending(path: "refs/new.md"))
        let said = SkillHealthError.hiddenInPath("refs/n\u{200B}ew.md").plainDescription
        #expect(said.contains("n⟨U+200B⟩ew.md"))
        #expect(!said.contains("\u{200B}"))
    }

    /// An update that adds or drops a byte-order mark shows it: the file was read without it before.
    @Test func anUpdatePreviewKeepsAByteOrderMark() throws {
        let mark = Data([0xEF, 0xBB, 0xBF])
        let added = FileChange(path: "SKILL.md", kind: .changed, before: Data("a".utf8), after: mark + Data("a".utf8))
        #expect(added.lines == "-1: a\n+1: \u{FEFF}a")
        let dropped = FileChange(path: "SKILL.md", kind: .changed, before: mark + Data("a".utf8), after: Data("a".utf8))
        #expect(dropped.lines == "-1: \u{FEFF}a\n+1: a")
        let both = FileChange(path: "SKILL.md", kind: .changed, before: mark + Data("a".utf8), after: mark + Data("b".utf8))
        #expect(both.lines == "-1: \u{FEFF}a\n+1: \u{FEFF}b")
    }

    @Test func aChangesKindComesFromItsBlobs() {
        #expect(FileChange.Kind(before: nil as String?, after: "x") == .added)
        #expect(FileChange.Kind(before: "x", after: nil as String?) == .removed)
        #expect(FileChange.Kind(before: "x", after: "y") == .changed)
        #expect(FileChange.Kind(before: nil as String?, after: nil as String?) == nil)
    }
}
