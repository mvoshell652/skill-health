import Foundation
import Testing
@testable import SkillHealthCore

/// One commit's files, by path (the same shape as UpdateTests' source), and the listing GitHub
/// would give for them: every file's blob id, and which are executable. A test can make the listing
/// say something else, or make the source unreachable.
private actor OneCommit: SourceHost {
    var files: [String: Data] = [:]
    var executables: Set<String> = []
    var extraListed: [String: String] = [:]
    var unreachable = false
    var listCalls = 0
    func put(_ text: String, at path: String) { files[path] = Data(text.utf8) }
    func markExecutable(_ path: String) { executables.insert(path) }
    func alsoList(_ path: String, blob: String) { extraListed[path] = blob }
    func makeUnreachable() { unreachable = true }
    func defaultBranch(of repo: String) async throws(SkillHealthError) -> String { "main" }
    func headCommit(of repo: String, branch: String) async throws(SkillHealthError) -> String { "c2" }
    func commits(of repo: String, branch: String, atOrBefore moment: Date, limit: Int) async throws(SkillHealthError) -> [String] { ["c1"] }
    func files(of repo: String, at commit: String) async throws(SkillHealthError) -> SourceTree {
        listCalls += 1
        if unreachable { throw .offline("no network in this test") }
        return SourceTree(blobs: files.mapValues { GitBlob.id(of: $0) }.merging(extraListed) { _, extra in extra }, executables: executables)
    }
    func contents(of repo: String, at commit: String, path: String) async throws(SkillHealthError) -> Data {
        guard let data = files[path] else { throw .sourceNotFound(repo) }
        return data
    }
}

@Suite("Undoing an update")
struct UndoUpdateTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-undo-update-\(UUID().uuidString)")
    var folder: URL { home.appending(path: "skills/a") }
    var engine: Engine { Engine(paths: SkillHealthPaths(claudeHome: home)) }
    var skill: Skill { Skill(name: "a", folder: folder, origin: Origin(repo: "o/r", subpath: "skills/a", installedAt: .now)) }
    func blob(_ text: String) -> String { GitBlob.id(of: Data(text.utf8)) }

    /// Installed: SKILL.md v1 and run.sh (executable) and old.md. Source: SKILL.md v2, old.md gone,
    /// refs/new.md added, run.sh changed.
    fileprivate func setUp(source: OneCommit) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try "v1\r\nshared \n".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "old\n".write(to: folder.appending(path: "old.md"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho 1\n".write(to: folder.appending(path: "run.sh"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "run.sh").path(percentEncoded: false))
        var compare = CompareFile()
        compare.copies["a"] = .init(repo: "o/r", subpath: "skills/a", installedFrom: "c1", head: "c2",
                                    installed: ["SKILL.md": blob("v1\r\nshared \n"), "old.md": blob("old\n"), "run.sh": blob("#!/bin/sh\necho 1\n")],
                                    source: ["SKILL.md": blob("v2\nshared\n"), "refs/new.md": blob("new\n"), "run.sh": blob("#!/bin/sh\necho 2\n")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try fm.createDirectory(at: home.appending(path: "skill-health"), withIntermediateDirectories: true)
        try encoder.encode(compare).write(to: home.appending(path: "skill-health/compare.json"))
        await source.put("v2\nshared\n", at: "skills/a/SKILL.md")
        await source.put("new\n", at: "skills/a/refs/new.md")
        await source.put("#!/bin/sh\necho 2\n", at: "skills/a/run.sh")
    }

    func snapshot() throws -> [String: (Data, Int)] {
        var files: [String: (Data, Int)] = [:]
        for path in ["SKILL.md", "old.md", "run.sh", "refs/new.md"] {
            let url = folder.appending(path: path)
            guard let data = try? Data(contentsOf: url) else { continue }
            let mode = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] as! Int
            files[path] = (data, mode)
        }
        return files
    }

    @Test func anUpdateCanBeUndoneByteForByteWithModes() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let before = try snapshot()
        let outcome = await engine.applyUpdates(try await engine.prepareUpdates(for: [skill], host: source))
        #expect(outcome.updated == ["a"])
        let manifests = engine.updateManifests()
        #expect(manifests.count == 1)
        #expect(manifests.first?.manifest.files.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.added, .changed, .changed, .removed])
        try await engine.undoUpdate(at: manifests[0].folder)
        let after = try snapshot()
        #expect(Set(after.keys) == Set(before.keys))
        for (path, value) in before {
            #expect(after[path]?.0 == value.0, "\(path) bytes")
            #expect(after[path]?.1 == value.1, "\(path) mode")
        }
        // The record the update made is gone, and the update isn't offered for undo again.
        #expect(await engine.loadUpdateRecords().records["a"] == nil)
        #expect(engine.updateManifests().isEmpty)
    }

    @Test func undoRefusesWhenTheFilesChangedSinceTheUpdate() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        _ = await engine.applyUpdates(try await engine.prepareUpdates(for: [skill], host: source))
        try "edited\n".write(to: folder.appending(path: "refs/new.md"), atomically: true, encoding: .utf8)
        let manifest = try #require(engine.updateManifests().first)
        await #expect(throws: SkillHealthError.changedSinceUpdate("a")) { try await engine.undoUpdate(at: manifest.folder) }
        // Nothing was touched.
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "v2\nshared\n")
        #expect(try String(contentsOf: folder.appending(path: "refs/new.md"), encoding: .utf8) == "edited\n")
    }

    /// The legitimate flow can't write such a manifest; anything else that writes into backups/
    /// still can't point an undo at a file outside the skills folder.
    @Test func anUndoRefusesAManifestNamingAFolderOutsideTheSkillsFolder() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let outside = home.appending(path: "outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "mine\n".write(to: outside.appending(path: "victim.txt"), atomically: true, encoding: .utf8)
        let run = home.appending(path: "skill-health/backups/x/2026-10-04T00-00-00-update")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        try "planted\n".write(to: run.appending(path: "victim.txt"), atomically: true, encoding: .utf8)
        let manifest = UpdateManifest(skill: "x", folder: outside.path(percentEncoded: false), repo: "o/r", toCommit: "c2",
                                      updatedAt: .now, previousRecord: nil, previousInstalledFrom: nil,
                                      files: [.init(path: "victim.txt", kind: .changed, before: blob("planted\n"), after: blob("mine\n"),
                                                    beforeMode: nil, afterMode: nil)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: run.appending(path: UpdateManifest.fileName))
        await #expect(throws: SkillHealthError.notInsideSkills(outside)) { try await engine.undoUpdate(at: run) }
        #expect(try String(contentsOf: outside.appending(path: "victim.txt"), encoding: .utf8) == "mine\n")
        // Nor can a backup folder outside backups/ be named.
        await #expect(throws: SkillHealthError.self) { try await engine.undoUpdate(at: outside) }
    }

    @Test func anUpdateRefusesASkillFolderThatLinksOutsideTheSkillsFolder() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let elsewhere = home.appending(path: "elsewhere/a")
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder, to: elsewhere)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: elsewhere)
        let outcome = await engine.applyUpdates(try await engine.prepareUpdates(for: [skill], host: source))
        #expect(outcome.updated.isEmpty)
        #expect(outcome.skipped["a"] != nil)
        #expect(try String(contentsOf: elsewhere.appending(path: "SKILL.md"), encoding: .utf8) == "v1\r\nshared \n")
    }

    // MARK: A manifest is data on disk: it has to agree with itself and with the install

    /// The update just made, then its manifest changed by `edit`, as anything that can write into
    /// backups/ could. Returns the backup folder.
    fileprivate func updatedThenEdited(_ edit: (inout [String: Any]) -> Void) async throws -> URL {
        let source = OneCommit()
        try await setUp(source: source)
        let outcome = await engine.applyUpdates(try await engine.prepareUpdates(for: [skill], host: source))
        #expect(outcome.updated == ["a"])
        let manifest = try #require(engine.updateManifests().first)
        let url = manifest.folder.appending(path: UpdateManifest.fileName)
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        edit(&object)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        return manifest.folder
    }

    func expectUntouched() throws {
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "v2\nshared\n")
        #expect(try String(contentsOf: folder.appending(path: "refs/new.md"), encoding: .utf8) == "new\n")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "old.md").path(percentEncoded: false)))
    }

    @Test func anUndoRefusesAManifestWhoseSkillIsNotTheFolderItNames() async throws {
        let backup = try await updatedThenEdited { $0["skill"] = "b" }
        await #expect(throws: SkillHealthError.self) { try await engine.undoUpdate(at: backup) }
        try expectUntouched()
    }

    /// The folder of something inside a skill is not a skill's own.
    @Test func anUndoRefusesAManifestNamingAFolderInsideASkill() async throws {
        let nested = try await updatedThenEdited { object in
            object["skill"] = "refs"
            object["folder"] = folder.appending(path: "refs").path(percentEncoded: false)
        }
        await #expect(throws: SkillHealthError.self) { try await engine.undoUpdate(at: nested) }
        try expectUntouched()
    }

    @Test func anUndoRefusesAnEntryWhoseKindItsBlobsDontSay() async throws {
        let backup = try await updatedThenEdited { object in
            var files = object["files"] as! [[String: Any]]
            for index in files.indices where files[index]["path"] as? String == "old.md" { files[index]["kind"] = "added" }
            object["files"] = files
        }
        await #expect(throws: SkillHealthError.self) { try await engine.undoUpdate(at: backup) }
        try expectUntouched()
    }

    @Test func anUndoRefusesWhereAFolderNowStandsInPlaceOfARemovedFile() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        _ = await engine.applyUpdates(try await engine.prepareUpdates(for: [skill], host: source))
        // old.md was removed by the update; the person has made a folder of that name since.
        try FileManager.default.createDirectory(at: folder.appending(path: "old.md"), withIntermediateDirectories: true)
        let manifest = try #require(engine.updateManifests().first)
        await #expect(throws: SkillHealthError.changedSinceUpdate("a")) { try await engine.undoUpdate(at: manifest.folder) }
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "v2\nshared\n")
        #expect(try String(contentsOf: folder.appending(path: "refs/new.md"), encoding: .utf8) == "new\n")
    }

    /// The files went back, the record can't be saved: the skill is not left restored under records
    /// that say it is updated.
    @Test func anUndoThatCantBeRecordedPutsTheUpdatesFilesBack() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        _ = await engine.applyUpdates(try await engine.prepareUpdates(for: [skill], host: source))
        let records = home.appending(path: "skill-health/updates.json").path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: records)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: records) }
        let manifest = try #require(engine.updateManifests().first)
        do {
            try await engine.undoUpdate(at: manifest.folder)
            Issue.record("the undo went through with its record unsaved")
        } catch let error as SkillHealthError {
            guard case .undoNotRecorded(let name, _) = error else { Issue.record("\(error)"); return }
            #expect(name == "a")
            #expect(error.plainDescription.contains("Nothing was changed"))
        }
        try expectUntouched()
        #expect(try Data(contentsOf: folder.appending(path: "run.sh")) == Data("#!/bin/sh\necho 2\n".utf8))
        // Still undoable: the manifest wasn't spent, and once the record can be saved it goes through.
        #expect(engine.updateManifests().count == 1)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: records)
        try await engine.undoUpdate(at: engine.updateManifests()[0].folder)
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "v1\r\nshared \n")
    }
}

@Suite("The write lock")
struct FileLockTests {
    let folder = URL.temporaryDirectory.appending(path: "skill-health-lock-\(UUID().uuidString)")

    @Test func aHeldLockMakesTheNextWriterWaitThenFailNamingTheHolder() throws {
        let first = FileLock(directory: folder.appending(path: ".lock"), wait: .milliseconds(200))
        try first.acquire()
        let second = FileLock(directory: folder.appending(path: ".lock"), wait: .milliseconds(200))
        #expect(throws: SkillHealthError.self) { try second.acquire() }
        first.release()
        try second.acquire()
        second.release()
    }

    @Test func aLockLeftBehindByADeadProcessIsTakenOverAfterTenMinutes() throws {
        let lock = FileLock(directory: folder.appending(path: ".lock"), wait: .milliseconds(100))
        try lock.acquire()
        // Someone else, much later.
        let later = FileLock(directory: folder.appending(path: ".lock"), wait: .milliseconds(100))
        try later.acquire(now: { Date.now.addingTimeInterval(11 * 60) })
        later.release()
    }

    @Test func theBusyMessageNamesWhoHoldsTheLock() throws {
        for (process, said) in [("skill-health", "The Skill Health command in Claude Code"), ("SkillHealth", "The Skill Health app"),
                                ("something-else", "Something-else")] {
            let directory = folder.appending(path: ".lock-\(process)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try #"{"pid":1,"process":"\#(process)","since":"\#(Date.now.formatted(.iso8601))"}"#
                .write(to: directory.appending(path: "owner"), atomically: true, encoding: .utf8)
            do {
                try FileLock(directory: directory, wait: .milliseconds(100)).acquire()
                Issue.record("the lock held by \(process) was taken")
            } catch {
                #expect(error.plainDescription == "\(said) is saving Skill Health's files. Try again in a moment.", "\(process)")
            }
        }
    }

    /// Only an existing lock means someone else is saving. A folder Skill Health can't write to isn't busy,
    /// and "try again in a moment" would never stop being said.
    @Test func aFolderSkillHealthCantWriteToIsSaidAsItIsNotCalledBusy() throws {
        try #require(getuid() != 0, "a folder can't be made unwritable for the superuser")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false)) }
        let lock = FileLock(directory: folder.appending(path: ".lock"), wait: .milliseconds(100))
        do {
            try lock.acquire()
            Issue.record("a lock was taken in a folder that can't be written")
        } catch {
            guard case .cantLock(let where_, let why) = error else { Issue.record("\(error)"); return }
            #expect(where_ == folder.path)
            #expect(why == "permission denied")
            let said = error.plainDescription
            #expect(said == "Skill Health can't write to \(folder.path): permission denied. Check that folder's permissions, then try again.")
            #expect(!said.contains("Try again in a moment"))
        }
    }

    @Test func theEngineHoldsTheLockAcrossAPatchAndItsRecordWithoutDeadlocking() async throws {
        let home = folder.appending(path: "claude")
        let skills = home.appending(path: "skills/s")
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try "use npm install -g s\n".write(to: skills.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let engine = Engine(paths: SkillHealthPaths(claudeHome: home))
        let finding = Finding(skillName: "s", severity: .breaks, skillSays: "npm install -g s", trueNow: "t",
                              source: URL(string: "https://example.com")!, foundOn: .now, wrongSince: .undated, suggestedText: "npx s")
        let proposal = try await engine.proposePatch(for: finding, in: Skill(name: "s", folder: skills))
        let decision = try await engine.patch(try proposal.approve(shownDiff: proposal.diff), finding: finding)
        #expect(decision.patch != nil)
        // Released afterwards.
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "skill-health/.lock").path(percentEncoded: false)))
    }

    @Test func aPatchIsRefusedBeforeTheSkillIsTouchedWhenDecisionsCantBeRead() async throws {
        let home = folder.appending(path: "claude2")
        let skills = home.appending(path: "skills/s")
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "skill-health"), withIntermediateDirectories: true)
        try "use npm install -g s\n".write(to: skills.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "{half".write(to: home.appending(path: "skill-health/decisions.json"), atomically: true, encoding: .utf8)
        let engine = Engine(paths: SkillHealthPaths(claudeHome: home))
        let finding = Finding(skillName: "s", severity: .breaks, skillSays: "npm install -g s", trueNow: "t",
                              source: URL(string: "https://example.com")!, foundOn: .now, wrongSince: .undated, suggestedText: "npx s")
        let proposal = try await engine.proposePatch(for: finding, in: Skill(name: "s", folder: skills))
        await #expect(throws: SkillHealthError.self) { try await engine.patch(try proposal.approve(shownDiff: proposal.diff), finding: finding) }
        #expect(try String(contentsOf: skills.appending(path: "SKILL.md"), encoding: .utf8) == "use npm install -g s\n")
    }
}

// MARK: An update from a plan is checked against the source itself

@Suite("Applying an update from a plan")
struct PlannedUpdateTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-planned-\(UUID().uuidString)")
    var folder: URL { home.appending(path: "skills/a") }
    var staging: URL { home.appending(path: "skill-health/pending/staging") }
    var paths: SkillHealthPaths { SkillHealthPaths(claudeHome: home) }
    var engine: Engine { Engine(paths: paths) }
    let origin = Origin(repo: "o/r", subpath: "skills/a", installedAt: Date(timeIntervalSince1970: 1_780_000_000))
    func blob(_ text: String) -> String { GitBlob.id(of: Data(text.utf8)) }

    /// Installed: SKILL.md v1, old.md and run.sh (executable). Source: SKILL.md v2, old.md gone,
    /// refs/new.md added, run.sh changed.
    fileprivate func setUp(source: OneCommit, executables: Set<String>? = nil) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try "v1\nshared\n".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "old\n".write(to: folder.appending(path: "old.md"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho 1\n".write(to: folder.appending(path: "run.sh"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "run.sh").path(percentEncoded: false))
        try writeCompare(source: ["SKILL.md": blob("v2\nshared\n"), "refs/new.md": blob("new\n"), "run.sh": blob("#!/bin/sh\necho 2\n")],
                         executables: executables)
        await source.put("v2\nshared\n", at: "skills/a/SKILL.md")
        await source.put("new\n", at: "skills/a/refs/new.md")
        await source.put("#!/bin/sh\necho 2\n", at: "skills/a/run.sh")
    }

    func writeCompare(source: [String: String], executables: Set<String>? = nil) throws {
        var compare = CompareFile()
        compare.copies["a"] = .init(repo: "o/r", subpath: "skills/a", installedFrom: "c1", head: "c2",
                                    installed: ["SKILL.md": blob("v1\nshared\n"), "old.md": blob("old\n"), "run.sh": blob("#!/bin/sh\necho 1\n")],
                                    source: source, sourceExecutables: executables)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try encoder.encode(compare).write(to: paths.compare)
    }

    /// What `skill-health update preview` makes of a prepared update: its entry in the plan, with each new
    /// file staged under pending/<plan>/<skill>/<path>.
    func planned(_ update: CopyUpdate) throws -> PendingPlan.Update.Skill {
        var changes: [PendingPlan.Update.Change] = []
        for change in update.changes {
            var stagedPath: String?
            if let after = change.after {
                let relative = "\(update.skill)/\(change.path)"
                let target = relative.split(separator: "/").reduce(staging) { $0.appending(path: String($1)) }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try after.write(to: target)
                stagedPath = relative
            }
            changes.append(.init(path: change.path, kind: change.kind, before: change.before.map(GitBlob.id(of:)),
                                 after: change.after.map(GitBlob.id(of:)), staged: stagedPath, executable: change.executable))
        }
        return .init(skill: update.skill, folder: update.folder.path(percentEncoded: false), origin: update.origin,
                     repo: update.repo, commit: update.commit, historyURL: update.historyURL, changes: changes)
    }

    func installed(_ compare: CompareFile) -> [Skill] {
        [Skill(name: "a", folder: folder, origin: origin, usesLast90Days: 3,
               copy: compare.copies["a"]?.state(local: LocalCopy.files(in: folder)))]
    }

    fileprivate func prepared(_ source: OneCommit) async throws -> PendingPlan.Update.Skill {
        let skill = Skill(name: "a", folder: folder, origin: origin, usesLast90Days: 3)
        return try planned(try await engine.prepareUpdates(for: [skill], host: source).first!)
    }

    fileprivate func apply(_ item: PendingPlan.Update.Skill, host: OneCommit) async -> PlannedUpdates {
        let compare = await engine.loadCompare()
        return await engine.applyPlanned([item], staging: staging, skills: installed(compare), compare: compare, host: host)
    }

    func expectUntouched() throws {
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "v1\nshared\n")
        #expect(try String(contentsOf: folder.appending(path: "old.md"), encoding: .utf8) == "old\n")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "refs/new.md").path(percentEncoded: false)))
    }

    /// The same change with one file's entry swapped for another.
    func changing(_ item: PendingPlan.Update.Skill, _ path: String, _ change: (PendingPlan.Update.Change) -> PendingPlan.Update.Change)
        -> PendingPlan.Update.Skill {
        .init(skill: item.skill, folder: item.folder, origin: item.origin, repo: item.repo, commit: item.commit,
              historyURL: item.historyURL, changes: item.changes.map { $0.path == path ? change($0) : $0 })
    }

    @Test func aPlanTheSourceConfirmsIsWritten() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let result = await apply(try await prepared(source), host: source)
        #expect(result.refused.isEmpty)
        #expect(result.outcome.updated == ["a"])
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "v2\nshared\n")
        #expect(try String(contentsOf: folder.appending(path: "refs/new.md"), encoding: .utf8) == "new\n")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "old.md").path(percentEncoded: false)))
        #expect(await source.listCalls == 1)
    }

    /// A plan, the comparison file and a staged file, all written to say the same thing: the prompt
    /// shows file names only, so nothing but the source's own listing can contradict them.
    @Test func aForgedPlanAndComparisonAreRefusedBecauseTheSourceListsOtherFiles() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let honest = try await prepared(source)
        // The source holds v2; the forgery says SKILL.md should become something else.
        try writeCompare(source: ["SKILL.md": blob("evil\n"), "refs/new.md": blob("new\n"), "run.sh": blob("#!/bin/sh\necho 2\n")])
        let forged = changing(honest, "SKILL.md") { change in
            let staged = staging.appending(path: "a/SKILL.md")
            try? Data("evil\n".utf8).write(to: staged)
            return .init(path: change.path, kind: change.kind, before: change.before, after: blob("evil\n"),
                         staged: change.staged, executable: change.executable)
        }
        let result = await apply(forged, host: source)
        #expect(result.outcome.updated.isEmpty)
        #expect(result.refused["a"] == "the files prepared for it aren't the ones o/r lists for that version")
        try expectUntouched()
    }

    @Test func aFileTheSourceStillHoldsIsNotRemoved() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let honest = try await prepared(source)
        #expect(honest.changes.contains { $0.path == "old.md" && $0.kind == .removed })
        // GitHub still lists old.md at that commit; the plan and the comparison say it is gone.
        await source.alsoList("skills/a/old.md", blob: blob("old\n"))
        let result = await apply(honest, host: source)
        #expect(result.outcome.updated.isEmpty)
        #expect(result.refused["a"]?.contains("aren't the ones o/r lists") == true)
        try expectUntouched()
    }

    @Test func aSourceThatCantBeReachedLeavesTheSkillAsItWas() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let honest = try await prepared(source)
        await source.makeUnreachable()
        let result = await apply(honest, host: source)
        #expect(result.outcome.updated.isEmpty)
        #expect(result.refused["a"]?.hasPrefix("Skill Health couldn't reach GitHub to confirm this update") == true)
        try expectUntouched()
    }

    @Test func aKindThatItsBlobsDontSayIsRefused() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let honest = try await prepared(source)
        // SKILL.md exists here, so it can't be "added"; refs/new.md has no file here, so it can't be "changed".
        let lie = changing(honest, "SKILL.md") { .init(path: $0.path, kind: .added, before: $0.before, after: $0.after, staged: $0.staged, executable: $0.executable) }
        let first = await apply(lie, host: source)
        #expect(first.refused["a"] == "its list of changes doesn't add up")
        let other = changing(honest, "refs/new.md") { .init(path: $0.path, kind: .changed, before: $0.before, after: $0.after, staged: $0.staged, executable: $0.executable) }
        let second = await apply(other, host: source)
        #expect(second.refused["a"] == "its list of changes doesn't add up")
        try expectUntouched()
    }

    @Test func anExecutableFlagTheComparisonDoesntHaveIsRefused() async throws {
        let source = OneCommit()
        try await setUp(source: source, executables: ["run.sh"])
        await source.markExecutable("skills/a/run.sh")
        let honest = try await prepared(source)
        #expect(honest.changes.first { $0.path == "run.sh" }?.executable == true)
        let lie = changing(honest, "refs/new.md") { .init(path: $0.path, kind: $0.kind, before: $0.before, after: $0.after, staged: $0.staged, executable: true) }
        let result = await apply(lie, host: source)
        #expect(result.refused["a"] == "its list of changes doesn't match how its source lists the files")
        try expectUntouched()
        // And one that runs is honoured: the same plan, untouched, is written.
        #expect(await apply(honest, host: source).outcome.updated == ["a"])
    }

    /// A comparison file forged along with the plan says run.sh isn't executable; the source says it is.
    @Test func anExecutableFlagTheSourceDoesntHaveIsRefused() async throws {
        let source = OneCommit()
        try await setUp(source: source, executables: [])
        await source.markExecutable("skills/a/run.sh")
        let honest = try await prepared(source)
        #expect(honest.changes.first { $0.path == "run.sh" }?.executable == false)
        let result = await apply(honest, host: source)
        #expect(result.refused["a"]?.contains("aren't the ones o/r lists") == true)
        try expectUntouched()
    }

    @Test func eachRepositoryAndCommitIsListedOnce() async throws {
        let source = OneCommit()
        try await setUp(source: source)
        let a = try await prepared(source)
        let b = PendingPlan.Update.Skill(skill: "b", folder: a.folder, origin: a.origin, repo: a.repo, commit: a.commit,
                                         historyURL: nil, changes: a.changes)
        let refused = await engine.confirmAtSource([a, b], host: source)
        // The files are the ones listed under skills/a, so both confirm; the listing was fetched once.
        #expect(refused.isEmpty)
        #expect(await source.listCalls == 1)
    }
}

@Suite("What an update run says")
struct UpdateReportTests {
    @Test func anUpdatedSkillIsOnlySaidToBeUndoableWhenItIs() {
        var outcome = UpdateOutcome()
        outcome.updated = ["a", "b"]
        outcome.damaged["a"] = "Updated, but Skill Health couldn't save what would undo it: disk full"
        let report = outcome.report(backups: "/home/backups")
        // Its attention line comes first, and /skill-health:undo is only said to put back the other one.
        #expect(report.lines == ["a needs attention: Updated, but Skill Health couldn't save what would undo it: disk full",
                                 "Updated 2 skills: a, b.",
                                 "The old copies are in /home/backups, and /skill-health:undo puts b back."])
        #expect(report.failure?.contains("a was updated, but Skill Health couldn't save everything it keeps for it") == true)
    }

    @Test func aSkillThatWasUpdatedButNotRecordedGetsNoUndoLineAtAll() {
        var outcome = UpdateOutcome()
        outcome.updated = ["a"]
        outcome.damaged["a"] = "Updated, but Skill Health couldn't save what would undo it: disk full"
        let report = outcome.report(backups: "/home/backups")
        #expect(!report.lines.contains { $0.contains("/skill-health:undo") })
        #expect(report.failure != nil)
    }

    @Test func aCleanUpdateSucceedsAndOneNothingHappenedToFails() {
        var outcome = UpdateOutcome()
        outcome.updated = ["a"]
        let clean = outcome.report(backups: "/b")
        #expect(clean.lines == ["Updated 1 skill: a.", "The old copies are in /b, and /skill-health:undo puts a skill back."])
        #expect(clean.failure == nil)
        let nothing = UpdateOutcome().report(refused: ["a": "it changed after the preview"], backups: "/b")
        #expect(nothing.lines == ["a was left as it was: it changed after the preview"])
        #expect(nothing.failure == "Nothing was updated.")
    }

    @Test func aPartlyUpdatedSkillFailsAndNamesTheBackups() {
        var outcome = UpdateOutcome()
        outcome.damaged["a"] = "Partly updated, and SKILL.md couldn't be put back. The originals are in /b/a."
        let report = outcome.report(backups: "/b")
        #expect(report.lines.first == "a needs attention: Partly updated, and SKILL.md couldn't be put back. The originals are in /b/a.")
        #expect(report.failure == "a is partly updated. The old files are in /b.")
    }
}

// MARK: Rolling back, and the lock

@Suite("Rolling back an update that failed part way")
struct UpdateRollbackTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-rollback-\(UUID().uuidString)")
    var folder: URL { home.appending(path: "skills/a") }
    var paths: SkillHealthPaths { SkillHealthPaths(claudeHome: home) }
    var engine: Engine { Engine(paths: paths) }
    let origin = Origin(repo: "o/r", subpath: "skills/a", installedAt: Date(timeIntervalSince1970: 1_780_000_000))
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func file(_ path: String, _ text: String) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func text(_ path: String) -> String? { try? String(contentsOf: folder.appending(path: path), encoding: .utf8) }

    func update(_ changes: [FileChange]) -> CopyUpdate {
        CopyUpdate(skill: "a", folder: folder, origin: origin, repo: "o/r", commit: "c2", changes: changes, historyURL: nil)
    }

    /// Where this run's copies of the replaced files go.
    var backup: URL {
        paths.backups.appending(path: "a")
            .appending(path: "\(now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)).replacing(":", with: "-"))-update")
    }

    /// The backup of old.md can't be made, so the update stops before it writes anything. SKILL.md
    /// can't be rewritten either (it is locked), so trying to "put it back" would fail for nothing
    /// and call a skill nothing happened to partly updated.
    @Test func aSkillNothingWasWrittenToIsLeftAloneAndNotCalledPartlyUpdated() async throws {
        try file("SKILL.md", "v1")
        try file("old.md", "old")
        try FileManager.default.createDirectory(at: backup.appending(path: "old.md"), withIntermediateDirectories: true)
        try "in the way".write(to: backup.appending(path: "old.md/x"), atomically: true, encoding: .utf8)
        let locked = folder.appending(path: "SKILL.md").path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked) }
        let outcome = await engine.applyUpdates([update([
            FileChange(path: "SKILL.md", kind: .changed, before: Data("v1".utf8), after: Data("v2".utf8)),
            FileChange(path: "old.md", kind: .removed, before: Data("old".utf8), after: nil),
        ])], now: now)
        #expect(outcome.updated.isEmpty)
        #expect(outcome.damaged.isEmpty)
        #expect(outcome.skipped["a"] != nil)
        #expect(text("SKILL.md") == "v1")
        #expect(text("old.md") == "old")
    }

    @Test func aWriteThatFailsPutsEveryFileBack() async throws {
        try file("SKILL.md", "v1")
        try file("old.md", "old")
        try FileManager.default.createDirectory(at: folder.appending(path: "refs"), withIntermediateDirectories: true)
        let refs = folder.appending(path: "refs").path(percentEncoded: false)
        // refs/new.md can't be created, after SKILL.md was written and old.md removed.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: refs)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: refs) }
        try #require(getuid() != 0, "a folder can't be made unwritable for the superuser")
        let outcome = await engine.applyUpdates([update([
            FileChange(path: "SKILL.md", kind: .changed, before: Data("v1".utf8), after: Data("v2".utf8)),
            FileChange(path: "old.md", kind: .removed, before: Data("old".utf8), after: nil),
            FileChange(path: "refs/new.md", kind: .added, before: nil, after: Data("new".utf8)),
        ])], now: now)
        #expect(outcome.updated.isEmpty)
        #expect(outcome.damaged.isEmpty)
        #expect(outcome.skipped["a"] != nil)
        #expect(text("SKILL.md") == "v1")
        #expect(text("old.md") == "old")
        #expect(text("refs/new.md") == nil)
    }
}
