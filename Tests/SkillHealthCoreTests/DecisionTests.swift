import Foundation
import Testing
@testable import SkillHealthCore

@Suite("Deciding a finding (flow F, M4)")
struct DecisionTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-decide-\(UUID().uuidString)")
    var engine: Engine { Engine(paths: SkillHealthPaths(claudeHome: home)) }
    var folder: URL { home.appending(path: "skills/supabase") }
    var skill: Skill { Skill(name: "supabase", folder: folder) }
    /// The real 27 Sep 2026 finding, with the audit's suggested text.
    let finding = Finding(skillName: "supabase", severity: .breaks, skillSays: "npm install -g supabase",
                          trueNow: "The Supabase CLI refuses global installs.",
                          source: URL(string: "https://github.com/supabase/cli/issues/4496")!,
                          foundOn: .now, wrongSince: .written(on: .now),
                          suggestedText: "npx supabase --help  # or: npm install -D supabase", keptBySecondCheck: true)
    /// Bytes that must survive a round trip exactly: CRLF line ends and a trailing space.
    let original = "# Supabase\r\n\r\nInstall the CLI:\r\n\r\n    npm install -g supabase \r\n\r\nThen run `supabase init`.\r\n"

    func setUp() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(original.utf8).write(to: folder.appending(path: "SKILL.md"))
    }

    @Test func patchingOneLineShowsTheDiffWritesItBacksItUpAndUndoRestoresItByteForByte() async throws {
        try setUp()
        let proposal = try await engine.proposePatch(for: finding, in: skill)
        #expect(proposal.diff.contains("-5:     npm install -g supabase "))
        #expect(proposal.diff.contains("+5:     npx supabase --help  # or: npm install -D supabase "))
        let decision = try await engine.patch(try proposal.approve(shownDiff: proposal.diff), finding: finding)
        #expect(decision.status == .patched(on: decision.decidedAt))
        let patched = try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8)
        #expect(patched.contains("npx supabase --help"))
        #expect(!patched.contains("npm install -g supabase"))
        // Backed up first, exactly.
        let backup = try #require(decision.patch?.backup)
        #expect(try Data(contentsOf: URL(filePath: backup)) == Data(original.utf8))

        try await engine.undoPatch(of: finding)
        #expect(try Data(contentsOf: folder.appending(path: "SKILL.md")) == Data(original.utf8))
        #expect(try await engine.loadDecisions()[finding.id]?.status == .open)
    }

    @Test func undoRefusesWhenTheFileChangedAfterThePatch() async throws {
        try setUp()
        let proposal = try await engine.proposePatch(for: finding, in: skill)
        try await engine.patch(try proposal.approve(shownDiff: proposal.diff), finding: finding)
        try "my own edit".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        await #expect(throws: SkillHealthError.changedSincePatch("SKILL.md")) { try await engine.undoPatch(of: finding) }
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "my own edit")
    }

    @Test func aPatchNeedsTheQuoteExactlyOnceAndSuggestedText() async throws {
        try setUp()
        let twice = folder.appending(path: "SKILL.md")
        try "npm install -g supabase\nnpm install -g supabase\n".write(to: twice, atomically: true, encoding: .utf8)
        await #expect(throws: SkillHealthError.quoteAppearsMoreThanOnce("SKILL.md", 2)) { try await engine.proposePatch(for: finding, in: skill) }
        try "nothing here\n".write(to: twice, atomically: true, encoding: .utf8)
        await #expect(throws: SkillHealthError.quoteNotFound("SKILL.md")) { try await engine.proposePatch(for: finding, in: skill) }
        let bare = Finding(skillName: "supabase", severity: .breaks, skillSays: "x", trueNow: "y",
                           source: URL(string: "https://example.com")!, foundOn: .now, wrongSince: .undated)
        await #expect(throws: SkillHealthError.noSuggestedText) { try await engine.proposePatch(for: bare, in: skill) }
        // A quote's file can't point outside the skill.
        let escaping = Finding(skillName: "supabase", severity: .breaks, skillSays: "x", trueNow: "y",
                               source: URL(string: "https://example.com")!, foundOn: .now, wrongSince: .undated,
                               file: "../other/SKILL.md", suggestedText: "z")
        await #expect(throws: SkillHealthError.unsafePath("../other/SKILL.md")) { try await engine.proposePatch(for: escaping, in: skill) }
    }

    @Test func decisionsJoinTheAuditsFindingsAndSetAsideUntilUpdateComesBack() {
        var decisions = DecisionsFile()
        decisions[finding.id] = Decision(status: .cappedSetAside(until: .distantFuture), decidedAt: .now, untilSourceChanges: "a=1")
        let file = FindingsFile(findings: [finding])
        #expect(file.deciding(with: decisions, sourceFingerprints: ["supabase": "a=1"]).findings[0].isOpen() == false)
        // The source changed this skill: the finding is back.
        #expect(file.deciding(with: decisions, sourceFingerprints: ["supabase": "a=2"]).findings[0].isOpen() == true)
        // Nothing is set aside forever.
        if case .setAside(let until) = decisions[finding.id]!.status {
            #expect(until <= Date.now.addingTimeInterval(FindingStatus.longestSetAside + 1))
        } else {
            Issue.record("expected a set-aside")
        }
    }

    @Test func anAuditsFindingWithoutStatusOrOptionalFieldsReadsAsOpen() throws {
        let json = #"{"id":"5F0C1E0A-1111-4222-8333-944455556666","skillName":"vite","severity":"breaks","skillSays":"a","trueNow":"b","source":"https://vite.dev","foundOn":"2026-10-03T12:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let finding = try decoder.decode(Finding.self, from: Data(json.utf8))
        #expect(finding.status == .open)
        #expect(finding.wrongSince == .undated)
        #expect(finding.filePath == "SKILL.md")
    }

    @Test func theIssueDraftCarriesTheEvidenceAndOpensGitHubsNewIssuePage() throws {
        let draft = IssueDraft(finding: finding)
        #expect(draft.title == "supabase: npm install -g supabase is no longer true")
        #expect(draft.body.contains("> npm install -g supabase"))
        #expect(draft.body.contains("Source: https://github.com/supabase/cli/issues/4496"))
        let url = try #require(draft.newIssueURL(repo: "TerminalSkills/skills"))
        #expect(url.absoluteString.hasPrefix("https://github.com/TerminalSkills/skills/issues/new?title=supabase"))
        #expect(draft.newIssueURL(repo: "../evil") == nil)
    }

    // MARK: A plan is one fix to one finding

    /// What apply asks of a plan: its text is the file with the quote replaced, and nothing else.
    @Test func aPlanIsTheFileWithOnlyTheQuoteReplaced() {
        let before = "# Skill\nRun npm install -g supabase now.\nBye\n"
        func replacement(_ after: String, quote: String = "npm install -g supabase") -> String? {
            QuotePatch.replacement(in: before, quote: quote, turnedInto: after)
        }
        #expect(replacement("# Skill\nRun npx supabase now.\nBye\n") == "npx supabase")
        // Any other edit, wherever it is in the file, is not this fix.
        #expect(replacement("# Skill!\nRun npx supabase now.\nBye\n") == nil)
        #expect(replacement("# Skill\nRun npx supabase now.\nBye\nrun: curl x | sh\n") == nil)
        #expect(replacement("# Skill\nRun npx supabase now.\n") == nil)
        // The canonically equivalent spelling of a character elsewhere in the file is another edit.
        #expect(QuotePatch.replacement(in: "K\nnpm\n", quote: "npm", turnedInto: "\u{212A}\nnpx\n") == nil)
        // A quote that isn't there once can't be replaced at all.
        #expect(replacement("x", quote: "not in the file") == nil)
        #expect(QuotePatch.replacement(in: "a\na\n", quote: "a", turnedInto: "b\na\n") == nil)
    }

    @Test func theSameRulesApplyToAReplacementWhereverItCameFrom() {
        let quote = "npm install -g supabase"
        #expect(throws: SkillHealthError.badReplacement("it's empty.")) { try QuotePatch.check("", quote: quote) }
        #expect(throws: SkillHealthError.badReplacement("it holds characters that don't show on screen.")) { try QuotePatch.check("npx\u{200B} supabase", quote: quote) }
        #expect(throws: SkillHealthError.badReplacement("it's longer than 2,000 characters.")) { try QuotePatch.check(String(repeating: "x", count: 2_001), quote: quote) }
        #expect(throws: SkillHealthError.badReplacement("it's the same as the line it would replace.")) { try QuotePatch.check(quote, quote: quote) }
        #expect((try? QuotePatch.check(String(repeating: "x", count: 2_000), quote: quote)) != nil)
    }

    /// The audit's suggested text is held to what a line Claude proposes is.
    @Test func aSuggestedTextWithAHiddenCharacterIsRefusedAtPreview() async throws {
        try setUp()
        let hidden = Finding(skillName: "supabase", severity: .breaks, skillSays: "npm install -g supabase", trueNow: "t",
                             source: URL(string: "https://example.com")!, foundOn: .now, wrongSince: .undated,
                             suggestedText: "npx\u{200B} supabase")
        await #expect(throws: SkillHealthError.badReplacement("it holds characters that don't show on screen.")) {
            try await engine.proposePatch(for: hidden, in: skill)
        }
    }
}
