import Foundation
import Testing
@testable import SkillHealthCore

/// The tool's read commands and the words they say, run as Claude Code runs them: the real binary,
/// a scratch .claude folder, the output read back. Every case here was a sentence that said more
/// than Skill Health knew: an all-clear over an unreadable entry, over set-aside instructions, over a
/// comparison that never reached GitHub.
@Suite("The tool's read commands")
struct ToolReadTests {
    static let binary = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: ".build/debug/skill-health")
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let home = URL.temporaryDirectory.appending(path: "skill-health-read-\(UUID().uuidString)")
    var skillHealth: URL { home.appending(path: "skill-health") }
    let quote = "npm install -g supabase"
    let checkedStamp = "2026-10-01T00:00:00Z"

    // MARK: Scratch folder

    /// A finding as findings.json holds it. The id is the n-th of a fixed series, so a test can name it.
    func finding(_ n: Int, skill: String = "supa", severity: String = "breaks", says: String? = nil,
                 wrongSince: String = #"{"undated":{}}"#) -> String {
        """
        {"id":"\(id(n))","skillName":"\(skill)","severity":"\(severity)","skillSays":"\(says ?? quote)",
         "trueNow":"Global installs are refused.","source":"https://github.com/supabase/cli/issues/4496",
         "foundOn":"2026-10-01T00:00:00Z","wrongSince":\(wrongSince),"suggestedText":"npx supabase --help","keptBySecondCheck":true}
        """
    }

    func id(_ n: Int) -> String { "11111111-2222-5333-A444-55555555555\(n)" }

    /// Skills with their loads this week (a skill with 0 is installed and unused), the results file,
    /// and Claude Code's own session files. `coversWindow` adds a session older than the window, so
    /// the count of skills used is no longer a lower bound.
    func scratch(skills: [(name: String, loads: Int)] = [("supa", 3), ("other", 0)], findings: [String] = [],
                 audited: [String] = ["supa"], rawFindings: String? = nil, coversWindow: Bool = false,
                 sessions: Bool = true) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: skillHealth, withIntermediateDirectories: true)
        for (name, _) in skills {
            let folder = home.appending(path: "skills/\(name)")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try "# \(name)\n\nInstall:\n\n    \(quote) \n".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        }
        let dates = audited.map { #""\#($0)":"\#(checkedStamp)""# }.joined(separator: ",")
        let body = rawFindings ?? findings.joined(separator: ",")
        try #"{"version":1,"audited":{\#(dates)},"findings":[\#(body)]}"#
            .write(to: skillHealth.appending(path: "findings.json"), atomically: true, encoding: .utf8)
        if sessions {
            try fm.createDirectory(at: home.appending(path: "projects/-t"), withIntermediateDirectories: true)
            let stamp = Date.now.addingTimeInterval(-86_400).formatted(.iso8601)
            var lines: [String] = []
            for (name, loads) in skills {
                for n in 0..<loads {
                    lines.append(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: \#(home.path(percentEncoded: false))/skills/\#(name)\n\nx"}]},"isMeta":true,"uuid":"t-\#(name)-\#(n)","timestamp":"\#(stamp)"}"#)
                }
            }
            try lines.joined(separator: "\n").write(to: home.appending(path: "projects/-t/s.jsonl"), atomically: true, encoding: .utf8)
        }
        if coversWindow {
            try fm.createDirectory(at: home.appending(path: "projects/-old"), withIntermediateDirectories: true)
            let old = home.appending(path: "projects/-old/o.jsonl")
            try "{}".write(to: old, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: Date.now.addingTimeInterval(-100 * 86_400)], ofItemAtPath: old.path(percentEncoded: false))
        }
        try #"{"version":1,"updatedAt":"2026-10-01T00:00:00Z","corrections":[],"checked":[]}"#
            .write(to: home.appending(path: "corrections.json"), atomically: true, encoding: .utf8)
    }

    func write(_ decisions: DecisionsFile) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(decisions).write(to: skillHealth.appending(path: "decisions.json"))
    }

    func write(_ compare: CompareFile) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(compare).write(to: skillHealth.appending(path: "compare.json"))
    }

    /// The receipt openskills leaves in a skill folder: where the skill came from.
    func receipt(_ skill: String, repo: String, subpath: String = "skills", installedAt: String = "2026-01-01T00:00:00Z") throws {
        try #"{"source":"\#(repo)","subpath":"\#(subpath)/\#(skill)","installedAt":"\#(installedAt)"}"#
            .write(to: home.appending(path: "skills/\(skill)/.openskills.json"), atomically: true, encoding: .utf8)
    }

    func blob(_ text: String) -> String { GitBlob.id(of: Data(text.utf8)) }

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

    func json(_ arguments: [String]) throws -> [String: Any] {
        let result = try run(arguments)
        #expect(result.status == 0, "\(arguments): \(result.err)")
        return try #require(try JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
    }

    func first(_ arguments: [String]) throws -> [String: Any] {
        try #require((try json(arguments)["findings"] as? [[String: Any]])?.first)
    }

    // MARK: 1. An entry that can't be read is never an all-clear

    @Test func anEntryThatCantBeReadIsNeverAnAllClear() throws {
        try scratch(rawFindings: #"{"id":"not-a-finding"}"#)
        let findings = try run(["findings"])
        #expect(findings.status == 0)
        #expect(!findings.out.contains("Nothing to fix"))
        #expect(!findings.out.contains("No failing or deprecated"))
        #expect(findings.out.contains("1 instruction in the results of earlier checks couldn't be read"))
        let named = try run(["findings", "supa"])
        #expect(!named.out.contains("Nothing to fix"))
        #expect(named.out.contains("couldn't be read"))
        let status = try run(["status"])
        #expect(!status.out.contains("No failing or deprecated"))
        #expect(!status.out.contains("No open failing or deprecated"))
        #expect(status.out.contains("1 instruction in the results of earlier checks couldn't be read"))
        let object = try json(["findings", "--json"])
        #expect((object["findings"] as? [Any])?.isEmpty == true)
        #expect((object["problem"] as? String)?.contains("couldn't be read") == true)
        #expect((try json(["status", "--json"])["findingsProblem"] as? String)?.contains("couldn't be read") == true)
    }

    // MARK: 2. Set-aside instructions are still wrong

    @Test func setAsideInstructionsAreSaidWhereNothingIsOpen() throws {
        try scratch(findings: [finding(1), finding(2, severity: "deprecated", says: "old flag")])
        #expect(try run(["decide", id(1), "set-aside", "30"]).status == 0)
        // One failing is set aside, one deprecated is still open: the list isn't empty.
        let one = try json(["findings", "--json"])
        #expect(one["setAsideFailing"] as? Int == 1)
        #expect(one["setAsideDeprecated"] as? Int == 0)
        #expect(try run(["decide", id(2), "another", "other"]).status == 0)

        let text = try run(["findings"])
        #expect(text.out.hasPrefix("Nothing open to fix. 1 failing instruction and 1 deprecated are set aside; /skill-health:undo lists them.\n"))
        #expect(!text.out.contains("Nothing to fix"))
        #expect(try run(["findings", "supa"]).out.hasPrefix("Nothing open to fix in supa. 1 failing instruction and 1 deprecated are set aside;"))
        let status = try json(["status", "--json"])
        #expect(status["setAsideFailing"] as? Int == 1)
        #expect(status["setAsideDeprecated"] as? Int == 1)
        let statusText = try run(["status"]).out
        #expect(statusText.contains("No open failing or deprecated instructions"))
        #expect(statusText.contains("1 failing instruction and 1 deprecated are set aside; /skill-health:undo lists them."))
    }

    @Test func setAsideCountsReadRightForOneAndMany() {
        #expect(Self.line(1, 0) == "1 failing instruction is set aside; /skill-health:undo lists them.")
        #expect(Self.line(2, 0) == "2 failing instructions are set aside; /skill-health:undo lists them.")
        #expect(Self.line(0, 1) == "1 deprecated instruction is set aside; /skill-health:undo lists them.")
        #expect(Self.line(0, 3) == "3 deprecated instructions are set aside; /skill-health:undo lists them.")
    }

    /// The same sentences through the tool, from fixtures with that many set aside.
    static func line(_ failing: Int, _ deprecated: Int) -> String? {
        let tool = ToolReadTests()
        return (try? tool.sentence(failing: failing, deprecated: deprecated)) ?? nil
    }

    func sentence(failing: Int, deprecated: Int) throws -> String? {
        let entries = (0..<failing).map { finding($0 + 1, says: "failing \($0)") }
            + (0..<deprecated).map { finding($0 + 5, severity: "deprecated", says: "deprecated \($0)") }
        try scratch(findings: entries)
        for n in (0..<failing).map({ $0 + 1 }) + (0..<deprecated).map({ $0 + 5 }) {
            try run(["decide", id(n), "set-aside", "30"])
        }
        let out = try run(["findings"]).out
        return out.split(separator: "\n").first.map(String.init)?.replacing("Nothing open to fix. ", with: "")
    }

    // MARK: 3 and 8. A save never drops what it couldn't read; a check says so before it spends anything

    @Test func aSaveIsRefusedWhileEntriesOfOtherSkillsCouldntBeRead() throws {
        try scratch(rawFindings: #"{"id":"not-a-finding"}"#)
        let before = try Data(contentsOf: skillHealth.appending(path: "findings.json"))
        let results = ##"{"audited":["other"],"findings":[]}"##
        let save = try run(["save-findings", "-"], stdin: results)
        #expect(save.status == 1)
        #expect(save.err.contains("1 instruction in the results of earlier checks couldn't be read, and saving would lose it"))
        #expect(save.err.contains("Move ~/.claude/skill-health/findings.json aside, then run /skill-health:check again"))
        #expect(try Data(contentsOf: skillHealth.appending(path: "findings.json")) == before)
        // The plan stops first, so a check doesn't spend tokens on results that couldn't be saved.
        let plan = try run(["plan", "--json"])
        #expect(plan.status == 1)
        #expect(plan.err.contains("couldn't be read, and saving would lose it"))
    }

    @Test func manyUnreadableEntriesAreCounted() throws {
        try scratch(rawFindings: #"{"id":"a"},{"id":"b"},{"id":"c"}"#)
        #expect(try run(["plan"]).err.contains("3 instructions in the results of earlier checks couldn't be read, and saving would lose them"))
    }

    @Test func aCheckIsNotStoppedByDecisionsItNeverWrites() throws {
        try scratch(findings: [finding(1)])
        try "{ broken".write(to: skillHealth.appending(path: "decisions.json"), atomically: true, encoding: .utf8)
        #expect(try run(["plan", "--json"]).status == 0)
        #expect(try run(["save-findings", "-"], stdin: ##"{"audited":["supa"],"findings":[]}"##).status == 0)
        // Anything that answers about what to fix still stops: "nothing to fix" could be untrue.
        #expect(try run(["findings"]).status == 1)
    }

    @Test func aFindingsFileThatCantBeReadStopsThePlan() throws {
        try scratch()
        try "{ broken".write(to: skillHealth.appending(path: "findings.json"), atomically: true, encoding: .utf8)
        #expect(try run(["plan", "--json"]).err.contains("couldn't read the results of earlier checks"))
    }

    @Test func theAppsSaveRefusesTheSameThing() async throws {
        try scratch(rawFindings: #"{"id":"not-a-finding"}"#)
        let engine = Engine(paths: SkillHealthPaths(claudeHome: home))
        let results = AuditResults(audited: ["other"], findings: [])
        await #expect(throws: SkillHealthError.auditRejected(AuditResults.unreadableEntriesProblem(1))) { try await engine.save(results) }
        #expect(AuditResults.unreadableEntriesProblem(2).hasPrefix("2 instructions"))
    }

    // MARK: 5. What the source says about a line

    @Test func upstreamNamesTheFileAndTheSkillThatsGone() throws {
        try scratch(findings: [finding(1)])
        try receipt("supa", repo: "o/r")
        let here = "# supa\n\nInstall:\n\n    \(quote) \n"
        func upstream(source: [String: String]?) throws -> String? {
            var compare = CompareFile()
            compare.copies["supa"] = .init(repo: "o/r", subpath: "skills/supa", installedFrom: "c1", head: "c2",
                                           installed: ["SKILL.md": blob(here)], source: source)
            try write(compare)
            return try first(["findings", "--json"])["upstream"] as? String
        }
        #expect(try upstream(source: nil) == "skillRemoved")                                  // the source dropped the whole skill
        #expect(try upstream(source: ["references/x.md": blob("x")]) == "fileRemoved")        // only this file is gone
        #expect(try upstream(source: ["SKILL.md": blob(here)]) == "same")
        #expect(try upstream(source: ["SKILL.md": blob(here + "newer\n")]) == "differs")
        try FileManager.default.removeItem(at: skillHealth.appending(path: "compare.json"))
        #expect(try first(["findings", "--json"])["upstream"] as? String == "unknown")
    }

    // MARK: 6. Why a decision no longer holds

    @Test func aDecisionThatNoLongerHoldsSaysWhy() throws {
        try scratch(findings: [finding(1)])
        let past = Date.now.addingTimeInterval(-86_400), later = Date.now.addingTimeInterval(30 * 86_400)
        func lapsed(_ decision: Decision) throws -> [String: Any]? {
            var file = DecisionsFile()
            file[UUID(uuidString: id(1))!] = decision
            try write(file)
            return try first(["findings", "--json"])["decision"] as? [String: Any]
        }
        #expect(try lapsed(.init(status: .setAside(until: past), decidedAt: past.addingTimeInterval(-86_400)))?["lapsed"] as? String == "expired")

        // A set-aside "until update" comes back when the source's files change, before its date.
        var compare = CompareFile()
        compare.copies["supa"] = .init(repo: "o/r", subpath: "skills/supa", installedFrom: "c1", head: "c2",
                                       installed: [:], source: ["SKILL.md": blob("newer")])
        try write(compare)
        let moved = try lapsed(.init(status: .setAside(until: later), decidedAt: past, untilSourceChanges: "SKILL.md=\(blob("older"))"))
        #expect(moved?["lapsed"] as? String == "sourceChanged")
        #expect(moved?["status"] as? String == "setAside")
        #expect(moved?["until"] is String)

        // A fixed line that is back: the file says the wrong line and isn't what the fix wrote.
        let patch = PatchRecord(file: home.appending(path: "skills/supa/SKILL.md").path(percentEncoded: false),
                                backup: "/nowhere", original: blob("a"), written: blob("b"))
        let back = try lapsed(.init(status: .patched(on: past), decidedAt: past, patch: patch))
        #expect(back?["lapsed"] as? String == "lineCameBack")
        #expect(back?["status"] as? String == "patched")
    }

    @Test func aDecisionThatStillHoldsIsntListed() throws {
        try scratch(findings: [finding(1)])
        #expect(try run(["decide", id(1), "set-aside", "30"]).status == 0)
        let object = try json(["findings", "--json"])
        #expect((object["findings"] as? [Any])?.isEmpty == true)
    }

    // MARK: 7. save-findings says what it saved and which rule a result broke

    func results(_ change: (inout [String: Any]) -> Void = { _ in }, audited: [String] = ["supa"], copies: Int = 1) throws -> String {
        var item: [String: Any] = ["skillName": "supa", "severity": "breaks", "skillSays": quote, "trueNow": "Refused.",
                                   "source": "https://github.com/supabase/cli/issues/4496", "keptBySecondCheck": true]
        change(&item)
        let data = try JSONSerialization.data(withJSONObject: ["audited": audited, "findings": Array(repeating: item, count: copies)])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Fourth round: what a person couldn't tell from the answer

    /// A skill that isn't installed, or a quote that isn't in its file, can't be fixed. The rest of
    /// an expensive check is still saved, and what was left out is named.
    @Test func aCheckKeepsWhatCanBeFixedAndNamesWhatCantBe() throws {
        try scratch(findings: [])
        let gone = try results({ $0["skillSays"] = "a line that isn't in the file" }, audited: ["supa", "ghost"])
        let saved = try run(["save-findings", "-"], stdin: gone)
        #expect(saved.status == 0, "\(saved.err)")
        #expect(saved.out.contains("Saved 0 findings for 1 checked skill."))
        #expect(saved.out.contains("ghost isn't installed, so it wasn't saved as checked."))
        #expect(saved.out.contains("Finding 0 wasn't saved: its quote isn't in supa/SKILL.md."))
        // A malformed result is still refused with the rule it broke, before anything is dropped.
        #expect(try run(["save-findings", "-"], stdin: results({ $0["skillSays"] = "" })).err.contains("skillSays is empty"))
    }

    /// Each file's problem in its own field, so a skill knows which answer it can't trust.
    @Test func statusNamesEachUnreadableFileSeparately() throws {
        try scratch()
        try "{ broken".write(to: skillHealth.appending(path: "decisions.json"), atomically: true, encoding: .utf8)
        try "{ broken".write(to: skillHealth.appending(path: "compare.json"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: home.appending(path: "corrections.json"))
        let status = try json(["status", "--json"])
        #expect(status["findingsProblem"] is NSNull)
        #expect((status["decisionsProblem"] as? String)?.contains("couldn't read what you fixed or set aside") == true)
        #expect((status["decisionsProblem"] as? String)?.contains("It isn't valid JSON.") == true)
        #expect((status["compareProblem"] as? String)?.contains("couldn't read its last comparison with GitHub") == true)
        #expect((status["correctionsProblem"] as? String)?.contains("couldn't find its known corrections") == true)
        // An unreadable comparison isn't "never compared".
        #expect(try run(["update", "list"]).out.contains("couldn't read its last comparison with GitHub"))
        // And without the known corrections there is no all-clear.
        try FileManager.default.removeItem(at: skillHealth.appending(path: "decisions.json"))
        let findings = try run(["findings"]).out
        #expect(!findings.contains("Nothing to fix"))
        #expect(findings.contains("couldn't find its known corrections"))
        // A refusal doesn't read "skill-health: Skill Health couldn't".
        try "{ broken".write(to: skillHealth.appending(path: "findings.json"), atomically: true, encoding: .utf8)
        #expect(try run(["plan"]).err.hasPrefix("skill-health: couldn't read the results of earlier checks"))
    }

    /// An update whose undo record can't be read is said, not left out of "Nothing to undo".
    @Test func anUnreadableUndoRecordIsSaid() throws {
        try scratch()
        let run1 = skillHealth.appending(path: "backups/supa/2026-10-03T12-00-00Z-update")
        try FileManager.default.createDirectory(at: run1, withIntermediateDirectories: true)
        try "{ broken".write(to: run1.appending(path: ".manifest.json"), atomically: true, encoding: .utf8)
        let list = try run(["undo", "list"]).out
        #expect(!list.contains("Nothing to undo"))
        #expect(list.contains("1 update's undo record couldn't be read, so it can't be undone"))
        #expect((try json(["undo", "list", "--json"])["unreadable"] as? [String])?.count == 1)
    }

    /// "Already wrong when installed" shows a day as fact, so it is kept only when it is the day this copy was
    /// installed. Another day is saved without a date, and the check says so.
    @Test func anInstallDayIsKeptOnlyWhenItIsThisCopysInstallDay() throws {
        try scratch(findings: [])
        try receipt("supa", repo: "owner/skills", installedAt: "2026-06-01T18:27:41Z")
        let right = try run(["save-findings", "-"], stdin: results({ $0["wrongSince"] = "installed:2026-06-01" }))
        #expect(right.status == 0, "\(right.err)")
        #expect(right.out == "Saved 1 finding for 1 checked skill.\n")
        #expect(try first(["findings", "--json"])["wrongSince"] as? String == "Already wrong when installed (Jun 1, 2026)")

        let wrong = try run(["save-findings", "-"], stdin: results({ $0["wrongSince"] = "installed:2026-06-02" }))
        #expect(wrong.status == 0, "\(wrong.err)")
        #expect(wrong.out == "Saved 1 finding for 1 checked skill.\nFinding 0 was saved without a date: supa was installed on 2026-06-01, not 2026-06-02.\n")
        #expect(try first(["findings", "--json"])["wrongSince"] as? String == "When it became wrong isn't dated")

        // The other dates are the auditor's to give from its sources, so they are not compared with the install.
        for label in ["since:2025-03-18", "written:2026-02-18"] {
            #expect(try run(["save-findings", "-"], stdin: results({ $0["wrongSince"] = label })).out == "Saved 1 finding for 1 checked skill.\n", "\(label)")
        }
    }

    @Test func aSkillWithNoInstallDateCantBeAlreadyWrongWhenInstalled() throws {
        try scratch(findings: [])
        let saved = try run(["save-findings", "-"], stdin: results({ $0["wrongSince"] = "installed:2026-06-01" }))
        #expect(saved.status == 0, "\(saved.err)")
        #expect(saved.out == "Saved 1 finding for 1 checked skill.\nFinding 0 was saved without a date: supa has no install date.\n")
        #expect(try first(["findings", "--json"])["wrongSince"] as? String == "When it became wrong isn't dated")
    }

    @Test func aFindingAlreadyWrongWhenInstalledIsPrintedWithTheDay() throws {
        try scratch(findings: [finding(1, wrongSince: #"{"installed":{"on":"2026-06-01T00:00:00Z"}}"#)])
        #expect(try first(["findings", "--json"])["wrongSince"] as? String == "Already wrong when installed (Jun 1, 2026)")
        #expect(try run(["findings"]).out.contains("Already wrong when installed (Jun 1, 2026)."))
    }

    @Test func saveCountsWhatWasActuallySaved() throws {
        try scratch(findings: [])
        // The same wrong line twice is one finding, and a skill listed twice is one skill.
        let twice = try results(audited: ["supa", "supa"], copies: 2)
        let saved = try run(["save-findings", "-"], stdin: twice)
        #expect(saved.status == 0, "\(saved.err)")
        #expect(saved.out == "Saved 1 finding for 1 checked skill.\n")
        #expect(try run(["save-findings", "-"], stdin: ##"{"audited":["supa","other"],"findings":[]}"##).out == "Saved 0 findings for 2 checked skills.\n")
    }

    @Test func aResultThatIsntAnObjectSaysWhatItMustBe() throws {
        try scratch()
        for text in ["[]", "7", "null", #""text""#] {
            let refused = try run(["save-findings", "-"], stdin: text)
            #expect(refused.status == 1, "\(text)")
            #expect(refused.err == "skill-health: Nothing saved: the results must be a JSON object with audited and findings.\n", "\(text): \(refused.err)")
        }
        #expect(try run(["save-findings", "-"], stdin: "not json").err.contains("aren't valid JSON"))
        #expect(try run(["save-findings", "-"], stdin: ##"{"audited":"supa","findings":[]}"##).err.contains("audited must be a list"))
        #expect(try run(["save-findings", "-"], stdin: ##"{"audited":["supa"],"findings":{}}"##).err.contains("findings must be a list"))
        #expect(try run(["save-findings", "-"], stdin: ##"{"audited":["supa"],"findings":[{"skillName":5}]}"##).err.contains("findings[0].skillName must be text"))
    }

    /// Each rule broken is named with the JSON field's own name, in words Claude can act on.
    @Test func eachRefusalNamesTheRuleAndTheField() throws {
        try scratch()
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("finding 0: skillSays is empty", { $0["skillSays"] = "" }),
            ("finding 0: trueNow is over 2,000 characters", { $0["trueNow"] = String(repeating: "x", count: 2001) }),
            ("finding 0: skillSays holds characters that don't show on screen", { $0["skillSays"] = "a\u{200B}b" }),
            ("finding 0: suggestedText is empty", { $0["suggestedText"] = "" }),
            ("finding 0: file is over 300 characters", { $0["file"] = String(repeating: "d/", count: 160) }),
            ("finding 0: file must stay inside the skill folder: no leading / and no . or .. parts", { $0["file"] = "../x.md" }),
            ("finding 0: skillName isn't a skill name (letters, digits, ., _ and -, starting with a letter or digit)", { $0["skillName"] = "../x" }),
            ("finding 0: alternative isn't a skill name (letters, digits, ., _ and -, starting with a letter or digit)", { $0["alternative"] = "a b" }),
            ("finding 0: severity must be breaks, deprecated, oldVersion or cosmetic", { $0["severity"] = "break" }),
            ("finding 0: source must be an https link", { $0["source"] = "http://example.com" }),
            ("finding 0: keptBySecondCheck must be true: only findings the second look kept are saved", { $0["keptBySecondCheck"] = false }),
            ("finding 0: wrongSince must be undated, written:YYYY-MM-DD, installed:YYYY-MM-DD or since:YYYY-MM-DD", { $0["wrongSince"] = "2026-13-45" }),
        ]
        for (message, change) in cases {
            let refused = try run(["save-findings", "-"], stdin: results(change))
            #expect(refused.status == 1, "\(message)")
            #expect(refused.err == "skill-health: Nothing saved: \(message).\n", "\(message): \(refused.err)")
        }
        let empty = try run(["save-findings", "-"], stdin: ##"{"audited":[],"findings":[]}"##)
        #expect(empty.err == "skill-health: Nothing saved: audited is empty: it must list the skill names checked.\n")
        let missing = try run(["save-findings", "-"], stdin: results(audited: ["other"]))
        #expect(missing.err == "skill-health: Nothing saved: finding 0: skillName supa isn't in audited.\n")
        #expect(!FileManager.default.fileExists(atPath: skillHealth.appending(path: "decisions.json").path(percentEncoded: false)))
    }

    // MARK: 9, 10 and 14. What the commands print and give

    @Test func findingsGiveTheTotalsACommandNeeds() throws {
        try scratch(skills: [("supa", 3), ("other", 0), ("third", 0)],
                    findings: [finding(1), finding(2, severity: "deprecated", says: "a"), finding(3, severity: "oldVersion", says: "b"),
                               finding(4, severity: "cosmetic", says: "c")])
        let named = try json(["findings", "supa", "--json"])
        #expect(named["failing"] as? Int == 1)
        #expect(named["deprecated"] as? Int == 1)
        #expect(named["other"] as? Int == 2)
        #expect(named["skills"] as? Int == 1)
        #expect(named["checkedOn"] as? String == checkedStamp)
        #expect(named["setAsideFailing"] as? Int == 0)
        // A skill that was never checked says so, as null; one that was has its date.
        let never = try json(["findings", "other", "--json"])
        #expect(never["checkedOn"] is NSNull)
        #expect(never["other"] as? Int == 0)
        // Without a skill named, only failing and deprecated are listed.
        let all = try json(["findings", "--json"])
        #expect(all["other"] as? Int == 0)
        #expect(all["skills"] as? Int == 1)
        #expect(all["checkedOn"] == nil)
    }

    @Test func aSkillNeverCheckedIsNotCalledClean() throws {
        try scratch(skills: [("supa", 3), ("other", 0)], findings: [])
        // Installed but not used: /skill-health:check doesn't cover it, so it isn't sent there.
        #expect(try run(["findings", "other"]).out == "other isn't one of the skills you use, so /skill-health:check doesn't cover it.\n")
        let used = ToolReadTests()
        try used.scratch(skills: [("supa", 3), ("vite", 2)], findings: [])
        #expect(try used.run(["findings", "vite"]).out == "vite hasn't been checked yet. Run /skill-health:check vite.\n")
        #expect(try run(["findings", "supa"]).out.hasPrefix("Nothing to fix in supa. It was last checked "))
        #expect(try run(["findings", "nope"]).err.contains("There's no skill called nope"))
    }

    @Test func zeroSkillsUsedIsSaidOnceAndNeverAsAtLeastZero() throws {
        try scratch(skills: [("supa", 0), ("other", 0)], audited: [], sessions: false)
        let status = try run(["status"]).out
        #expect(status.contains("2 skills, none used yet."))
        #expect(status.contains("There are no Claude Code sessions in this folder yet."))
        #expect(!status.contains("at least 0") && !status.contains("0 of"))
        #expect(try run(["plan"]).out == "No skills used in the last 90 days.\n")
        #expect(try run(["findings"]).out == "No skills used in the last 90 days, so there's nothing to fix.\n")
        let plan = try json(["plan", "--json"])
        #expect((plan["skills"] as? [Any])?.isEmpty == true)
        // With sessions kept but no load in them, it is the window that has none.
        let kept = ToolReadTests()
        try kept.scratch(skills: [("supa", 0)], audited: [])
        let keptStatus = try kept.run(["status"]).out
        // Sessions kept for less than 90 days say nothing about before them.
        #expect(keptStatus.contains("1 skill, none used since "))
        #expect(keptStatus.contains("Claude Code has kept sessions only since"))
        #expect(!keptStatus.contains("at least 0") && !keptStatus.contains("0 of"))
    }

    @Test func theUsedPhraseHandlesNoneAndNoSessionsAtAll() {
        let start = Date.now.addingTimeInterval(-90 * 86_400)
        let covered = UsageReport(loads: [:], windowStart: start, completeSince: start.addingTimeInterval(-86_400))
        let partial = UsageReport(loads: [:], windowStart: start, completeSince: .now.addingTimeInterval(-86_400))
        let none = UsageReport(loads: [:], windowStart: start, completeSince: nil)
        #expect(covered.usedPhrase(count: 0) == "none used in the last 90 days")
        #expect(partial.usedPhrase(count: 0) == "none used since \(UsageReport.day(partial.completeSince!))")
        #expect(UsageReport(loads: ["a": 1_200], windowStart: start, completeSince: start.addingTimeInterval(-86_400)).usedPhrase(count: 1_200)
                == "1,200 used in the last 90 days")
        #expect(none.usedPhrase(count: 0) == "none used yet")
        #expect(covered.usedPhrase(count: 4) == "4 used in the last 90 days")
        #expect(partial.usedPhrase(count: 4) == "at least 4 used in the last 90 days")
        #expect(none.usedPhrase(count: 1) == "at least 1 used in the last 90 days")
    }

    @Test func theUncheckedLineSaysAtLeastWhileUsageIsALowerBound() throws {
        try scratch(skills: [("supa", 3), ("other", 2), ("third", 1)], audited: ["supa"])
        // Sessions go back a day here, so 3 used is a lower bound, and so is the 2 not checked.
        let partial = try run(["findings"]).out
        #expect(partial.contains("Nothing to fix. No failing or deprecated instructions in the 1 skill you use that is checked."))
        #expect(partial.contains("At least 2 skills you use haven't been checked yet. Run /skill-health:check."))
        #expect(try run(["status"]).out.contains("1 of at least 3 skills you use checked."))

        let home2 = ToolReadTests()
        try home2.scratch(skills: [("supa", 3), ("other", 2)], audited: ["supa"], coversWindow: true)
        let covered = try home2.run(["findings"]).out
        #expect(covered.contains("1 skill you use hasn't been checked yet. Run /skill-health:check."))
        #expect(!covered.contains("At least"))
        #expect(try home2.run(["status"]).out.contains("1 of 2 skills you use checked."))
    }

    @Test func thePlanSaysHowManyMoreItDoesntListAndHasNoCostLineForNoSkills() throws {
        let many = (1...14).map { (name: "s\($0)", loads: $0) }
        try scratch(skills: many, audited: [])
        let lines = try run(["plan"]).out.split(separator: "\n").map(String.init)
        #expect(lines[0] == "0 of at least 14 skills you use checked. A check costs about 75,000 tokens a skill, more for large ones.")
        #expect(lines.count == 14)   // the summary, 12 skills, and "and 2 more"
        #expect(lines.last == "  and 2 more")
        let one = ToolReadTests()
        try one.scratch(skills: [("a", 1)], audited: [])
        #expect(try one.run(["plan"]).out.split(separator: "\n").last == "  a: loaded once, never checked, about 75,000 tokens")
        #expect(!(try one.run(["plan"]).out.contains("and ")))
    }

    // MARK: 13. A comparison that didn't reach its sources is no all-clear

    func compareFailing(_ repos: [String: String?]) throws {
        var compare = CompareFile()
        compare.checkedAt = .now.addingTimeInterval(-3 * 3600)
        for (repo, problem) in repos {
            var source = CompareFile.Source()
            source.problem = problem
            compare.sources[repo] = source
        }
        try write(compare)
    }

    @Test func aComparisonThatCouldntReachGitHubDoesntSayNothingIsNewer() throws {
        try scratch(skills: [("supa", 3), ("vite", 2)])
        try receipt("supa", repo: "o/a")
        try receipt("vite", repo: "o/b")
        let offline = SkillHealthError.offline("The Internet connection appears to be offline.").plainDescription
        try compareFailing(["o/a": offline, "o/b": offline])
        let list = try run(["update", "list"]).out
        #expect(list.contains("Nothing to update that Skill Health knows of."))
        #expect(!list.contains("None of the skills you use has a newer copy"))
        #expect(list.contains("Skill Health couldn't reach GitHub at the last comparison, so newer copies aren't known."))
        let status = try run(["status"]).out
        #expect(status.contains("Skill Health couldn't reach GitHub at the last comparison, so newer copies aren't known."))
        #expect(try json(["status", "--json"])["comparedProblems"] as? Int == 2)
        let object = try json(["update", "list", "--json"])
        #expect(object["comparedProblems"] as? Int == 2)
        #expect((object["eligible"] as? [Any])?.isEmpty == true)
    }

    @Test func someSourcesFailingIsCountedAndOnlySourcesOfSkillsYouUseCount() throws {
        try scratch(skills: [("supa", 3), ("vite", 2), ("react", 1), ("idle", 0)])
        try receipt("supa", repo: "o/a")
        try receipt("vite", repo: "o/b")
        try receipt("react", repo: "o/c")
        try receipt("idle", repo: "o/unused")
        try compareFailing(["o/a": "o/a isn't on GitHub any more, or it's private.", "o/b": "GitHub couldn't answer for o/b (status 502).",
                            "o/c": nil, "o/unused": "o/unused isn't on GitHub any more, or it's private."])
        let list = try run(["update", "list"]).out
        #expect(list.contains("2 sources couldn't be reached at the last comparison, so newer copies from them aren't known."))
        #expect(try json(["update", "list", "--json"])["comparedProblems"] as? Int == 2)   // o/unused isn't one a skill you use came from
        let one = ToolReadTests()
        try one.scratch(skills: [("supa", 3), ("vite", 2)])
        try one.receipt("supa", repo: "o/a")
        try one.receipt("vite", repo: "o/b")
        try one.compareFailing(["o/a": "o/a isn't on GitHub any more, or it's private.", "o/b": nil])
        #expect(try one.run(["status"]).out.contains("1 source couldn't be reached at the last comparison, so newer copies from it aren't known."))
    }

    /// No skill with a recorded source means nothing was compared: never "none has a newer copy".
    @Test func skillsWithNoRecordedSourceAreNotSaidToHaveNoNewerCopy() throws {
        try scratch(skills: [("supa", 3), ("vite", 2)])
        try compareFailing([:])
        let list = try run(["update", "list"]).out
        #expect(list.contains("None of the skills you use has a recorded source, so Skill Health has nothing to compare."))
        #expect(!list.contains("has a newer copy that's safe"))
    }

    @Test func aComparisonThatReachedEverythingSaysNoneIsNewer() throws {
        try scratch(skills: [("supa", 3)])
        try receipt("supa", repo: "o/a")
        try compareFailing(["o/a": nil])
        let list = try run(["update", "list"]).out
        #expect(list.contains("Nothing to update. None of the 1 skill you use that has a source has a newer copy that's safe to take."))
        #expect(!list.contains("couldn't be reached") && !list.contains("couldn't reach"))
        #expect(try json(["update", "list", "--json"])["comparedProblems"] as? Int == 0)
    }

    @Test func anOfflineProblemBeginsTheWayTheCountExpects() {
        #expect(SkillHealthError.offline("x").plainDescription.hasPrefix(CompareProblems.offlinePrefix))
    }

    @Test func aStoppedComparisonIsNotAnAllClearEither() throws {
        try scratch(skills: [("supa", 3)])
        try receipt("supa", repo: "o/a")
        var compare = CompareFile()
        compare.checkedAt = .now.addingTimeInterval(-600)
        compare.stopped = SkillHealthError.rateLimited(resetAt: nil).plainDescription
        try write(compare)
        let list = try run(["update", "list"]).out
        #expect(list.contains("Nothing to update that Skill Health knows of."))
        #expect(list.contains("GitHub allows 60 requests an hour"))
        #expect((try json(["update", "list", "--json"])["stopped"] as? String)?.contains("60 requests an hour") == true)
        // Hours later the limit has reset, so its reset time isn't repeated as if it were ahead.
        compare.checkedAt = .now.addingTimeInterval(-3 * 3600)
        try write(compare)
        let later = try run(["update", "list"]).out
        #expect(later.contains("The last comparison stopped at GitHub's hourly limit, which has reset since. Run skill-health compare to finish."))
        #expect(!later.contains("It resets"))
    }

    // MARK: 4. Nothing sets a skill aside from updates

    @Test func updateListGivesOnlyReasonsTheToolCanSet() throws {
        try scratch(skills: [("supa", 3)])
        try receipt("supa", repo: "o/a")
        var compare = CompareFile()
        compare.checkedAt = .now
        compare.copies["supa"] = .init(repo: "o/a", subpath: "skills/supa", installedFrom: "c1", head: "c2",
                                       installed: ["SKILL.md": blob("x")], source: nil)
        try write(compare)
        let left = try #require((try json(["update", "list", "--json"])["leftOut"] as? [[String: Any]])?.first)
        #expect(left["reason"] as? String == "removedAtSource")
    }

    // MARK: The command files say what the tool says

    func command(_ name: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: "plugin/skills/\(name)/SKILL.md"), encoding: .utf8)
    }

    @Test func theFixCommandKnowsEveryValueTheToolCanGive() throws {
        let fix = try command("fix")
        for word in ["skillRemoved", "fileRemoved", "expired", "sourceChanged", "lineCameBack", "setAsideFailing", "setAsideDeprecated",
                     "checkedOn", "`other`", "`skills`", "`problem`", "Its source no longer has this skill.", "Its source no longer has this file."] {
            #expect(fix.contains(word), "fix/SKILL.md doesn't mention \(word)")
        }
        // The old value, and a sentence that is untrue for a set-aside "until update".
        #expect(!fix.contains("`removed`"))
        #expect(!fix.contains("that has passed"))
        #expect(fix.contains("never say \"Nothing to fix\""))
    }

    @Test func theUpdateCommandQuotesWhatThePreviewPrintsAndKnowsComparisonsFail() throws {
        let update = try command("update")
        #expect(!update.contains("keptAsItIs") && !update.contains("kept as it is"))
        #expect(update.contains("comparedProblems"))
        let source = try String(contentsOf: Self.root.appending(path: "Sources/skill-health/Updating.swift"), encoding: .utf8)
        // The one sentence the preview prints about lines it didn't show, said the way it is printed.
        #expect(source.contains("more changed line"))
        #expect(source.contains("shown here; each file's full new copy is in"))
        #expect(update.contains("more changed lines aren't shown here; each file's full new copy is in"))
        #expect(!update.contains("more lines in"))
    }

    @Test func theCheckCommandSaysWhatToDoWhenThereIsNoSkillsFolderAndForOneSkill() throws {
        let check = try command("check")
        #expect(!check.contains("hasn't read your skills yet"))
        #expect(check.contains("Claude Code keeps skills in ~/.claude/skills; Skill Health looks there."))
        #expect(check.contains("To check one anyway, run /skill-health:check <skill>."))
        #expect(!check.contains("Run it again to re-check the oldest."))
        #expect(check.contains("The skill you use isn't checked yet."))
        // Which the tool says when there is nothing at ~/.claude/skills.
        let bare = ToolReadTests()
        let refused = try bare.run(["plan"])
        #expect(refused.status == 1)
        #expect(refused.err.contains("There's no skills folder at"))
    }
}
