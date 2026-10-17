import Foundation
import Testing
@testable import SkillHealthCore

@Suite("apply writes only reviewed changes, inside the skills folder, with a backup")
struct ApplyTests {
    let home: URL
    let engine: Engine

    init() throws {
        home = URL.temporaryDirectory.appending(path: "skill-health-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: "skills/supabase/references"),
                                                withIntermediateDirectories: true)
        engine = Engine(paths: SkillHealthPaths(claudeHome: home))
    }

    private func reviewed(_ file: URL, before: String, after: String) throws -> ReviewedWrite {
        let proposal = ProposedWrite(file: file, before: before, after: after)
        return try proposal.approve(shownDiff: proposal.diff)
    }

    @Test func writesTheChangeAndKeepsABackupUnderTheSkillsName() async throws {
        let file = home.appending(path: "skills/supabase/references/cli.md")
        try "npm install -g supabase".write(to: file, atomically: true, encoding: .utf8)
        let backup = try await engine.apply(reviewed(file, before: "npm install -g supabase", after: "npx supabase"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "npx supabase")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "npm install -g supabase")
        #expect(backup.path(percentEncoded: false).contains("/backups/supabase/"))
        #expect(backup.path(percentEncoded: false).hasSuffix("/references/cli.md"))
    }

    @Test func refusesAFileThatChangedAfterReview() async throws {
        let file = home.appending(path: "skills/supabase/SKILL.md")
        try "npm install -g supabase".write(to: file, atomically: true, encoding: .utf8)
        let write = try reviewed(file, before: "npm install -g supabase", after: "npx supabase")
        try "edited elsewhere".write(to: file, atomically: true, encoding: .utf8)
        await #expect(throws: SkillHealthError.fileChangedSinceReview(file)) { try await engine.apply(write) }
    }

    @Test func refusesAFileOutsideTheSkillsFolder() async throws {
        let file = home.appending(path: "outside.md")
        try "a".write(to: file, atomically: true, encoding: .utf8)
        await #expect(throws: SkillHealthError.notInsideSkills(file)) {
            try await engine.apply(reviewed(file, before: "a", after: "b"))
        }
    }

    @Test func refusesToReplaceALink() async throws {
        let target = home.appending(path: "real.md")
        try "a".write(to: target, atomically: true, encoding: .utf8)
        let link = home.appending(path: "skills/supabase/SKILL.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await #expect(throws: SkillHealthError.linkedFile(link)) {
            try await engine.apply(reviewed(link, before: "a", after: "b"))
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "a")
    }

    @Test func unchangedStatusIsNotRewritten() async throws {
        let snapshot = StatusSnapshot(sessionNote: "note", corrections: [])
        try await engine.writeStatus(snapshot)
        let first = try FileManager.default.attributesOfItem(atPath: engine.paths.status.path(percentEncoded: false))[.modificationDate] as? Date
        try await Task.sleep(for: .milliseconds(1100))
        try await engine.writeStatus(StatusSnapshot(sessionNote: "note", corrections: []))
        let second = try FileManager.default.attributesOfItem(atPath: engine.paths.status.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(first == second)
    }
}
