import Foundation
import Testing
@testable import SkillHealthCore

@Suite("A write needs the diff the person saw")
struct SafetyTests {
    let file = URL(filePath: "/tmp/SKILL.md")

    @Test func approvingWithTheShownDiffSucceeds() throws {
        let proposal = ProposedWrite(file: file, before: "npm install -g supabase", after: "npx supabase --help")
        #expect(proposal.diff == "-1: npm install -g supabase\n+1: npx supabase --help")
        let reviewed = try proposal.approve(shownDiff: proposal.diff)
        #expect(reviewed.proposal == proposal)
    }

    @Test func approvingWithADifferentDiffFails() {
        let proposal = ProposedWrite(file: file, before: "a", after: "b")
        #expect(throws: SkillHealthError.diffNotShown) { try proposal.approve(shownDiff: "-1: a") }
    }

    @Test(arguments: [
        ("a\nb\na", "a\nb", "-3: a"),                                   // delete a duplicate line
        ("foo\nbar", "bar\nbar", "-1: foo\n+1: bar"),                    // change into a duplicate
        ("x\ny\nz", "z\ny\nx", "-1: x\n-2: y\n+2: y\n+3: x"),          // reorder: never empty
        ("a\nb", "a\nb\na", "+3: a"),                                    // add a duplicate line
    ] as [(String, String, String?)])
    func duplicateAndReorderedLinesAreNeverHidden(before: String, after: String, expected: String?) {
        let diff = ProposedWrite(file: file, before: before, after: after).diff
        #expect(!diff.isEmpty)
        if let expected { #expect(diff == expected) }
    }

    @Test func anEmptyDiffCanNeverBeApproved() {
        let proposal = ProposedWrite(file: file, before: "same", after: "same")
        #expect(throws: SkillHealthError.diffNotShown) { try proposal.approve(shownDiff: "") }
    }

    @Test func anAuditsEstimateIsPerSkill() {
        #expect(AuditPlan(skillNames: ["shadcn-ui", "web-scraper"]).estimatedTokens == 360_000)
    }
}
