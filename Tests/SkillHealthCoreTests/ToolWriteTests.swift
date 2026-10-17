import Foundation
import Testing
@testable import SkillHealthCore

/// The plugin's tool on the write path (fix, update and undo, plans, the lock, names the person
/// can't see), run as Claude Code runs it: the real binary, a scratch .claude folder, output read
/// back. Every write goes preview, then apply of the plan the preview made.
@Suite("The plugin's tool: the write path")
struct ToolWriteTests {
    static let binary = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: ".build/debug/skill-health")
    let home = URL.temporaryDirectory.appending(path: "skill-health-write-\(UUID().uuidString)")
    var skillHealth: URL { home.appending(path: "skill-health") }
    var pending: URL { skillHealth.appending(path: "pending") }
    var skill: URL { home.appending(path: "skills/supa") }
    var file: URL { skill.appending(path: "SKILL.md") }
    let original = "# Supa\r\n\r\nInstall:\r\n\r\n    npm install -g supabase \r\n"
    let findingID = "11111111-2222-5333-A444-555555555555"
    let secondID = "22222222-3333-5444-A555-666666666666"
    let thirdID = "33333333-4444-5555-A666-777777777777"

    struct Item {
        let id: String
        let quote: String
        let suggested: String?
        var skill = "supa"
    }

    /// One skill, loaded recently, with the given failing instructions.
    func setUp(skill name: String = "supa", text: String? = nil, items: [Item]? = nil) throws {
        let fm = FileManager.default
        let folder = home.appending(path: "skills/\(name)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: skillHealth, withIntermediateDirectories: true)
        try Data((text ?? original).utf8).write(to: folder.appending(path: "SKILL.md"))
        try writeFindings(items ?? [Item(id: findingID, quote: "npm install -g supabase", suggested: "npx supabase --help", skill: name)])
        // Loaded three times this week, in Claude Code's own session format.
        try fm.createDirectory(at: home.appending(path: "projects/-t"), withIntermediateDirectories: true)
        let stamp = Date.now.addingTimeInterval(-86_400).formatted(.iso8601)
        let lines = (0..<3).map { Self.load(of: folder, id: "t-\($0)", at: stamp) }
        try lines.joined(separator: "\n").write(to: home.appending(path: "projects/-t/s.jsonl"), atomically: true, encoding: .utf8)
        try #"{"version":1,"updatedAt":"2026-10-01T00:00:00Z","corrections":[],"checked":[]}"#
            .write(to: home.appending(path: "corrections.json"), atomically: true, encoding: .utf8)
    }

    /// The line Claude Code writes when a skill loads, in the field order the usage reader scans for.
    static func load(of folder: URL, id: String, at stamp: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: \#(folder.path(percentEncoded: false))\n\nx"}]},"isMeta":true,"uuid":"\#(id)","timestamp":"\#(stamp)"}"#
    }

    func writeFindings(_ items: [Item]) throws {
        let findings = items.map { item -> [String: Any] in
            var finding: [String: Any] = [
                "id": item.id, "skillName": item.skill, "severity": "breaks", "skillSays": item.quote,
                "trueNow": "Global installs are refused.", "source": "https://github.com/supabase/cli/issues/4496",
                "foundOn": "2026-10-01T00:00:00Z", "wrongSince": ["written": ["on": "2026-02-18T00:00:00Z"]],
                "keptBySecondCheck": true,
            ]
            if let suggested = item.suggested { finding["suggestedText"] = suggested }
            return finding
        }
        let audited = Dictionary(uniqueKeysWithValues: Set(items.map(\.skill)).map { ($0, "2026-10-01T00:00:00Z") })
        let object: [String: Any] = ["version": 1, "audited": audited, "findings": findings]
        try JSONSerialization.data(withJSONObject: object).write(to: skillHealth.appending(path: "findings.json"))
    }

    @discardableResult
    func run(_ arguments: String..., stdin: String? = nil) throws -> (status: Int32, out: String, err: String) {
        try run(arguments, stdin: stdin)
    }

    @discardableResult
    func run(_ arguments: [String], stdin: String? = nil) throws -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = arguments
        process.environment = ["SKILL_HEALTH_CLAUDE_HOME": home.path(percentEncoded: false),
                               "SKILL_HEALTH_CORRECTIONS": home.appending(path: "corrections.json").path(percentEncoded: false),
                               "PATH": "/usr/bin:/bin", "HOME": home.path(percentEncoded: false)]
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input
        try process.run()
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try input.fileHandleForWriting.close()
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let error = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self), String(decoding: error, as: UTF8.self))
    }

    func json(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func plan(from output: String) throws -> String {
        try #require(output.split(separator: "\n").last { $0.hasPrefix("Plan: ") }.map { String($0.dropFirst(6)) })
    }

    func planFile(_ id: String) -> URL { pending.appending(path: "\(id).json") }

    /// A plan's own summary, as the gate would show it.
    func summary(_ id: String) throws -> String {
        try #require(json(String(contentsOf: planFile(id), encoding: .utf8))["summary"] as? String)
    }

    /// A plan rewritten the way the tool writes one, with one field changed, as anything that can
    /// write ~/.claude/skill-health could.
    func tamper(_ id: String, _ change: (inout [String: Any]) -> Void) throws {
        var object = try json(String(contentsOf: planFile(id), encoding: .utf8))
        change(&object)
        let changed = try PlanStore.decoder.decode(PendingPlan.self, from: JSONSerialization.data(withJSONObject: object))
        try PlanStore.encoder.encode(changed).write(to: planFile(id))
    }

    // MARK: A plan file is read the way the gate reads it

    /// jq (the gate) takes the last of a key given twice, Swift's decoder the first: the prompt would
    /// show one change, and a plan could write another.
    @Test func aPlanFileWithAKeyTwiceIsNeverApplied() throws {
        try setUp()
        let id = try plan(from: run("fix", "preview", findingID).out)
        let url = planFile(id)
        let text = try String(contentsOf: url, encoding: .utf8)
        let shown = try summary(id)
        // A second "summary", ahead of the real one: what jq would read is the real one, what Swift
        // would read is the first.
        let doubled = text.replacing("\"summary\" : ", with: "\"summary\" : \"Fix something harmless\",\n  \"summary\" : ")
        #expect(doubled != text)
        try doubled.write(to: url, atomically: true, encoding: .utf8)
        let apply = try run("fix", "apply", id)
        #expect(apply.status == 1)
        #expect(apply.err.contains("was changed after the preview"))
        #expect(try Data(contentsOf: file) == Data(original.utf8))
        // The plan as the tool wrote it is applied.
        try text.write(to: url, atomically: true, encoding: .utf8)
        #expect(try summary(id) == shown)
        #expect(try run("fix", "apply", id).status == 0)
    }

    @Test func aPlanFiledUnderAnotherIdIsNeverApplied() throws {
        try setUp()
        let id = try plan(from: run("fix", "preview", findingID).out)
        let other = UUID().uuidString
        try FileManager.default.copyItem(at: planFile(id), to: planFile(other))
        let apply = try run("fix", "apply", other)
        #expect(apply.status == 1)
        #expect(apply.err.contains("was changed after the preview"))
        #expect(try Data(contentsOf: file) == Data(original.utf8))
    }

    // MARK: A summary fits the prompt in the unit the gate cuts it in

    /// 1,400 accented letters are 1,400 characters and 2,800 scalars: the tool counted characters,
    /// the gate (jq) cuts at 3,000 scalars, so a summary that passed here could be cut there.
    @Test func aSummaryOver3000ScalarsIsRefusedEvenWhenItIsUnder3000Characters() throws {
        let quote = String(repeating: "e\u{301}", count: 1_400)
        try setUp(text: "# Supa\n\n\(quote)\n", items: [Item(id: findingID, quote: quote, suggested: String(repeating: "y", count: 200))])
        let preview = try run("fix", "preview", findingID)
        #expect(preview.status == 1)
        #expect(preview.err.contains("too long to show in full in Claude Code's approval prompt"))
        // No plan was made.
        let made = (try? FileManager.default.contentsOfDirectory(atPath: pending.path(percentEncoded: false))) ?? []
        #expect(made.isEmpty)
    }

    @Test func aSummaryJustUnderTheLimitIsAcceptedWholeAndApplied() throws {
        let quote = String(repeating: "e\u{301}", count: 1_200)
        try setUp(text: "# Supa\n\n\(quote)\n", items: [Item(id: findingID, quote: quote, suggested: String(repeating: "y", count: 100))])
        let id = try plan(from: run("fix", "preview", findingID).out)
        let shown = try summary(id)
        #expect(shown.unicodeScalars.count < PendingPlan.summaryLimit)
        #expect(!shown.contains("cut short"))
        #expect(try run("fix", "apply", id).status == 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Supa\n\n\(String(repeating: "y", count: 100))\n")
    }

    // MARK: A long line is shown cut around the change

    /// The line is 4,023 characters: shown whole twice, the summary would be far over the prompt's
    /// limit, and the old refusal told the person to shorten a replacement that wasn't the cause.
    @Test func aFixOnAVeryLongLineIsShownCutAroundTheChangeAndWrittenWhole() throws {
        let before = String(repeating: "A", count: 2_000), after = String(repeating: "B", count: 2_000)
        let line = "\(before)npm install -g supabase\(after)"
        try setUp(text: "# Supa\n\n\(line)\n")
        let preview = try run("fix", "preview", findingID)
        #expect(preview.status == 0, "\(preview.err)")
        // The change starts after "np": 2,002 characters are the same before it, 2,000 after it.
        let head = "⟨… 1,942 unchanged characters …⟩", tail = "⟨… 1,940 unchanged characters …⟩"
        #expect(preview.out.contains("-3: \(head)\(String(repeating: "A", count: 58))np"))
        #expect(preview.out.contains("+3: \(head)"))
        #expect(preview.out.contains("\(String(repeating: "B", count: 60))\(tail)"))
        #expect(preview.out.count < 1_000)
        let id = try plan(from: preview.out)
        let shown = try summary(id)
        #expect(shown.contains(head) && shown.contains(tail))
        #expect(shown.unicodeScalars.count < PendingPlan.summaryLimit)
        // Apply builds the same text again, and writes the whole line.
        #expect(try run("fix", "apply", id).status == 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Supa\n\n\(before)npx supabase --help\(after)\n")
    }

    @Test func aReplacementTooLongToShowIsRefusedInWordsThatSayWhatItIs() throws {
        let replacement = String(repeating: "q", count: 2_000)
        // Two thousand characters are allowed; with the line's own text, two long lines are not.
        try setUp(text: "# Supa\n\n\(String(repeating: "x", count: 1_500))npm install -g supabase\n",
                  items: [Item(id: findingID, quote: "\(String(repeating: "x", count: 1_500))npm install -g supabase", suggested: nil)])
        let preview = try run("fix", "preview", findingID, "--with", "-", stdin: replacement)
        #expect(preview.status == 1)
        #expect(preview.err.contains("The text this change removes and adds is too long to show in full"))
        #expect(!preview.err.contains("fix fewer lines"))
    }

    // MARK: A fix is tied to its finding, and to nothing else in the file

    @Test func aFindingDecidedAfterThePreviewIsNotFixed() throws {
        try setUp()
        let id = try plan(from: run("fix", "preview", findingID).out)
        #expect(try run("decide", findingID, "set-aside", "30").status == 0)
        let apply = try run("fix", "apply", id)
        #expect(apply.status == 1)
        #expect(apply.err.contains("already decided"))
        #expect(try Data(contentsOf: file) == Data(original.utf8))
    }

    /// A plan that is self-consistent (its summary says what it writes) but writes more than the
    /// finding's line: the prompt would show it, but it isn't this fix.
    /// The forged plans below are only a test if their summary is the one apply rebuilds: an honest
    /// plan written the same way is applied.
    @Test func aPlanRewrittenWithItsOwnSummaryStillAppliesWhenItIsTheFix() throws {
        try setUp()
        let id = try plan(from: run("fix", "preview", findingID).out)
        try forge(id, after: original.replacing("npm install -g supabase", with: "npx supabase --help"))
        let apply = try run("fix", "apply", id)
        #expect(apply.status == 0, "\(apply.err)")
    }

    @Test func aPlanThatChangesMoreThanTheFindingsLineIsRefusedEvenWithItsSummaryMatching() throws {
        try setUp()
        let id = try plan(from: run("fix", "preview", findingID).out)
        // The fix, and a second edit on the first line.
        let edited = original.replacing("npm install -g supabase", with: "npx supabase --help").replacing("# Supa", with: "# Evil")
        try forge(id, after: edited)
        let apply = try run("fix", "apply", id)
        #expect(apply.status == 1)
        #expect(apply.err.contains("doesn't match the change it describes"))
        #expect(try Data(contentsOf: file) == Data(original.utf8))
    }

    @Test func aPlanWhoseReplacementHoldsAHiddenCharacterIsRefusedEvenWithItsSummaryMatching() throws {
        try setUp()
        let id = try plan(from: run("fix", "preview", findingID).out)
        let edited = original.replacing("npm install -g supabase", with: "npx\u{200B} supabase --help")
        try forge(id, after: edited)
        let apply = try run("fix", "apply", id)
        #expect(apply.status == 1)
        #expect(apply.err.contains("holds characters that don't show on screen"))
        #expect(try Data(contentsOf: file) == Data(original.utf8))
    }

    /// Rewrites a plan's text and its summary together, so the summary is what apply would rebuild.
    func forge(_ id: String, after: String) throws {
        let diff = ProposedWrite(file: file, before: original, after: after).condensedDiff
        try tamper(id) { object in
            var fix = object["fix"] as! [String: Any]
            fix["after"] = after
            object["fix"] = fix
            // The path as the tool names it (it resolves /var to /private/var).
            object["summary"] = "Fix supa, \(fix["file"] as! String)\n\n\(HiddenText.revealed(diff))"
        }
    }

    /// Without the results or the decisions, "no finding with that id" could be untrue.
    @Test func anUnreadableFileIsSaidBeforeNoFindingWithThatId() throws {
        try setUp()
        try "{ broken".write(to: skillHealth.appending(path: "findings.json"), atomically: true, encoding: .utf8)
        for arguments in [["fix", "preview", findingID], ["decide", findingID, "set-aside", "30"], ["issue", findingID]] {
            let result = try run(arguments)
            #expect(result.status == 1, "\(arguments)")
            #expect(result.err.contains("couldn't read the results of earlier checks"), "\(arguments): \(result.err)")
            #expect(!result.err.contains("no finding with that id"), "\(arguments)")
        }
        try setUp()
        try "{ broken".write(to: skillHealth.appending(path: "decisions.json"), atomically: true, encoding: .utf8)
        let reopen = try run("decide", findingID, "reopen")
        #expect(reopen.status == 1)
        #expect(reopen.err.contains("couldn't read what you fixed or set aside"))
        #expect(!reopen.err.contains("already open"))
    }

    // MARK: A change that adds nothing hidden doesn't say it does

    @Test func aFileThatStartsWithAByteOrderMarkDoesNotWarnOfHiddenCharacters() throws {
        try setUp(items: [Item(id: findingID, quote: "# Supa", suggested: "# Supabase")])
        try (Data([0xEF, 0xBB, 0xBF]) + Data(original.utf8)).write(to: file)
        let preview = try run("fix", "preview", findingID)
        #expect(preview.status == 0, "\(preview.err)")
        #expect(preview.out.contains("-1: ⟨U+FEFF⟩# Supa"))
        #expect(!preview.out.contains("This change holds characters that don't show on screen"))
        #expect(try run("fix", "apply", try plan(from: preview.out)).status == 0)
        #expect(try Data(contentsOf: file).prefix(3) == Data([0xEF, 0xBB, 0xBF]))
    }

    // MARK: Names reach the person spelled out

    @Test func aNameWithAHiddenCharacterIsSpelledOutInThePreviewAndTheSummary() throws {
        let name = "su\u{200B}pa"
        try setUp(skill: name)
        let preview = try run("fix", "preview", findingID)
        #expect(preview.status == 0, "\(preview.err)")
        #expect(preview.out.contains("su⟨U+200B⟩pa"))
        #expect(!preview.out.contains("\u{200B}"))
        let shown = try summary(try plan(from: preview.out))
        #expect(shown.hasPrefix("Fix su⟨U+200B⟩pa, "))
        #expect(!shown.contains("\u{200B}"))
    }

    // MARK: A plan is spent when its change is written, even if saying so fails

    @Test func aPlanThatCantBeRetiredSaysSoAndTheChangeStandsAndCantBeWrittenAgain() throws {
        try setUp()
        let id = try plan(from: run("fix", "preview", findingID).out)
        let path = planFile(id).path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }
        let apply = try run("fix", "apply", id)
        #expect(apply.status == 0, "\(apply.err)")
        #expect(apply.out.contains("Written to supa."))
        #expect(apply.err.contains(id))
        #expect(apply.err.contains("couldn't be marked used or deleted"))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("npx supabase --help"))
        // The plan is still there, but its finding is decided, so it writes nothing more.
        let again = try run("fix", "apply", id)
        #expect(again.status == 1)
        #expect(again.err.contains("already decided"))
    }

    // MARK: A folder Skill Health can't write to is not "busy"

    @Test func anUnwritableFolderIsSaidAsItIsNotCalledBusy() throws {
        try #require(getuid() != 0, "a folder can't be made unwritable for the superuser")
        try setUp()
        let id = try plan(from: run("fix", "preview", findingID).out)
        let folder = skillHealth.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }
        let apply = try run("fix", "apply", id)
        #expect(apply.status == 1)
        #expect(apply.err.contains("skill-health: can't write to \(folder)"))
        #expect(apply.err.contains("permission denied"))
        #expect(!apply.err.contains("Try again in a moment"))
        #expect(try Data(contentsOf: file) == Data(original.utf8))
    }

    // MARK: undo list names what it lists

    @Test func undoListNamesTheLineAndTheInstructionOfEveryEntry() throws {
        let long = "npm install --global --save-dev some-very-long-package-name-here"
        try setUp(text: original + "\r\n    \(long)\r\n", items: [
            Item(id: findingID, quote: "npm install -g supabase", suggested: "npx supabase --help"),
            Item(id: secondID, quote: "# Supa", suggested: nil),
            Item(id: thirdID, quote: long, suggested: nil),
        ])
        #expect(try run("fix", "apply", try plan(from: run("fix", "preview", findingID).out)).status == 0)
        #expect(try run("decide", secondID, "set-aside", "30").status == 0)
        #expect(try run("decide", thirdID, "another", "supa2").status == 1)   // not installed
        try FileManager.default.createDirectory(at: home.appending(path: "skills/supa2"), withIntermediateDirectories: true)
        try "# Two\n".write(to: home.appending(path: "skills/supa2/SKILL.md"), atomically: true, encoding: .utf8)
        #expect(try run("decide", thirdID, "another", "supa2").status == 0)

        let entries = try #require(try json(run("undo", "list", "--json").out)["entries"] as? [[String: Any]])
        let byID = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in (entry["id"] as? String).map { ($0, entry["detail"] as? String ?? "") } })
        #expect(byID["fix:\(findingID)"] == "Line 5 of SKILL.md: npx supabase --help")
        let day = Date.now.addingTimeInterval(30 * 86_400).formatted(date: .abbreviated, time: .omitted)
        #expect(byID["decision:\(secondID)"] == "Set aside until \(day): # Supa")
        #expect(byID["decision:\(thirdID)"] == "Using supa2 instead: npm install --global --save-dev some-ver…")
        #expect(entries.count == 3)
        // The text listing says the same.
        let text = try run("undo", "list").out
        #expect(text.contains("[fix:\(findingID)] supa: Fixed"))
        #expect(text.contains("Line 5 of SKILL.md: npx supabase --help."))
    }

    @Test func aFixWhoseFileHasChangedSinceIsStillNamedByItsText() throws {
        try setUp()
        #expect(try run("fix", "apply", try plan(from: run("fix", "preview", findingID).out)).status == 0)
        try (try String(contentsOf: file, encoding: .utf8) + "\r\nMy own note.\r\n").write(to: file, atomically: true, encoding: .utf8)
        let entries = try #require(try json(run("undo", "list", "--json").out)["entries"] as? [[String: Any]])
        #expect(entries.first?["detail"] as? String == "1 line in SKILL.md: npx supabase --help")
    }

    @Test func aSetAsideThatHasLapsedIsAlreadyOpenAndNotListed() throws {
        try setUp()
        #expect(try run("decide", findingID, "set-aside", "30").status == 0)
        #expect((try json(run("undo", "list", "--json").out)["entries"] as? [[String: Any]])?.count == 1)
        // Thirty-one days on, in the decisions file as the tool wrote it.
        let url = skillHealth.appending(path: "decisions.json")
        var object = try json(String(contentsOf: url, encoding: .utf8))
        var decisions = object["decisions"] as! [String: Any]
        for key in decisions.keys {
            var decision = decisions[key] as! [String: Any]
            decision["status"] = ["setAside": ["until": Date.now.addingTimeInterval(-86_400).formatted(.iso8601)]]
            decisions[key] = decision
        }
        object["decisions"] = decisions
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        #expect((try json(run("undo", "list", "--json").out)["entries"] as? [[String: Any]])?.isEmpty == true)
        // It is in the list to go through again.
        #expect(try json(run("findings", "--json").out)["failing"] as? Int == 1)
    }

    /// Results that can't be read could hide a fix: "nothing to undo" would be untrue.
    @Test func undoListFailsWhenTheResultsCantBeRead() throws {
        try setUp()
        try "{ broken".write(to: skillHealth.appending(path: "findings.json"), atomically: true, encoding: .utf8)
        let list = try run("undo", "list")
        #expect(list.status == 1)
        #expect(list.err.contains("couldn't read the results of earlier checks"))
        #expect(!list.out.contains("Nothing to undo"))
    }

    // MARK: Updates

    /// A plan for an update, as the tool's preview would make it, for a skill whose source can't be
    /// asked: its repository isn't a name GitHub could answer for, so the check fails at once.
    func updatePlan() throws -> (id: String, folder: URL) {
        let fm = FileManager.default
        let folder = home.appending(path: "skills/up")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: skillHealth, withIntermediateDirectories: true)
        try "v1\n".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let installedAt = Date(timeIntervalSince1970: 1_788_220_800)
        try #"{"source":"bad repo","subpath":"skills/up","installedAt":"\#(installedAt.formatted(.iso8601))"}"#
            .write(to: folder.appending(path: ".openskills.json"), atomically: true, encoding: .utf8)
        func blob(_ text: String) -> String { GitBlob.id(of: Data(text.utf8)) }
        var compare = CompareFile()
        compare.copies["up"] = .init(repo: "bad repo", subpath: "skills/up", installedFrom: "c1", head: "c2",
                                     installed: ["SKILL.md": blob("v1\n")], source: ["SKILL.md": blob("v2\n")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(compare).write(to: skillHealth.appending(path: "compare.json"))
        // Used this week.
        let sessions = home.appending(path: "projects/-u")
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        let stamp = Date.now.addingTimeInterval(-3_600).formatted(.iso8601)
        try Self.load(of: folder, id: "u-1", at: stamp).write(to: sessions.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)
        try #"{"version":1,"updatedAt":"2026-10-01T00:00:00Z","corrections":[],"checked":[]}"#
            .write(to: home.appending(path: "corrections.json"), atomically: true, encoding: .utf8)

        let store = PlanStore(paths: SkillHealthPaths(claudeHome: home))
        let id = UUID()
        let item = PendingPlan.Update.Skill(
            skill: "up", folder: folder.path(percentEncoded: false),
            origin: Origin(repo: "bad repo", subpath: "skills/up", installedAt: installedAt), repo: "bad repo", commit: "c2",
            historyURL: nil,
            changes: [.init(path: "SKILL.md", kind: .changed, before: blob("v1\n"), after: blob("v2\n"), staged: "up/SKILL.md", executable: nil)])
        let staged = store.staging(for: id).appending(path: "up")
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        try "v2\n".write(to: staged.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let summary = "Update 1 skill from its source (current files go to backups first):\n- up: 1 changed (from bad repo): SKILL.md"
        try store.save(PendingPlan(id: id, kind: .update, summary: summary, update: .init(skills: [item])))
        return (id.uuidString, folder)
    }

    /// The source is asked before anything is written, and when it can't confirm the files, the skill
    /// stays as it was and the plan stays good for another try.
    @Test func anUpdateIsNotWrittenWhenTheSourceCantConfirmIt() throws {
        let (id, folder) = try updatePlan()
        let apply = try run("update", "apply", id)
        #expect(apply.status == 1)
        #expect(apply.out.contains("up was left as it was: Skill Health couldn't reach GitHub to confirm this update"))
        #expect(apply.err.contains("Nothing was updated."))
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "v1\n")
        // Not spent: nothing was written.
        #expect(try PlanStore(paths: SkillHealthPaths(claudeHome: home)).ready(UUID(uuidString: id)!, kind: .update).used == false)
    }

    /// An update, made through the engine as the tool's apply does, then undone through the tool.
    func updatedSkill() async throws -> (folder: URL, stamp: String) {
        try setUp()
        let folder = skill
        let engine = Engine(paths: SkillHealthPaths(claudeHome: home))
        let origin = Origin(repo: "o/r", subpath: "skills/supa", installedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let update = CopyUpdate(skill: "supa", folder: folder, origin: origin, repo: "o/r", commit: "c2", changes: [
            FileChange(path: "SKILL.md", kind: .changed, before: Data(original.utf8), after: Data("# Supa 2\n".utf8)),
            FileChange(path: "refs/new.md", kind: .added, before: nil, after: Data("new\n".utf8)),
        ], historyURL: nil)
        let outcome = await engine.applyUpdates([update], now: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(outcome.updated == ["supa"])
        let manifest = try #require(engine.updateManifests().first)
        return (folder, manifest.folder.lastPathComponent)
    }

    @Test func anUpdatesUndoPreviewSaysWhatEachFileDoesFromItsBlobsAndIsAppliedOnlyFromThere() async throws {
        let (folder, stamp) = try await updatedSkill()
        let id = "update:supa:\(stamp)"
        let entries = try #require(try json(run("undo", "list", "--json").out)["entries"] as? [[String: Any]])
        #expect(entries.contains { $0["id"] as? String == id && $0["detail"] as? String == "2 files" })
        // A record that says "added" of a file it replaced reads from its blobs: the file is put back.
        let manifestURL = skillHealth.appending(path: "backups/supa/\(stamp)/\(UpdateManifest.fileName)")
        var object = try json(String(contentsOf: manifestURL, encoding: .utf8))
        var files = object["files"] as! [[String: Any]]
        for index in files.indices where files[index]["path"] as? String == "SKILL.md" { files[index]["kind"] = "added" }
        object["files"] = files
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)
        let lying = try run("undo", "preview", id)
        #expect(lying.status == 0, "\(lying.err)")
        #expect(lying.out.contains("  puts back SKILL.md"))
        #expect(lying.out.contains("  removes refs/new.md (the update added it)"))
        // ...and then Skill Health refuses to write from it.
        let refused = try run("undo", "apply", try plan(from: lying.out))
        #expect(refused.status == 1)
        #expect(refused.err.contains("doesn't match the skill it names"))
        #expect(try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) == "# Supa 2\n")
        // The honest record goes through.
        object["files"] = (object["files"] as! [[String: Any]]).map { entry in
            var entry = entry
            if entry["path"] as? String == "SKILL.md" { entry["kind"] = "changed" }
            return entry
        }
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)
        let undo = try run("undo", "apply", try plan(from: run("undo", "preview", id).out))
        #expect(undo.status == 0, "\(undo.err)")
        #expect(try Data(contentsOf: folder.appending(path: "SKILL.md")) == Data(original.utf8))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "refs/new.md").path(percentEncoded: false)))
    }

    /// A record that names a skill that isn't installed, in a folder that isn't its own, is not undone.
    @Test func anUpdatesUndoIsRefusedForASkillThatIsNotInstalledThere() async throws {
        let (folder, stamp) = try await updatedSkill()
        // The skill is gone from the list of skills (its SKILL.md is moved away), though its folder stays.
        try FileManager.default.moveItem(at: folder.appending(path: "SKILL.md"), to: home.appending(path: "SKILL.md.away"))
        let preview = try run("undo", "preview", "update:supa:\(stamp)")
        #expect(preview.status == 1)
        #expect(preview.err.contains("supa isn't installed in the folder it names"))
    }
}
