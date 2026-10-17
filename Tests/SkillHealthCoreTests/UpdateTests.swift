import Foundation
import Testing
@testable import SkillHealthCore

/// A source holding one commit's file contents, by path.
private actor Contents: SourceHost {
    var files: [String: Data] = [:]
    func put(_ text: String, at path: String) { files[path] = Data(text.utf8) }
    func defaultBranch(of repo: String) async throws(SkillHealthError) -> String { "main" }
    func headCommit(of repo: String, branch: String) async throws(SkillHealthError) -> String { "c2" }
    func commits(of repo: String, branch: String, atOrBefore moment: Date, limit: Int) async throws(SkillHealthError) -> [String] { ["c1"] }
    func files(of repo: String, at commit: String) async throws(SkillHealthError) -> SourceTree { SourceTree(blobs: [:]) }
    func contents(of repo: String, at commit: String, path: String) async throws(SkillHealthError) -> Data {
        guard commit == "c2", let data = files[path] else { throw .sourceNotFound(repo) }
        return data
    }
}

@Suite("Updating a copy that is behind (flow G)")
struct UpdateTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-update-\(UUID().uuidString)")
    var folder: URL { home.appending(path: "skills/a") }
    var engine: Engine { Engine(paths: SkillHealthPaths(claudeHome: home)) }
    var skill: Skill { Skill(name: "a", folder: folder, origin: Origin(repo: "o/r", subpath: "skills/a", installedAt: .now)) }
    func blob(_ text: String) -> String { GitBlob.id(of: Data(text.utf8)) }

    /// Installed: SKILL.md v1 and old.md. Source now: SKILL.md v2, old.md gone, refs/new.md added.
    fileprivate func setUp(source: Contents) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try "v1\nshared\n".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "old\n".write(to: folder.appending(path: "old.md"), atomically: true, encoding: .utf8)
        var compare = CompareFile()
        compare.copies["a"] = .init(repo: "o/r", subpath: "skills/a", installedFrom: "c1", head: "c2",
                                    installed: ["SKILL.md": blob("v1\nshared\n"), "old.md": blob("old\n")],
                                    source: ["SKILL.md": blob("v2\nshared\n"), "refs/new.md": blob("new\n")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try fm.createDirectory(at: home.appending(path: "skill-health"), withIntermediateDirectories: true)
        try encoder.encode(compare).write(to: home.appending(path: "skill-health/compare.json"))
        await source.put("v2\nshared\n", at: "skills/a/SKILL.md")
        await source.put("new\n", at: "skills/a/refs/new.md")
    }

    @Test func showsEveryChangeThenWritesItWithBackups() async throws {
        let source = Contents()
        try await setUp(source: source)
        let updates = try await engine.prepareUpdates(for: [skill], host: source)
        #expect(updates.count == 1)
        #expect(updates[0].changes.map(\.path) == ["SKILL.md", "old.md", "refs/new.md"])
        #expect(updates[0].changes.map(\.kind) == [.changed, .removed, .added])
        #expect(updates[0].changes[0].lines == "-1: v1\n+1: v2")

        let outcome = await engine.applyUpdates(updates, now: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(outcome.updated == ["a"])
        #expect(outcome.skipped.isEmpty)
        #expect(LocalCopy.files(in: folder) == ["SKILL.md": blob("v2\nshared\n"), "refs/new.md": blob("new\n")])
        // The installed copy is kept, file by file.
        let backups = try FileManager.default.contentsOfDirectory(atPath: home.appending(path: "skill-health/backups/a").path(percentEncoded: false))
        #expect(backups.count == 1)
        let saved = home.appending(path: "skill-health/backups/a/\(backups[0])")
        #expect(try String(contentsOf: saved.appending(path: "SKILL.md"), encoding: .utf8) == "v1\nshared\n")
        #expect(try String(contentsOf: saved.appending(path: "old.md"), encoding: .utf8) == "old\n")
        // Recorded, so the next check measures from the update: the copy now reads as current.
        let compare = await engine.loadCompare()
        #expect(await engine.loadUpdateRecords().commit(for: skill) == "c2")
        #expect(compare.copies["a"]?.state(local: LocalCopy.files(in: folder)) == .current)
    }

    @Test func aSkillChangedAfterReviewIsLeftUntouched() async throws {
        let source = Contents()
        try await setUp(source: source)
        let updates = try await engine.prepareUpdates(for: [skill], host: source)
        try "v1\nshared\nmy note\n".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let outcome = await engine.applyUpdates(updates)
        #expect(outcome.updated.isEmpty)
        #expect(outcome.skipped["a"] == "a changed after you reviewed it. Nothing in it was written; review it again.")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "old.md").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "refs/new.md").path(percentEncoded: false)))
    }

    @Test func aDownloadThatDoesntMatchItsListingIsRefused() async throws {
        let source = Contents()
        try await setUp(source: source)
        await source.put("tampered\n", at: "skills/a/SKILL.md")
        await #expect(throws: SkillHealthError.downloadMismatch("SKILL.md")) {
            try await engine.prepareUpdates(for: [skill], host: source)
        }
    }

    @Test func aCopyEditedOnThisMacIsNeverOffered() async throws {
        let source = Contents()
        try await setUp(source: source)
        try "v1\nshared\nmine\n".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        #expect(try await engine.prepareUpdates(for: [skill], host: source).isEmpty)
    }

    @Test func pathsFromAListingCantLeaveTheSkillFolder() {
        #expect(throws: SkillHealthError.unsafePath("../escape.md")) { try Engine.inside(folder, "../escape.md") }
        #expect(throws: SkillHealthError.unsafePath("a//b")) { try Engine.inside(folder, "a//b") }
        #expect((try? Engine.inside(folder, "refs/new.md")) == folder.appending(path: "refs/new.md"))
    }
}

@Suite("Updates keep a durable, accurate record, scripts, and case-only renames")
struct UpdateRecordTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-records-\(UUID().uuidString)")
    var folder: URL { home.appending(path: "skills/a") }
    var paths: SkillHealthPaths { SkillHealthPaths(claudeHome: home) }
    var engine: Engine { Engine(paths: paths) }
    let installedAt = Date(timeIntervalSince1970: 1_780_000_000)
    var skill: Skill { Skill(name: "a", folder: folder, origin: Origin(repo: "o/r", subpath: "skills/a", installedAt: installedAt)) }
    func blob(_ text: String) -> String { GitBlob.id(of: Data(text.utf8)) }

    func copy(installed: [String: String], source: [String: String], head: String = "c2", executables: Set<String>? = nil) throws {
        var compare = CompareFile()
        compare.copies["a"] = .init(repo: "o/r", subpath: "skills/a", installedFrom: "c1", head: head,
                                    installed: installed, source: source, sourceExecutables: executables)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try encoder.encode(compare).write(to: paths.compare)
    }

    func file(_ path: String, _ text: String, mode: Int = 0o644) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }

    func mode(_ path: String) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: folder.appending(path: path).path(percentEncoded: false))[.posixPermissions] as! Int
    }

    @Test func theRecordIsSavedApartAndSurvivesALaterCheck() async throws {
        try file("SKILL.md", "v1")
        try copy(installed: ["SKILL.md": blob("v1")], source: ["SKILL.md": blob("v2")])
        let update = CopyUpdate(skill: "a", folder: folder, origin: skill.origin!, repo: "o/r", commit: "c2",
                                changes: [FileChange(path: "SKILL.md", kind: .changed, before: Data("v1".utf8), after: Data("v2".utf8))],
                                historyURL: nil)
        let outcome = await engine.applyUpdates([update])
        #expect(outcome.updated == ["a"])
        #expect(await engine.loadUpdateRecords().commit(for: skill) == "c2")
        // compare.json reset or overwritten: the record, kept apart, still says where the copy came from.
        try FileManager.default.removeItem(at: paths.compare)
        #expect(await engine.loadUpdateRecords().commit(for: skill) == "c2")
    }

    @Test func theRecordedCopyIsWhatWasWrittenNotANewerCheck() async throws {
        try file("SKILL.md", "v1")
        // Prepared at c2; a check then moved the source on to c3 before the person pressed Update.
        try copy(installed: ["SKILL.md": blob("v1")], source: ["SKILL.md": blob("v3")], head: "c3")
        let update = CopyUpdate(skill: "a", folder: folder, origin: skill.origin!, repo: "o/r", commit: "c2",
                                changes: [FileChange(path: "SKILL.md", kind: .changed, before: Data("v1".utf8), after: Data("v2".utf8))],
                                historyURL: nil)
        _ = await engine.applyUpdates([update])
        let compare = await engine.loadCompare()
        #expect(compare.copies["a"]?.installedFrom == "c2")
        #expect(compare.copies["a"]?.installed == ["SKILL.md": blob("v2")])
        // Behind c3, as it truly is: not "changed on this Mac".
        #expect(compare.copies["a"]?.state(local: LocalCopy.files(in: folder)) == .behind)
    }

    @Test func scriptsStayRunnableAndNewOnesBecomeRunnable() async throws {
        try file("SKILL.md", "v1")
        try file("scripts/old.sh", "echo old", mode: 0o755)
        let update = CopyUpdate(skill: "a", folder: folder, origin: skill.origin!, repo: "o/r", commit: "c2", changes: [
            FileChange(path: "scripts/new.sh", kind: .added, before: nil, after: Data("echo new".utf8), executable: true),
            FileChange(path: "scripts/old.sh", kind: .changed, before: Data("echo old".utf8), after: Data("echo old2".utf8), executable: nil),
            FileChange(path: "SKILL.md", kind: .changed, before: Data("v1".utf8), after: Data("v2".utf8), executable: false),
        ], historyURL: nil)
        try copy(installed: [:], source: [:])
        let outcome = await engine.applyUpdates([update])
        #expect(outcome.updated == ["a"])
        #expect(try mode("scripts/new.sh") & 0o111 != 0)
        #expect(try mode("scripts/old.sh") == 0o755)   // mode unknown at the source: kept
        #expect(try mode("SKILL.md") & 0o111 == 0)
    }

    @Test func aRenameThatOnlyChangesCaseApplies() async throws {
        try file("Skill.md", "old")
        try copy(installed: [:], source: [:])
        let update = CopyUpdate(skill: "a", folder: folder, origin: skill.origin!, repo: "o/r", commit: "c2", changes: [
            FileChange(path: "SKILL.md", kind: .added, before: nil, after: Data("new".utf8)),
            FileChange(path: "Skill.md", kind: .removed, before: Data("old".utf8), after: nil),
        ], historyURL: nil)
        let outcome = await engine.applyUpdates([update])
        #expect(outcome.updated == ["a"])
        #expect(outcome.skipped.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names == ["SKILL.md"])
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "new")
    }

    @Test func checkingDropsRecordsForSkillsReinstalledOrRemoved() async throws {
        var records = UpdateRecords()
        records.records["a"] = .init(repo: "o/r", subpath: "skills/a", installedAt: installedAt, commit: "c2", updatedAt: .now)
        records.records["gone"] = .init(repo: "o/r", subpath: "skills/gone", installedAt: installedAt, commit: "c2", updatedAt: .now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try encoder.encode(records).write(to: paths.updateRecords)
        _ = try await engine.checkSources([skill], host: NoSource())
        #expect(await engine.loadUpdateRecords().records.keys.sorted() == ["a"])
    }
}

/// A source that is unreachable: the check records a problem and changes nothing else.
private struct NoSource: SourceHost {
    func defaultBranch(of repo: String) async throws(SkillHealthError) -> String { throw .offline("test") }
    func headCommit(of repo: String, branch: String) async throws(SkillHealthError) -> String { throw .offline("test") }
    func commits(of repo: String, branch: String, atOrBefore moment: Date, limit: Int) async throws(SkillHealthError) -> [String] { [] }
    func files(of repo: String, at commit: String) async throws(SkillHealthError) -> SourceTree { SourceTree(blobs: [:]) }
    func contents(of repo: String, at commit: String, path: String) async throws(SkillHealthError) -> Data { Data() }
}
