import Foundation
import Testing
@testable import SkillHealthCore

/// One of the plugin's skills, read from its SKILL.md: the frontmatter fields and the body.
struct PluginSkill {
    let directory: String
    let fields: [String: String]
    let body: String

    var allowedTools: String { fields["allowed-tools"] ?? "" }

    /// allowed-tools split on spaces outside parentheses, so "Bash(tool plan *)" stays one rule.
    var allowedRules: [String] {
        var rules: [String] = [], current = "", depth = 0
        for character in allowedTools {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character == " " && depth == 0 {
                if !current.isEmpty { rules.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { rules.append(current) }
        return rules
    }

    static func load(_ directory: String) throws -> PluginSkill {
        let text = try String(contentsOf: PluginFiles.skills.appending(path: "\(directory)/SKILL.md"), encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let end = try #require(lines.dropFirst().firstIndex(of: "---"), "\(directory): no end to the frontmatter")
        #expect(lines.first == "---", "\(directory): doesn't start with frontmatter")
        var fields: [String: String] = [:]
        var key: String?
        for line in lines[1..<end] {
            // A YAML list under a key: fold its items into one space-separated value.
            if let current = key, line.hasPrefix(" ") || line.hasPrefix("\t") {
                var item = line.trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("- ") { item.removeFirst(2) }
                fields[current, default: ""] += " " + item
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
            key = String(line[..<colon])
            fields[key!] = value
        }
        return PluginSkill(directory: directory, fields: fields, body: lines[(end + 1)...].joined(separator: "\n"))
    }

    static func all() throws -> [PluginSkill] {
        try FileManager.default.contentsOfDirectory(atPath: PluginFiles.skills.plainPath).filter { !$0.hasPrefix(".") }.sorted().map(load)
    }
}

@Suite("The plugin's manifest, hooks and skills")
struct PluginManifestTests {
    static let tool = "${CLAUDE_PLUGIN_ROOT}/bin/skill-health"

    func json(_ relative: String) throws -> [String: Any] {
        let data = try Data(contentsOf: PluginFiles.repo.appending(path: relative))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: plugin.json

    /// Any other key in a userConfig option makes Claude Code refuse to load the whole plugin.
    static let allowedOptionKeys: Set<String> = ["type", "title", "description", "required", "default", "options", "multiple", "sensitive", "min", "max"]

    @Test func theTwoOptionsUseOnlyKeysClaudeCodeAccepts() throws {
        let manifest = try json("plugin/.claude-plugin/plugin.json")
        let options = try #require(manifest["userConfig"] as? [String: [String: Any]])
        #expect(Set(options.keys) == ["session_note", "corrections_for_claude"])
        for (name, option) in options {
            #expect(Set(option.keys).isSubset(of: Self.allowedOptionKeys), "\(name): \(Set(option.keys).subtracting(Self.allowedOptionKeys))")
            #expect(option["type"] as? String == "boolean", "\(name)")
            #expect(option["default"] as? Bool == true, "\(name)")
            #expect((option["title"] as? String)?.isEmpty == false, "\(name)")
            #expect((option["description"] as? String)?.isEmpty == false, "\(name)")
        }
        #expect(options["session_note"]?["title"] as? String == "Session note")
        #expect(options["corrections_for_claude"]?["title"] as? String == "Corrections for Claude")
    }

    @Test func theManifestIsVersionedForTheCommandsTheMenuOpens() throws {
        let manifest = try json("plugin/.claude-plugin/plugin.json")
        #expect(manifest["name"] as? String == "skill-health")
        let version = try #require(manifest["version"] as? String)
        #expect(version == "0.6.1")
        #expect(PluginHandshake(version: version, readAt: .now).isAtLeastMinimum)
        // One version for the plugin, its tool and the app, so there is one story to tell.
        let versionEnv = try String(contentsOf: PluginFiles.repo.appending(path: "version.env"), encoding: .utf8)
        #expect(versionEnv.contains("MARKETING_VERSION=\(version)\n"), "version.env says something else")
        let tool = try String(contentsOf: PluginFiles.repo.appending(path: "Sources/skill-health/Tool.swift"), encoding: .utf8)
        #expect(tool.contains("static let version = \"\(version)\""), "the tool's own version says something else")
        #expect(manifest["homepage"] as? String == "https://github.com/mvoshell652/skill-health")
        #expect(manifest["repository"] as? String == "https://github.com/mvoshell652/skill-health")
        #expect(manifest["license"] as? String == "Apache-2.0")
        let description = try #require(manifest["description"] as? String)
        #expect(description.contains("jq"))
        #expect(description.contains("macOS"))
    }

    @Test func theMarketplaceOffersThePluginFromItsFolder() throws {
        let marketplace = try json(".claude-plugin/marketplace.json")
        let plugins = try #require(marketplace["plugins"] as? [[String: Any]])
        #expect(plugins.count == 1)
        #expect(plugins.first?["name"] as? String == "skill-health")
        #expect(plugins.first?["source"] as? String == "./plugin")
        #expect((plugins.first?["description"] as? String)?.contains("no longer true") == false)
        #expect((plugins.first?["description"] as? String)?.contains("fixes") == true)
    }

    // MARK: hooks.json

    @Test func theHooksAreTheNoteAndTheGate() throws {
        let hooks = try #require(try json("plugin/hooks/hooks.json")["hooks"] as? [String: [[String: Any]]])
        #expect(Set(hooks.keys) == ["SessionStart", "PreToolUse"])
        func command(_ event: String) throws -> (matcher: String?, command: String, timeout: Int) {
            let group = try #require(hooks[event]?.first)
            let entry = try #require((group["hooks"] as? [[String: Any]])?.first)
            return (group["matcher"] as? String, try #require(entry["command"] as? String), try #require(entry["timeout"] as? Int))
        }
        let start = try command("SessionStart")
        #expect(start.command == #"sh "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh""#)
        let gate = try command("PreToolUse")
        #expect(gate.matcher == "Bash")
        #expect(gate.command == #"sh "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh""#)
        #expect(gate.timeout <= 10)
        for script in ["gate.sh", "session-start.sh", "save-findings.sh"] {
            #expect(FileManager.default.fileExists(atPath: PluginFiles.plugin.appending(path: "scripts/\(script)").plainPath), "\(script)")
        }
    }

    // MARK: skills

    @Test func theSkillsAreCheckFixStatusUpdateUndoAndTheOldAuditAlias() throws {
        let skills = try PluginSkill.all()
        #expect(skills.map(\.directory) == ["audit", "check", "fix", "status", "undo", "update"])
        for skill in skills {
            #expect(skill.fields["name"] == skill.directory)
            #expect(skill.fields["disable-model-invocation"] == "true", "\(skill.directory): only the person runs it")
            #expect((skill.fields["description"] ?? "").count > 20, "\(skill.directory): description")
        }
    }

    @Test func noSkillPreApprovesAnApply() throws {
        for skill in try PluginSkill.all() {
            #expect(!skill.allowedTools.lowercased().contains("apply"), "\(skill.directory): \(skill.allowedTools)")
        }
    }

    /// What a skill may pre-approve: commands that read, or that write only Skill Health's own notes.
    static let preApprovable: Set<String> = ["status", "findings", "fix preview", "decide", "issue", "undo list", "undo preview",
                                             "update list", "update preview", "compare", "plan", "save-findings", "version"]

    @Test func skillsPreApproveOnlyReadOnlyToolCommands() throws {
        for skill in try PluginSkill.all() {
            for rule in skill.allowedRules where rule.hasPrefix("Bash(") {
                let prefix = "Bash(\(Self.tool) "
                #expect(rule.hasPrefix(prefix) && rule.hasSuffix(" *)"), "\(skill.directory): \(rule)")
                guard rule.hasPrefix(prefix), rule.hasSuffix(" *)") else { continue }
                let command = String(rule.dropFirst(prefix.count).dropLast(3))
                #expect(Self.preApprovable.contains(command), "\(skill.directory): \(rule)")
            }
            // Anything else a skill pre-approves is a plain read, never a shell.
            for rule in skill.allowedRules where !rule.hasPrefix("Bash(") {
                #expect(["Read", "Glob", "Grep"].contains(rule), "\(skill.directory): \(rule)")
            }
        }
    }

    /// /skill-health:status is the one command that only looks: two reads, no write, no network, no plan.
    @Test func theStatusSkillCanOnlyRunItsTwoReads() throws {
        let skill = try PluginSkill.load("status")
        #expect(skill.allowedRules == ["Bash(\(Self.tool) status *)", "Bash(\(Self.tool) update list *)"])
        for command in ["decide", "save-findings", "refresh", "compare", "plan", "fix", "undo", "issue"] {
            #expect(!skill.body.contains("\(Self.tool) \(command)"), "\(command)")
        }
        for word in ["no tokens", "No tokens", "changes nothing"] {
            #expect(!(skill.fields["description"] ?? "").contains(word) && !skill.body.contains(word), "\(word)")
        }
    }

    @Test func theBinaryRecordsTheToolchainThatBuiltIt() throws {
        let recorded = try String(contentsOf: PluginFiles.plugin.appending(path: "bin/BUILT_WITH"), encoding: .utf8)
        let lines = recorded.split(separator: "\n")
        #expect(lines.count == 3, "\(recorded)")
        #expect(lines.contains { $0.hasPrefix("Xcode ") } && lines.contains { $0.contains("Swift") } && lines.contains { $0.hasPrefix("SDK ") })
    }

    /// Wherever Skill Health says what it sends GitHub, it says the install dates too: "only the names of the
    /// repositories" was once the wording, in the words a person agrees to and in the spec, while the code also
    /// sends when each skill was installed.
    @Test func everyLineThatSaysWhatIsSentToGitHubMentionsTheInstallDates() throws {
        var files = ["README.md", "SECURITY.md", "CONTRIBUTING.md"]
        for folder in ["docs", "docs/app-store"] {
            let url = PluginFiles.repo.appending(path: folder)
            files += try FileManager.default.contentsOfDirectory(atPath: url.plainPath).filter { $0.hasSuffix(".md") }.map { "\(folder)/\($0)" }
        }
        for skill in try PluginSkill.all() { files.append("plugin/skills/\(skill.directory)/SKILL.md") }
        let sentence = try NSRegularExpression(pattern: #"(?i)only the names|names of (the |your |their )?(public )?(skills' )?repositories|skills' repositories"#)
        var checked = 0
        for file in files {
            let text = try String(contentsOf: PluginFiles.repo.appending(path: file), encoding: .utf8)
            for line in text.split(separator: "\n") where sentence.firstMatch(in: String(line), range: NSRange(line.startIndex..., in: line)) != nil {
                checked += 1
                #expect(line.lowercased().contains("install"), "\(file): \(line.prefix(160))")
            }
        }
        #expect(checked >= 8, "the sentence wasn't found where it should be")
    }

    @Test func skillsNameOnlyCommandsTheToolHas() throws {
        let known: [String: Set<String>] = ["version": [], "status": [], "findings": [], "decide": [], "issue": [], "compare": [], "plan": [],
                                            "save-findings": [], "fix": ["preview", "apply"], "update": ["list", "preview", "apply"],
                                            "undo": ["list", "preview", "apply"]]
        let mention = try NSRegularExpression(pattern: #"\$\{CLAUDE_PLUGIN_ROOT\}/bin/skill-health ([a-z-]+)(?: ([a-z]+))?"#)
        for skill in try PluginSkill.all() {
            let text = skill.fields.values.joined(separator: "\n") + "\n" + skill.body
            for match in mention.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let command = String(text[Range(match.range(at: 1), in: text)!])
                let subcommands = try #require(known[command], "\(skill.directory): Skill Health \(command)")
                if !subcommands.isEmpty {
                    let sub = Range(match.range(at: 2), in: text).map { String(text[$0]) }
                    #expect(sub.map(subcommands.contains) == true, "\(skill.directory): Skill Health \(command) \(sub ?? "")")
                }
            }
        }
    }

    @Test func eachSkillAppliesOnlyItsOwnKind() throws {
        for skill in try PluginSkill.all() {
            for kind in ["fix", "update", "undo"] {
                let applies = skill.body.contains("\(Self.tool) \(kind) apply")
                #expect(applies == (skill.directory == kind), "\(skill.directory) \(kind) apply")
            }
        }
    }

    @Test func theThreeSkillsThatWriteStateTheRulesTheGateReliesOn() throws {
        for directory in ["fix", "update", "undo"] {
            let skill = try PluginSkill.load(directory)
            for phrase in ["AskUserQuestion", "verbatim", "Never edit, write or delete", "Esc", "Claude Code will ask", "alone", "refus"] {
                #expect(skill.body.contains(phrase), "\(directory): \(phrase)")
            }
        }
    }

    @Test func theCheckSkillKeepsItsTwoQuestionsAndTheSecondLook() throws {
        let skill = try PluginSkill.load("check")
        #expect(skill.fields["argument-hint"] == "[skill name]")
        for phrase in ["AskUserQuestion", "skill-health:auditor", "skill-health:second-check", "\(Self.tool) plan --json", "\(Self.tool) save-findings -",
                       "Check N Skills", "Nothing ran. /skill-health:check asks again any time.", "second look", "was not checked"] {
            #expect(skill.body.contains(phrase), "\(phrase)")
        }
        #expect(!skill.body.contains("audit-plan.json"))
    }

    @Test func nothingNamesTheOldAuditCommandOrItsScript() throws {
        for skill in try PluginSkill.all() where skill.directory != "audit" {
            #expect(!skill.body.contains("save-findings.sh"), "\(skill.directory)")
            #expect(!skill.body.contains("audit-plan.json"), "\(skill.directory)")
            #expect(!skill.body.contains("/skill-health:audit"), "\(skill.directory)")
        }
        for folder in ["agents", "evals"] {
            let enumerator = try #require(FileManager.default.enumerator(at: PluginFiles.plugin.appending(path: folder), includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where !file.hasDirectoryPath {
                let text = try String(contentsOf: file, encoding: .utf8)
                #expect(!text.contains("/skill-health:audit"), "\(file.lastPathComponent)")
            }
        }
    }

    /// The check's agents do nearly all of its reading, so they name their model: without one, an
    /// agent runs on the session's model, which may be Opus. `sonnet` is Claude Code's alias for the
    /// newest Sonnet, so a new Sonnet needs no plugin release. The skills name none on purpose: a
    /// skill's model switches the whole turn, which re-reads the conversation without the cache.
    @Test func theChecksAgentsRunOnTheNewestSonnetAndTheSkillsKeepThePersonsModel() throws {
        for name in ["auditor", "second-check"] {
            let text = try String(contentsOf: PluginFiles.plugin.appending(path: "agents/\(name).md"), encoding: .utf8)
            let frontmatter = text.components(separatedBy: "\n---\n").first ?? ""
            #expect(frontmatter.components(separatedBy: "\n").contains("model: sonnet"), "\(name)")
        }
        for skill in try PluginSkill.all() {
            #expect(skill.fields["model"] == nil, "\(skill.directory)")
        }
    }

    /// The auditor is given the day a skill was installed, not the day it was written. An install day once
    /// went out as "wrong since it was written", so it is dated as installed and `written:` is not offered.
    @Test func theAuditorDatesFromTheInstallDayAsInstalledNeverAsWritten() throws {
        let text = try String(contentsOf: PluginFiles.plugin.appending(path: "agents/auditor.md"), encoding: .utf8)
        #expect(text.contains("`installed:YYYY-MM-DD`"))
        #expect(text.contains("Never `written:`"))
        #expect(!text.contains("install or commit date"))
    }

    /// An install day is one person's, so the shared list holds written, since and undated dates only.
    @Test func theSharedListCarriesNoInstallDay() throws {
        let text = try String(contentsOf: PluginFiles.plugin.appending(path: "data/corrections.json"), encoding: .utf8)
        #expect(!text.contains(#""installed:"#))
    }

    @Test func theAuditAliasOnlyPointsAtCheck() throws {
        let skill = try PluginSkill.load("audit")
        #expect(skill.allowedTools.isEmpty)
        #expect(skill.body.contains("Renamed. Run /skill-health:check."))
        #expect(!skill.body.contains("\(Self.tool)"))
        #expect(skill.fields["description"]?.contains("/skill-health:check") == true)
    }
}
