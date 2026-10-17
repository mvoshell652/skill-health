import Foundation
import Testing
@testable import SkillHealthCore

/// Joining the person's own checks with the known corrections that ship with Skill Health.
@Suite("Known corrections and the person's own checks")
struct FindingsJoinTests {
    let sep27 = Date(timeIntervalSince1970: 1_790_467_200)   // 2026-09-27
    var oct9: Date { sep27.addingTimeInterval(12 * 86_400) }
    let skills = [Skill(name: "supabase", folder: URL(filePath: "/x/supabase"), usesLast90Days: 201)]

    func known(_ quote: String, on date: Date) -> Finding {
        Finding(id: FindingID.make(skill: "supabase", file: "SKILL.md", quote: quote), skillName: "supabase",
                severity: .breaks, skillSays: quote, trueNow: "now", source: URL(string: "https://supabase.com/docs")!,
                foundOn: date, wrongSince: .undated, sharedFrom: "supabase-community/skills · supabase")
    }

    func join(audit: FindingsFile, shared: [Finding], treeNow: String) -> [String] {
        FindingsJoin.join(audit: audit, shared: shared, sharedChecked: [:], trees: ["supabase": treeNow],
                          decisions: DecisionsFile(), compare: CompareFile(), skills: skills).findings.map(\.skillSays)
    }

    @Test func aLaterCheckOfTheSameFilesReplacesOlderKnownCorrections() {
        // The person's Oct 9 check of these files kept nothing for this line: its second look threw it out.
        let audit = FindingsFile(findings: [], audited: ["supabase": oct9], trees: ["supabase": "tree-a"])
        #expect(join(audit: audit, shared: [known("npm install -g supabase", on: sep27)], treeNow: "tree-a").isEmpty)
    }

    @Test func aCheckOfOtherFilesDoesNot() {
        // The skill changed since the person's check, so that check says nothing about these files.
        let audit = FindingsFile(findings: [], audited: ["supabase": oct9], trees: ["supabase": "tree-a"])
        #expect(join(audit: audit, shared: [known("npm install -g supabase", on: sep27)], treeNow: "tree-b") == ["npm install -g supabase"])
    }

    @Test func anOlderCheckDoesNot() {
        let audit = FindingsFile(findings: [], audited: ["supabase": sep27], trees: ["supabase": "tree-a"])
        #expect(join(audit: audit, shared: [known("anon key", on: oct9)], treeNow: "tree-a") == ["anon key"])
    }

    @Test func aCheckSavedWithoutAFingerprintDoesNot() {
        let audit = FindingsFile(findings: [], audited: ["supabase": oct9])
        #expect(join(audit: audit, shared: [known("npm install -g supabase", on: sep27)], treeNow: "tree-a") == ["npm install -g supabase"])
    }

    @Test func theCheckOwnFindingStillWinsOnTheSameLine() {
        let own = known("anon key", on: oct9)
        let audit = FindingsFile(findings: [own], audited: ["supabase": oct9], trees: ["supabase": "tree-a"])
        #expect(join(audit: audit, shared: [known("anon key", on: sep27)], treeNow: "tree-a") == ["anon key"])
    }
}
