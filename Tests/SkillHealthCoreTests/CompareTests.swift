import Foundation
import Testing
@testable import SkillHealthCore

/// A source that answers from memory and counts what it was asked, so the tests can say how
/// many requests a check costs.
private actor FakeSource: SourceHost {
    var branches: [String: String] = [:]
    var heads: [String: String] = [:]
    /// repo -> [(commit, made at)] oldest first
    var history: [String: [(String, Date)]] = [:]
    var trees: [String: [String: String]] = [:]   // commit -> files
    var limitAfter: Int?
    private(set) var treeRequests = 0
    private(set) var requests = 0

    func set(repo: String, branch: String = "main", history: [(String, Date)], trees: [String: [String: String]]) {
        branches[repo] = branch
        heads[repo] = history.last?.0
        self.history[repo] = history
        for (commit, files) in trees { self.trees[commit] = files }
    }
    func limit(after count: Int) { limitAfter = count }

    private func count() throws(SkillHealthError) {
        requests += 1
        if let limitAfter, requests > limitAfter { throw .rateLimited(resetAt: nil) }
    }
    func defaultBranch(of repo: String) async throws(SkillHealthError) -> String {
        try count()
        guard let branch = branches[repo] else { throw .sourceNotFound(repo) }
        return branch
    }
    func headCommit(of repo: String, branch: String) async throws(SkillHealthError) -> String {
        try count()
        return heads[repo]!
    }
    func commits(of repo: String, branch: String, atOrBefore moment: Date, limit: Int) async throws(SkillHealthError) -> [String] {
        try count()
        return Array((history[repo] ?? []).filter { $0.1 <= moment }.reversed().prefix(limit).map(\.0))
    }
    func files(of repo: String, at commit: String) async throws(SkillHealthError) -> SourceTree {
        try count()
        treeRequests += 1
        return SourceTree(blobs: trees[commit] ?? [:], executables: executables[commit] ?? [])
    }
    var executables: [String: Set<String>] = [:]
    func setExecutable(_ paths: Set<String>, at commit: String) { executables[commit] = paths }
    var contents: [String: Data] = [:]   // "commit:path" -> bytes
    func put(_ data: Data, commit: String, path: String) { contents["\(commit):\(path)"] = data }
    func contents(of repo: String, at commit: String, path: String) async throws(SkillHealthError) -> Data {
        guard let data = contents["\(commit):\(path)"] else { throw .sourceNotFound(repo) }
        return data
    }
}

@Suite("Git blob ids match git's")
struct GitBlobTests {
    @Test func knownIds() {
        // `printf 'hello\n' | git hash-object --stdin` and the empty blob.
        #expect(GitBlob.id(of: Data("hello\n".utf8)) == "ce013625030ba8dba906f756967f9e9ca394464a")
        #expect(GitBlob.id(of: Data()) == "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
    }
}

@Suite("A local copy is its files, minus what is never part of a skill")
struct LocalCopyTests {
    @Test func ignoresReceiptsFinderFilesAndGitHistory() throws {
        let folder = URL.temporaryDirectory.appending(path: "skill-health-copy-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appending(path: "references"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appending(path: ".git/hooks"), withIntermediateDirectories: true)
        try "hello\n".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "x".write(to: folder.appending(path: "references/api.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: folder.appending(path: ".openskills.json"), atomically: true, encoding: .utf8)
        try "junk".write(to: folder.appending(path: "references/.DS_Store"), atomically: true, encoding: .utf8)
        try "ref".write(to: folder.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(LocalCopy.files(in: folder) == [
            "SKILL.md": "ce013625030ba8dba906f756967f9e9ca394464a",
            "references/api.md": GitBlob.id(of: Data("x".utf8)),
        ])
    }
}

@Suite("Each copy is classified against the version it was installed from")
struct CopyStateTests {
    let copy = CompareFile.Copy(repo: "o/r", subpath: "skills/a", installedFrom: "c1", head: "c2",
                                installed: ["SKILL.md": "v1"], source: ["SKILL.md": "v2"])

    @Test func fiveStates() {
        #expect(copy.state(local: ["SKILL.md": "v1"]) == .behind)
        #expect(copy.state(local: ["SKILL.md": "v2"]) == .current)
        #expect(copy.state(local: ["SKILL.md": "mine"]) == .changedBoth)
        var quiet = copy
        quiet.source = ["SKILL.md": "v1"]
        #expect(quiet.state(local: ["SKILL.md": "v1"]) == .current)
        #expect(quiet.state(local: ["SKILL.md": "v1", "notes.md": "n"]) == .changedHere)
        var gone = copy
        gone.source = nil
        #expect(gone.state(local: ["SKILL.md": "v1"]) == .removedAtSource)
    }

    @Test func historyLinksToTheSkillsFolderAtTheComparedCommit() {
        #expect(copy.historyURL?.absoluteString == "https://github.com/o/r/commits/c2/skills/a")
    }
}

@Suite("Checking sources")
struct ComparerTests {
    let june = Date(timeIntervalSince1970: 1_780_000_000)
    var july: Date { june.addingTimeInterval(30 * 86_400) }

    func skill(_ name: String, repo: String = "o/r", subpath: String? = nil, at: Date) -> Skill {
        Skill(name: name, folder: URL(filePath: "/tmp/\(name)"),
              origin: Origin(repo: repo, subpath: subpath ?? "skills/\(name)", installedAt: at))
    }

    @Test func findsTheInstalledVersionAndTheSourceToday() async throws {
        let source = FakeSource()
        await source.set(repo: "o/r", history: [("c1", june.addingTimeInterval(-60)), ("c2", july)], trees: [
            "c1": ["skills/a/SKILL.md": "a1", "skills/b/SKILL.md": "b1", "skills/gone/SKILL.md": "g1", "README.md": "r"],
            "c2": ["skills/a/SKILL.md": "a2", "skills/b/SKILL.md": "b1", "README.md": "r2"],
        ])
        let skills = [skill("a", at: june), skill("b", at: june.addingTimeInterval(5)), skill("gone", at: june)]
        let file = await Comparer(host: source).check(skills, previous: CompareFile(), now: july)

        #expect(file.copies["a"]?.installedFrom == "c1")
        #expect(file.copies["a"]?.installed == ["SKILL.md": "a1"])
        #expect(file.copies["a"]?.source == ["SKILL.md": "a2"])
        #expect(file.copies["b"]?.source == ["SKILL.md": "b1"])
        #expect(file.copies["gone"]?.source == nil)
        #expect(file.sources["o/r"]?.head == "c2")
        #expect(file.stopped == nil)
        // branch, head, one install lookup, two file lists.
        #expect(await source.requests == 5)
    }

    @Test func aQuietSourceCostsTwoRequestsAndNoFileLists() async throws {
        let source = FakeSource()
        await source.set(repo: "o/r", history: [("c1", june.addingTimeInterval(-60))], trees: [
            "c1": ["skills/a/SKILL.md": "a1"],
        ])
        let skills = [skill("a", at: june)]
        let first = await Comparer(host: source).check(skills, previous: CompareFile(), now: july)
        let before = await source.requests
        let treesBefore = await source.treeRequests
        _ = await Comparer(host: source).check(skills, previous: first, now: july.addingTimeInterval(86_400))
        #expect(await source.requests - before == 2)
        #expect(await source.treeRequests == treesBefore)
    }

    @Test func installsDaysApartEachGetTheirOwnVersion() async throws {
        let source = FakeSource()
        await source.set(repo: "o/r", history: [("c1", june.addingTimeInterval(-60)), ("c2", june.addingTimeInterval(86_400))],
                         trees: ["c1": ["skills/a/SKILL.md": "a1"], "c2": ["skills/a/SKILL.md": "a1", "skills/b/SKILL.md": "b2"]])
        let file = await Comparer(host: source).check(
            [skill("a", at: june), skill("b", at: june.addingTimeInterval(2 * 86_400))], previous: CompareFile(), now: july)
        #expect(file.copies["a"]?.installedFrom == "c1")
        #expect(file.copies["b"]?.installedFrom == "c2")
    }

    @Test func theInstalledVersionIsTheOneTheCopiesMatchNotJustTheNewestByDate() async throws {
        // A repository that merges pull requests: c2 is dated before the install but reached the
        // branch after it. The untouched copy on disk is byte for byte c1.
        let folder = URL.temporaryDirectory.appending(path: "skill-health-merge-\(UUID().uuidString)/a")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "v1".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let source = FakeSource()
        await source.set(repo: "o/r", history: [("c1", june.addingTimeInterval(-3600)), ("c2", june.addingTimeInterval(-60)), ("c3", july)],
                         trees: ["c1": ["skills/a/SKILL.md": GitBlob.id(of: Data("v1".utf8))],
                                 "c2": ["skills/a/SKILL.md": GitBlob.id(of: Data("v2".utf8))],
                                 "c3": ["skills/a/SKILL.md": GitBlob.id(of: Data("v2".utf8))]])
        let a = Skill(name: "a", folder: folder, origin: Origin(repo: "o/r", subpath: "skills/a", installedAt: june))
        let file = await Comparer(host: source).check([a], previous: CompareFile(), now: july)
        #expect(file.copies["a"]?.installedFrom == "c1")
        #expect(file.copies["a"]?.state(local: LocalCopy.files(in: folder)) == .behind)
    }

    @Test func executableFilesAreKnownFromTheSource() async throws {
        let source = FakeSource()
        await source.set(repo: "o/r", history: [("c1", june.addingTimeInterval(-60))],
                         trees: ["c1": ["skills/a/SKILL.md": "s", "skills/a/scripts/run.sh": "r"]])
        await source.setExecutable(["skills/a/scripts/run.sh"], at: "c1")
        let file = await Comparer(host: source).check([skill("a", at: june)], previous: CompareFile(), now: july)
        #expect(file.copies["a"]?.sourceExecutables == ["scripts/run.sh"])
    }

    @Test func anUpdateRecordHoldsOnlyForTheInstallItWasMadeAgainst() async throws {
        let source = FakeSource()
        await source.set(repo: "o/r", history: [("c1", june.addingTimeInterval(-60)), ("c2", july)],
                         trees: ["c1": ["skills/a/SKILL.md": "a1"], "c2": ["skills/a/SKILL.md": "a2"]])
        var records = UpdateRecords()
        records.records["a"] = .init(repo: "o/r", subpath: "skills/a", installedAt: june, commit: "c2", updatedAt: july)
        let updated = await Comparer(host: source).check([skill("a", at: june)], previous: CompareFile(), records: records, now: july)
        #expect(updated.copies["a"]?.installedFrom == "c2")
        // Reinstalled later (a new receipt): the record no longer speaks for this copy.
        let reinstalled = skill("a", at: july.addingTimeInterval(60))
        #expect(records.commit(for: reinstalled) == nil)
        #expect(records.kept(for: [reinstalled]).records.isEmpty)
        #expect(records.kept(for: []).records.isEmpty)
        #expect(records.kept(for: [skill("a", at: june)]) == records)
    }

    @Test func aRepositoryThatIsTheSkillComparesFromItsRoot() async throws {
        let source = FakeSource()
        await source.set(repo: "o/one", history: [("c1", june.addingTimeInterval(-60))], trees: [
            "c1": ["SKILL.md": "s", ".git/HEAD": "never in a tree, but ignored if it were", ".DS_Store": "x"],
        ])
        let file = await Comparer(host: source).check([skill("one", repo: "o/one", subpath: "", at: june)],
                                                      previous: CompareFile(), now: july)
        #expect(file.copies["one"]?.installed == ["SKILL.md": "s"])
    }

    @Test func aMissingSourceIsReportedAndTheRestStillChecked() async throws {
        let source = FakeSource()
        await source.set(repo: "o/r", history: [("c1", june.addingTimeInterval(-60))], trees: ["c1": ["skills/a/SKILL.md": "a1"]])
        let file = await Comparer(host: source).check([skill("a", at: june), skill("x", repo: "gone/repo", at: june)],
                                                      previous: CompareFile(), now: july)
        #expect(file.copies["a"] != nil)
        #expect(file.sources["gone/repo"]?.problem == "gone/repo isn't on GitHub any more, or it's private.")
    }

    @Test func theHourlyLimitStopsTheCheckAndSaysSo() async throws {
        let source = FakeSource()
        await source.set(repo: "a/first", history: [("c1", june.addingTimeInterval(-60))], trees: ["c1": ["skills/a/SKILL.md": "a1"]])
        await source.set(repo: "b/second", history: [("d1", june.addingTimeInterval(-60))], trees: ["d1": ["skills/b/SKILL.md": "b1"]])
        await source.limit(after: 4)
        let file = await Comparer(host: source).check(
            [skill("a", repo: "a/first", at: june), skill("b", repo: "b/second", at: june)], previous: CompareFile(), now: july)
        #expect(file.copies["a"] != nil)
        #expect(file.copies["b"] == nil)
        #expect(file.stopped?.hasPrefix("GitHub allows 60 requests an hour") == true)
    }

    @Test func repositoryNamesFromReceiptsAreCheckedBeforeUse() {
        #expect(GitHubSource.isValidRepo("TerminalSkills/skills"))
        #expect(GitHubSource.isValidRepo("HoangNguyen0403/agent-skills-standard"))
        #expect(!GitHubSource.isValidRepo("../../user"))
        #expect(!GitHubSource.isValidRepo("o/r/extra"))
        #expect(!GitHubSource.isValidRepo("o/r?x=1"))
        #expect(!GitHubSource.isValidRepo("o/.."))
    }
}

@Suite("Settings files from before a switch existed still load")
struct SettingsDecodingTests {
    @Test func missingSwitchGetsItsDefault() throws {
        let old = Data(#"{"sessionNote":false,"correctionsForClaude":true}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: old)
        #expect(settings.sessionNote == false)
        #expect(settings.dailyCheck == true)
    }
}
