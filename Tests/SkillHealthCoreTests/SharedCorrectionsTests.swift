import Foundation
import Testing
@testable import SkillHealthCore

@Suite("Shared corrections match by exact file contents")
struct SharedCorrectionsTests {
    let skillMD = Data("# Supabase\n\nnpm install -g supabase\n".utf8)
    var correction: SharedCorrections.Correction {
        .init(blob: GitBlob.id(of: skillMD), file: "SKILL.md", skill: "supabase", repo: "TerminalSkills/skills",
              severity: .breaks, skillSays: "npm install -g supabase", trueNow: "Global installs are refused.",
              source: URL(string: "https://github.com/supabase/cli/issues/4496")!, wrongSince: "written:2026-02-18",
              suggestedText: "npx supabase", checkedOn: Date(timeIntervalSince1970: 1_790_000_000), keptBySecondCheck: true)
    }

    @Test func anIdenticalFileGetsTheFindingWhateverTheFolderIsCalled() {
        let shared = SharedCorrections(updatedAt: .now, corrections: [correction], checked: [])
        let mine = Skill(name: "my-supabase", folder: URL(filePath: "/x"))   // renamed, no install record
        let match = shared.matches(skill: mine, files: ["SKILL.md": GitBlob.id(of: skillMD), "notes.md": "anything"])
        #expect(match.findings.count == 1)
        let finding = match.findings[0]
        #expect(finding.skillName == "my-supabase")
        #expect(finding.id == FindingID.make(skill: "my-supabase", file: "SKILL.md", quote: "npm install -g supabase"))
        #expect(finding.sharedFrom == "TerminalSkills/skills · supabase")
        if case .written = finding.wrongSince {} else { Issue.record("expected written") }
    }

    @Test func anyDifferenceInTheFileMeansNoMatch() {
        let shared = SharedCorrections(updatedAt: .now, corrections: [correction], checked: [])
        let edited = shared.matches(skill: Skill(name: "s", folder: URL(filePath: "/x")),
                                    files: ["SKILL.md": GitBlob.id(of: Data("# Supabase\n\nnpm install -g supabase \n".utf8))])
        #expect(edited.findings.isEmpty)
    }

    @Test func aFolderCheckedWholeCountsAsCheckedOnlyWhenIdentical() {
        let files = ["SKILL.md": "a", "references/x.md": "b"]
        let on = Date(timeIntervalSince1970: 1_790_000_000)
        let shared = SharedCorrections(updatedAt: .now, corrections: [],
                                       checked: [.init(tree: SharedCorrections.tree(of: files), skill: "vite", checkedOn: on)])
        #expect(shared.matches(skill: Skill(name: "vite", folder: URL(filePath: "/x")), files: files).checkedOn == on)
        var changed = files
        changed["extra.md"] = "c"
        #expect(shared.matches(skill: Skill(name: "vite", folder: URL(filePath: "/x")), files: changed).checkedOn == nil)
    }

    @Test func wrongSinceLabelsParse() {
        if case .since = WrongSince(label: "since:2026-06-15") {} else { Issue.record("since") }
        if case .undated = WrongSince(label: "nonsense") {} else { Issue.record("undated") }
        if case .undated = WrongSince(label: nil) {} else { Issue.record("nil") }
    }
}
