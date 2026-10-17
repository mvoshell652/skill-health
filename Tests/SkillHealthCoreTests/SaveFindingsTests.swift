import Foundation
import Testing
@testable import SkillHealthCore

/// Runs the plugin's real save script, plugin/scripts/save-findings.sh, and reads what it wrote
/// with the app's own types: the two sides of findings.json can't drift apart unnoticed.
@Suite("The audit's save script")
struct SaveFindingsTests {
    static let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "plugin/scripts/save-findings.sh")
    let skillHealth = URL.temporaryDirectory.appending(path: "skill-health-save-\(UUID().uuidString)/skill-health")

    let supabase = #"{"skillName":"supabase","severity":"breaks","skillSays":"npm install -g supabase","trueNow":"The Supabase CLI refuses global installs.","source":"https://github.com/supabase/cli/issues/4496","wrongSince":"written:2026-02-18","suggestedText":"npx supabase --help","keptBySecondCheck":true}"#

    @discardableResult
    func save(_ json: String) throws -> (status: Int32, output: String) {
        try FileManager.default.createDirectory(at: skillHealth, withIntermediateDirectories: true)
        let input = skillHealth.deletingLastPathComponent().appending(path: "results-\(UUID().uuidString).json")
        try json.write(to: input, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [Self.script.path(percentEncoded: false), input.path(percentEncoded: false)]
        process.environment = ["SKILL_HEALTH_DIR": skillHealth.path(percentEncoded: false), "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func saved() throws -> FindingsFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FindingsFile.self, from: Data(contentsOf: skillHealth.appending(path: "findings.json")))
    }

    static let hiddenCases = [
        "plain", "warn \u{26A0}\u{FE0F} ok", "cjk \u{845B}\u{E0100}", "crlf\r\nok", "tab\tok", "👍🏽 thumbs",
        "smuggled\u{E0100}\u{E0101}", "\u{FE0F}first", "space \u{FE0F}", "run a\u{FE0F}\u{FE0F}",
        "soft\u{00AD}hyphen", "esc\u{1B}[2K", "nul\u{0}", "lone\rcr", "del\u{7F}", "c1\u{85}", "hangul\u{3164}",
        "braille\u{2800}", "cgj\u{034F}", "zwsp\u{200B}", "zwj\u{200D}", "rlo\u{202E}", "bom\u{FEFF}", "tag\u{E0041}",
        "arabic mark\u{061C}", "mongolian\u{180E}", "interlinear\u{FFF9}",
    ]

    /// The script's `hidden` and HiddenText are one rule written twice: each string is refused by
    /// both or by neither.
    @Test(arguments: hiddenCases)
    func theScriptAndTheAppAgreeOnHiddenCharacters(text: String) throws {
        var finding = try #require(try JSONSerialization.jsonObject(with: Data(supabase.utf8)) as? [String: Any])
        finding["skillSays"] = text
        let body = try JSONSerialization.data(withJSONObject: ["audited": ["supabase"], "findings": [finding]])
        let result = try save(String(decoding: body, as: UTF8.self))
        #expect((result.status != 0) == HiddenText.contains(text), "\(text.unicodeScalars.map { String($0.value, radix: 16) }): \(result.output)")
    }

    @Test func savesWhatTheAppReads() throws {
        let result = try save(#"{"audited":["supabase","vite"],"findings":[\#(supabase)]}"#)
        #expect(result.status == 0, "\(result.output)")
        let file = try saved()
        #expect(file.findings.count == 1)
        let finding = try #require(file.findings.first)
        #expect(finding.status == .open)
        #expect(finding.suggestedText == "npx supabase --help")
        #expect(finding.keptBySecondCheck == true)
        if case .written = finding.wrongSince {} else { Issue.record("expected written") }
        #expect(Set(file.audited.keys) == ["supabase", "vite"])
    }

    /// The script and the app both write an install day as `installed`, the day only, midnight UTC.
    @Test func anInstallDayIsSavedAsAnInstallDay() async throws {
        let installed = supabase.replacing("written:2026-02-18", with: "installed:2026-06-01")
        let result = try save(#"{"audited":["supabase"],"findings":[\#(installed)]}"#)
        #expect(result.status == 0, "\(result.output)")
        let day = try Date("2026-06-01T00:00:00Z", strategy: .iso8601)
        #expect(try saved().findings.first?.wrongSince == .installed(on: day))

        let engine = Engine(paths: SkillHealthPaths(claudeHome: skillHealth.deletingLastPathComponent().appending(path: "claude")))
        try FileManager.default.createDirectory(at: engine.paths.home, withIntermediateDirectories: true)
        try await engine.save(AuditResults(audited: ["supabase"], findings: [
            .init(skillName: "supabase", severity: .breaks, skillSays: "npm install -g supabase", trueNow: "Refused.",
                  source: URL(string: "https://github.com/supabase/cli/issues/4496")!, wrongSince: "installed:2026-06-01")]))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let byApp = try decoder.decode(FindingsFile.self, from: Data(contentsOf: engine.paths.findings))
        #expect(byApp.findings.first?.wrongSince == .installed(on: day))
    }

    @Test func theSameWrongLineKeepsItsIdAcrossAudits() throws {
        try save(#"{"audited":["supabase"],"findings":[\#(supabase)]}"#)
        let first = try saved().findings[0].id
        try save(#"{"audited":["supabase"],"findings":[\#(supabase)]}"#)
        #expect(try saved().findings.map(\.id) == [first])
    }

    @Test func anAuditReplacesOnlyTheSkillsItCovered() throws {
        let vite = supabase.replacing(#""skillName":"supabase""#, with: #""skillName":"vite""#)
        try save(#"{"audited":["supabase","vite"],"findings":[\#(supabase),\#(vite)]}"#)
        // Re-audit vite only, which is now clean: supabase's finding stays, vite's goes.
        try save(#"{"audited":["vite"],"findings":[]}"#)
        #expect(try saved().findings.map(\.skillName) == ["supabase"])
    }

    @Test func refusesAnythingMalformedAndWritesNothing() throws {
        let cases = [
            #"{"audited":["supabase"],"findings":[\#(supabase.replacing("\"breaks\"", with: "\"break\""))]}"#,
            #"{"audited":["supabase"],"findings":[\#(supabase.replacing("https://github.com", with: "http://github.com"))]}"#,
            #"{"audited":["supabase"],"findings":[\#(supabase.replacing("\"keptBySecondCheck\":true", with: "\"keptBySecondCheck\":false"))]}"#,
            #"{"audited":["supa"],"findings":[\#(supabase)]}"#,
            #"{"audited":["supabase"],"findings":[\#(supabase.replacing("\"suggestedText\"", with: "\"file\":\"../../escape.md\",\"suggestedText\""))]}"#,
            #"{"audited":["../x"],"findings":[]}"#,
            #"not json"#,
        ]
        for json in cases {
            let result = try save(json)
            #expect(result.status != 0, "accepted: \(json)")
            #expect(!FileManager.default.fileExists(atPath: skillHealth.appending(path: "findings.json").path(percentEncoded: false)))
        }
    }

    @Test func aFindingsFileItCantReadIsLeftAlone() throws {
        try FileManager.default.createDirectory(at: skillHealth, withIntermediateDirectories: true)
        try "{garbage".write(to: skillHealth.appending(path: "findings.json"), atomically: true, encoding: .utf8)
        let result = try save(#"{"audited":["supabase"],"findings":[\#(supabase)]}"#)
        #expect(result.status != 0)
        #expect(try String(contentsOf: skillHealth.appending(path: "findings.json"), encoding: .utf8) == "{garbage")
    }
}

extension SaveFindingsTests {
    @Test func readsResultsFromStandardInputSoTheAuditWritesNoFileItself() throws {
        try FileManager.default.createDirectory(at: skillHealth, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [Self.script.path(percentEncoded: false), "-"]
        process.environment = ["SKILL_HEALTH_DIR": skillHealth.path(percentEncoded: false), "PATH": "/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"audited":["supabase"],"findings":[\#(supabase)]}"#.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try saved().findings.count == 1)
        // Nothing left behind but findings.json.
        #expect(try FileManager.default.contentsOfDirectory(atPath: skillHealth.path(percentEncoded: false)) == ["findings.json"])
    }
}

@Suite("The audit plan the app writes for /skill-health:audit")
struct AuditPlanFileTests {
    @Test func mostUsedNeverAuditedIsTheTopSixByLoads() throws {
        let root = URL.temporaryDirectory.appending(path: "skill-health-plan-\(UUID().uuidString)")
        var skills: [Skill] = []
        for (index, loads) in [3, 50, 0, 9, 7, 12, 1, 20, 5].enumerated() {
            let folder = root.appending(path: "skills/s\(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try String(repeating: "x", count: 100 * (index + 1)).write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
            skills.append(Skill(name: "s\(index)", folder: folder, usesLast90Days: loads))
        }
        let plan = AuditPlanFile.make(skills: skills, audited: ["s1": .now], skillsFolder: root.appending(path: "skills"))
        #expect(plan.used.map(\.name) == ["s1", "s7", "s5", "s3", "s4", "s8", "s0", "s6"])   // unused s2 left out
        #expect(plan.mostUsedNeverAudited == ["s7", "s5", "s3", "s4", "s8", "s0"])             // s1 is audited
        #expect(plan.used.first?.bytes == 200)
        #expect(plan.tokensPerSkill == 180_000)
    }
}

extension SaveFindingsTests {
    /// The app and the plugin's script must derive the same id for the same wrong line.
    @Test func theAppDerivesTheSameIdAsTheSaveScript() throws {
        let quotes = ["npm install -g supabase", "a \"quoted\" line\nwith a newline and a \\ backslash", "naïve – ünïcode / slash\ttab"]
        for (index, quote) in quotes.enumerated() {
            let json = #"{"audited":["s\#(index)"],"findings":[{"skillName":"s\#(index)","severity":"breaks","skillSays":\#(String(data: try JSONEncoder().encode(quote), encoding: .utf8)!),"trueNow":"t","source":"https://example.com/x","keptBySecondCheck":true}]}"#
            let result = try save(json)
            #expect(result.status == 0, "\(result.output)")
            let saved = try saved().findings.first { $0.skillName == "s\(index)" }
            #expect(saved?.id == FindingID.make(skill: "s\(index)", file: "SKILL.md", quote: quote), "quote \(index)")
        }
    }
}

extension SaveFindingsTests {
    /// An audit saved by the app and the same audit saved by the plugin's script give the same file.
    @Test func theAppSavesExactlyWhatTheScriptSaves() async throws {
        try save(#"{"audited":["supabase","vite"],"findings":[\#(supabase)]}"#)
        let byScript = try saved()
        try FileManager.default.removeItem(at: skillHealth.appending(path: "findings.json"))
        let engine = Engine(paths: SkillHealthPaths(claudeHome: skillHealth.deletingLastPathComponent().appending(path: "claude")))
        try FileManager.default.createDirectory(at: engine.paths.home, withIntermediateDirectories: true)
        try await engine.save(AuditResults(audited: ["supabase", "vite"], findings: [
            .init(skillName: "supabase", severity: .breaks, skillSays: "npm install -g supabase",
                  trueNow: "The Supabase CLI refuses global installs.", source: URL(string: "https://github.com/supabase/cli/issues/4496")!,
                  wrongSince: "written:2026-02-18", suggestedText: "npx supabase --help")]))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let byApp = try decoder.decode(FindingsFile.self, from: Data(contentsOf: engine.paths.findings))
        #expect(byApp.findings.map(\.id) == byScript.findings.map(\.id))
        #expect(byApp.findings.map(\.skillSays) == byScript.findings.map(\.skillSays))
        #expect(Set(byApp.audited.keys) == Set(byScript.audited.keys))
        await #expect(throws: SkillHealthError.auditRejected("finding 0: source must be an https link")) {
            try await engine.save(AuditResults(audited: ["x"], findings: [
                .init(skillName: "x", severity: .breaks, skillSays: "a", trueNow: "b", source: URL(string: "http://example.com")!)]))
        }
    }
}

extension SaveFindingsTests {
    /// The one finding the cases below break one rule of.
    var base: [String: Any] {
        ["skillName": "supabase", "severity": "breaks", "skillSays": "npm install -g supabase", "trueNow": "Refused.",
         "source": "https://github.com/supabase/cli/issues/4496", "keptBySecondCheck": true]
    }

    static func kept(from item: [String: Any]) -> AuditResults.Kept? {
        guard let severity = (item["severity"] as? String).flatMap(Severity.init(rawValue:)),
              let source = (item["source"] as? String).flatMap(URL.init(string:)) else { return nil }
        return .init(skillName: item["skillName"] as? String ?? "", severity: severity, skillSays: item["skillSays"] as? String ?? "",
                     trueNow: item["trueNow"] as? String ?? "", source: source, wrongSince: item["wrongSince"] as? String,
                     file: item["file"] as? String, suggestedText: item["suggestedText"] as? String, alternative: item["alternative"] as? String)
    }

    /// A refusal names the rule broken and keeps the JSON field's name, in the same words whether
    /// the script or the app says it.
    @Test func theScriptAndTheAppRefuseInTheSameWords() throws {
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("skillSays is empty", { $0["skillSays"] = "" }),
            ("trueNow is over 2,000 characters", { $0["trueNow"] = String(repeating: "x", count: 2001) }),
            ("skillSays holds characters that don't show on screen", { $0["skillSays"] = "a\u{200B}b" }),
            ("suggestedText is empty", { $0["suggestedText"] = "" }),
            ("file is over 300 characters", { $0["file"] = String(repeating: "d/", count: 160) }),
            ("file must stay inside the skill folder: no leading / and no . or .. parts", { $0["file"] = "/etc/x" }),
            ("skillName isn't a skill name (letters, digits, ., _ and -, starting with a letter or digit)", { $0["skillName"] = "../x" }),
            ("alternative isn't a skill name (letters, digits, ., _ and -, starting with a letter or digit)", { $0["alternative"] = "a b" }),
            ("source must be an https link", { $0["source"] = "http://example.com" }),
            ("wrongSince must be undated, written:YYYY-MM-DD, installed:YYYY-MM-DD or since:YYYY-MM-DD", { $0["wrongSince"] = "2026-02-30" }),
            ("wrongSince must be undated, written:YYYY-MM-DD, installed:YYYY-MM-DD or since:YYYY-MM-DD", { $0["wrongSince"] = "installed:2026-02-30" }),
            ("wrongSince must be undated, written:YYYY-MM-DD, installed:YYYY-MM-DD or since:YYYY-MM-DD", { $0["wrongSince"] = "installed:" }),
            ("skillName other isn't in audited", { $0["skillName"] = "other" }),
            (AuditResults.severityRule, { $0["severity"] = "break" }),
            (AuditResults.keptRule, { $0["keptBySecondCheck"] = false }),
        ]
        for (message, change) in cases {
            var item = base
            change(&item)
            let body = try JSONSerialization.data(withJSONObject: ["audited": ["supabase"], "findings": [item]])
            let result = try save(String(decoding: body, as: UTF8.self))
            #expect(result.status != 0, "\(message)")
            #expect(result.output.contains("skill-health: nothing saved: finding 0: \(message)\n"), "\(message): \(result.output)")
            // Whether a finding was kept by the second look is the tool's to say, not AuditResults'.
            if message != AuditResults.keptRule, let kept = Self.kept(from: item) {
                #expect(AuditResults(audited: ["supabase"], findings: [kept]).problem == "finding 0: \(message)", "\(message)")
            }
        }
        #expect(AuditResults(audited: [], findings: []).problem == "audited is empty: it must list the skill names checked")
        #expect(try save(#"{"audited":[],"findings":[]}"#).output.contains("nothing saved: audited is empty: it must list the skill names checked\n"))
        let name = "isn't a skill name (letters, digits, ., _ and -, starting with a letter or digit)"
        #expect(AuditResults(audited: ["../x"], findings: []).problem == "audited has a name that \(name)")
        #expect(try save(#"{"audited":["../x"],"findings":[]}"#).output.contains("nothing saved: audited has a name that \(name)\n"))
        #expect(try save("[]").output.contains("nothing saved: the results must be a JSON object with audited and findings\n"))
        #expect(try save("7").output.contains("nothing saved: the results must be a JSON object with audited and findings\n"))
    }

    @Test func theScriptCountsWhatItSavedAfterDeduplication() throws {
        let result = try save(#"{"audited":["supabase","supabase"],"findings":[\#(supabase),\#(supabase)]}"#)
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("saved 1 finding(s) for 1 audited skill(s)"))
        #expect(try saved().findings.count == 1)
    }

    /// The tool saves one skill's results through the app's own save, and the script keeps other
    /// skills' entries it can't read as raw JSON; the app's save can't, so it refuses instead.
    @Test func theAppsSaveRefusesWhileEntriesItCouldntReadWouldBeLost() async throws {
        let claude = skillHealth.deletingLastPathComponent().appending(path: "claude")
        let engine = Engine(paths: SkillHealthPaths(claudeHome: claude))
        try FileManager.default.createDirectory(at: engine.paths.home, withIntermediateDirectories: true)
        let before = #"{"version":1,"audited":{"vite":"2026-10-01T00:00:00Z"},"findings":[{"id":"nope"}]}"#
        try before.write(to: engine.paths.findings, atomically: true, encoding: .utf8)
        let results = AuditResults(audited: ["supabase"], findings: [])
        await #expect(throws: SkillHealthError.auditRejected(AuditResults.unreadableEntriesProblem(1))) { try await engine.save(results) }
        #expect(try String(contentsOf: engine.paths.findings, encoding: .utf8) == before)
        #expect(AuditResults.unreadableEntriesProblem(1) == "1 instruction in the results of earlier checks couldn't be read, and saving would lose it. Move ~/.claude/skill-health/findings.json aside, then run /skill-health:check again")
        #expect(AuditResults.unreadableEntriesProblem(3).hasPrefix("3 instructions in the results of earlier checks couldn't be read, and saving would lose them."))
        #expect(AuditResults(audited: ["a", "a", "b"], findings: []).savedCounts.skills == 2)
    }
}
