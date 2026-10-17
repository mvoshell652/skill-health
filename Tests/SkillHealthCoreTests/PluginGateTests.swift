import Foundation
import Testing

/// Runs the plugin's real write gate, plugin/scripts/gate.sh, the way Claude Code does: `sh` with the
/// PreToolUse hook's JSON on standard input. The gate is what makes the person's approval prompt show
/// the change, and refuses every case where an approval would mean nothing.
///
/// It recognises one spelling of an apply and treats any other spelling that names a plan that exists
/// as a mistake to correct. A command that names no such plan gets no opinion, however much it
/// sounds like an apply.
@Suite("The plugin's write gate")
struct PluginGateTests {
    let root = URL.temporaryDirectory.appending(path: "skill-health-gate-\(UUID().uuidString)")
    var skillHealth: URL { root.appending(path: "skill-health") }
    let plan = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
    let summary = "Change to ~/.claude/skills/supabase/SKILL.md\n- npm install -g supabase\n+ npx supabase --help"

    static let bypassReason = "Skill Health doesn't write a skill while permission prompts are skipped. Switch to a mode that asks (Shift+Tab), then run the command again."
    static let notReadyReason = "That change isn't ready any more. Run the preview again."
    static let notOurToolReason = "That isn't Skill Health's own tool. Run the apply command exactly as the preview printed it."

    struct Decision {
        let decision: String
        let reason: String
    }

    /// What the gate says to do instead of another spelling of the apply.
    func formReason(kind: String = "fix", tool: String = "skill-health", plan: String? = nil) -> String {
        "Skill Health writes a change only from its own apply command, run by itself: \(tool) \(kind) apply \(plan ?? self.plan). Run it that way."
    }

    /// A plan file as the tool writes it, schema 1: made just now, so it expires in 15 minutes.
    func writePlan(id: String? = nil, kind: String = "fix", summary: String? = nil, used: Bool = false,
                   expiresIn: TimeInterval = 15 * 60) throws {
        let id = id ?? plan
        try FileManager.default.createDirectory(at: skillHealth.appending(path: "pending"), withIntermediateDirectories: true)
        let made = Date.now.addingTimeInterval(expiresIn - 15 * 60)
        let body: [String: Any] = ["schema": 1, "id": id, "kind": kind, "createdAt": made.formatted(.iso8601),
                                   "expiresAt": made.addingTimeInterval(15 * 60).formatted(.iso8601), "used": used,
                                   "summary": summary ?? self.summary]
        try JSONSerialization.data(withJSONObject: body).write(to: skillHealth.appending(path: "pending/\(id).json"))
    }

    /// A plugin folder with a bin folder in it, named `name` under this test's folder.
    @discardableResult
    func makePluginRoot(_ name: String = "plugin") throws -> URL {
        let folder = root.appending(path: name)
        try FileManager.default.createDirectory(at: folder.appending(path: "bin"), withIntermediateDirectories: true)
        return folder
    }

    func hookInput(_ command: String, mode: String? = "default", tool: String = "Bash") throws -> String {
        var object: [String: Any] = ["session_id": "s", "hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": ["command": command]]
        if let mode { object["permission_mode"] = mode }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// What the gate answered, or nil when it printed nothing (no opinion). The gate always exits 0.
    func answer(_ stdin: String, path: String = "/usr/bin:/bin", pluginRoot: URL? = nil, environment: [String: String] = [:]) throws -> Decision? {
        var env = ["SKILL_HEALTH_DIR": skillHealth.plainPath].merging(environment) { _, mine in mine }
        if let pluginRoot { env["CLAUDE_PLUGIN_ROOT"] = pluginRoot.plainPath }
        let result = try runPluginScript(PluginFiles.gate, stdin: stdin, environment: env, path: path)
        #expect(result.status == 0, "exit \(result.status): \(result.error)")
        #expect(result.error.isEmpty, "stderr: \(result.error)")
        guard !result.output.isEmpty else { return nil }
        let object = try #require(try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        let output = try #require(object["hookSpecificOutput"] as? [String: Any])
        #expect(output["hookEventName"] as? String == "PreToolUse")
        return Decision(decision: try #require(output["permissionDecision"] as? String),
                        reason: try #require(output["permissionDecisionReason"] as? String))
    }

    func gate(_ command: String, mode: String? = "default", tool: String = "Bash", pluginRoot: URL? = nil,
              environment: [String: String] = [:]) throws -> Decision? {
        try answer(hookInput(command, mode: mode, tool: tool), pluginRoot: pluginRoot, environment: environment)
    }

    // MARK: The documented limit

    /// The limit SECURITY.md states: a run that builds the plan id while it runs names no plan in its text, so
    /// the gate has no opinion, in a mode that asks and with prompts skipped. The tool's own checks are all
    /// that stand behind it. This pins that the documents and the code say the same thing: if the gate ever
    /// recognises such a run, SECURITY.md and the README change with it.
    @Test(arguments: ["default", "bypassPermissions", "dontAsk"])
    func aRunThatAssemblesThePlanIdIsTheKnownLimitAndGetsNoOpinion(mode: String) throws {
        try writePlan()
        let first = String(plan.prefix(18)), rest = String(plan.dropFirst(18))
        let command = "a=\(first); b=\(rest); skill-health fix apply \"$a$b\""
        #expect(try gate(command, mode: mode) == nil)
    }

    // MARK: Commands that only mention an apply

    /// No plan with this id exists, so nothing here can write one: leave it to the person's own
    /// permissions. This is where a commit message, a pull request title, a heredoc line, a markdown
    /// code span or a search for the words used to be denied.
    @Test func wordsThatNameNoPlanGetNoOpinion() throws {
        let apply = "skill-health fix apply \(plan)"
        let commands = [
            #"git commit -m "skill-health fix apply \#(plan) is allowed""#,
            "git commit -m 'gate: skill-health fix apply \(plan)'",
            "gh pr create --title \"skill-health fix apply \(plan)\" --body x",
            "cat <<'EOF'\n\(apply)\nEOF",
            "git commit -F - <<EOF\nTitle\n\n\(apply)\nEOF",
            "echo 'Run `\(apply)` next'",
            #"echo "Run \`\#(apply)\` next""#,
            #"git log --grep="skill-health fix apply""#,
            "git log --grep 'skill-health undo apply'",
            #"grep -rn "skill-health fix apply" docs"#,
            "echo apply skill-health fix",
            "echo skill-health update apply flow",
            "printf '%s' 'see skill-health undo apply in the docs'",
            "myskill-health fix apply \(plan)",
            "skill-health fix apply-all \(plan)",
            // Not a plan id at all: the tool refuses these itself.
            "skill-health fix apply",
            "skill-health fix apply ../x",
            "skill-health fix apply /etc/passwd",
            "skill-health fix apply $PLAN",
            "skill-health fix apply \(plan.dropLast())",
            "skill-health fix apply 3F2504E0-4F89-41D3-9A0C-0305E82C330Z",
            "skill-health fix apply --force",
        ]
        // First with no pending folder at all, then with some other plan in it.
        for command in commands {
            #expect(try gate(command) == nil, "\(command)")
        }
        try writePlan(id: "3F2504E0-4F89-41D3-9A0C-0305E82C3302")
        for command in commands {
            #expect(try gate(command) == nil, "\(command)")
        }
    }

    @Test func aCommandThatNamesALivePlanButDoesntApplyItGetsNoOpinion() throws {
        try writePlan()
        let commands = [
            "ls -la",
            "git status",
            "skill-health status --json",
            "skill-health fix preview \(plan)",
            "/Users/me/.claude/plugins/cache/skill-health/skill-health/0.4.0/bin/skill-health undo list --json",
            "skill-health decide \(plan) set-aside 30",
            "skill-health update preview --all",
            "cat \(skillHealth.plainPath)/pending/\(plan).json",
            "jq .summary \(skillHealth.plainPath)/pending/\(plan).json",
            "echo Plan: \(plan)",
        ]
        for command in commands {
            #expect(try gate(command) == nil, "\(command)")
        }
    }

    @Test func aToolThatIsntBashGetsNoOpinion() throws {
        try writePlan()
        #expect(try gate("skill-health fix apply \(plan)", tool: "Write") == nil)
    }

    // MARK: Applies

    @Test(arguments: ["fix", "update", "undo"], ["default", "acceptEdits", "auto", "plan"])
    func anApplyAsksAndTheReasonIsThePlansSummary(kind: String, mode: String) throws {
        try writePlan(kind: kind)
        let decision = try #require(try gate("/Users/me/.claude/plugins/cache/skill-health/skill-health/0.4.0/bin/skill-health \(kind) apply \(plan)", mode: mode))
        #expect(decision.decision == "ask")
        #expect(decision.reason == "Skill Health will write this change.\n\n\(summary)")
    }

    @Test func anAbsentModeAsksToo() throws {
        try writePlan()
        #expect(try gate("skill-health fix apply \(plan)", mode: nil)?.decision == "ask")
    }

    @Test func theToolCanBeNamedBareByPathOrByAQuotedOrEscapedPath() throws {
        try writePlan()
        let commands = [
            "skill-health fix apply \(plan)",
            "  skill-health fix apply \(plan)  ",
            "\tskill-health fix apply \(plan)\t",
            "skill-health fix apply \(plan)\n",
            "./bin/skill-health fix apply \(plan)",
            "~/.claude/plugins/cache/skill-health/skill-health/0.4.0/bin/skill-health fix apply \(plan)",
            #""skill-health" fix apply \#(plan)"#,
            #""/Users/me/My Files/.claude/plugins/cache/skill-health/skill-health/0.4.0/bin/skill-health" fix apply \#(plan)"#,
            "'/Users/me/My Files/bin/skill-health' fix apply \(plan)",
            #"/Users/me/My\ Files/bin/skill-health fix apply \#(plan)"#,
            #"/Users/me/It\'s\ here/bin/skill-health fix apply \#(plan)"#,
            #""/Users/me/Bo's Files/bin/skill-health" fix apply \#(plan)"#,
            #"'/Users/me/Say "hi"/bin/skill-health' fix apply \#(plan)"#,
            #""/Users/me/Say \"hi\"/bin/skill-health" fix apply \#(plan)"#,
            "skill-health fix apply \(plan.lowercased())",
        ]
        for command in commands {
            #expect(try gate(command)?.decision == "ask", "\(command)")
        }
    }

    @Test func aTrailingNewLineIsFineButMoreThanOneIsNot() throws {
        try writePlan()
        let apply = "skill-health fix apply \(plan)"
        #expect(try gate(apply + "\n")?.decision == "ask")
        let two = try #require(try gate(apply + "\n\n"))
        #expect(two.decision == "deny")
        #expect(two.reason == formReason())
        let windows = try #require(try gate(apply + "\r\n"))
        #expect(windows.reason == formReason())
    }

    // MARK: Another spelling of an apply

    /// Each of these runs the tool on a live plan, in a spelling the gate doesn't parse, so it is
    /// refused with the one form that works. Under bypassPermissions too: there it would run unseen.
    @Test func anotherSpellingOfAnApplyIsDeniedWithTheFormThatWorks() throws {
        try writePlan()
        let apply = "skill-health fix apply \(plan)"
        let spellings = [
            // The tool by a variable, or by a path with one in it.
            #""$U" fix apply \#(plan)"#,
            "U=skill-health; $U fix apply \(plan)",
            "${SKILL_HEALTH:-skill-health} fix apply \(plan)",
            "$HOME/.claude/plugins/cache/skill-health/skill-health/0.4.0/bin/skill-health fix apply \(plan)",
            "${CLAUDE_PLUGIN_ROOT}/bin/skill-health fix apply \(plan)",
            #""/Users/$USER/bin/skill-health" fix apply \#(plan)"#,
            "`which skill-health` fix apply \(plan)",
            // Wrappers, some with flags of their own.
            "env -u X \(apply)",
            "env FOO=1 \(apply)",
            "SKILL_HEALTH_CLAUDE_HOME=/tmp/x \(apply)",
            "sudo -E \(apply)",
            "nice -n 5 \(apply)",
            "time -p \(apply)",
            "command -p \(apply)",
            "exec \(apply)",
            "nohup \(apply) &",
            "echo \(plan) | xargs -n1 skill-health fix apply",
            "sh -c '\(apply)'",
            #"bash -c "\#(apply)""#,
            "eval \(apply)",
            // Anything joined to it, redirected or substituted around it.
            "cd /tmp && \(apply)",
            "\(apply) && rm -rf ~/.claude/skills",
            "\(apply); rm x",
            "\(apply) || true",
            "\(apply) | tee log",
            "\(apply) &",
            "echo hi\n\(apply)",
            "\(apply)\nrm x",
            "\(apply)\r\nrm x",
            "\(apply) 2>&1",
            "\(apply) > out.txt",
            "\(apply) < in.txt",
            "\(apply) `id`",
            "$(id); \(apply)",
            "true & \(apply)",
            "(\(apply))",
            "{ \(apply); }",
            "if true; then \(apply); fi",
            // Something other than the plan id after it.
            "\(apply) extra",
            "\(apply) # note",
            "skill-health fix apply --force \(plan)",
            "skill-health fix apply \"\(plan)\"",
            "skill-health fix apply '\(plan)'",
            "skill-health fix apply \(plan)0",
            "skill-health fix apply \(plan)/../../x",
            // A word or the plan id split by quotes or a backslash, which the shell puts back together.
            "'skill-health' fix 'apply' \(plan)",
            "skill-health fix ap''ply \(plan)",
            #"skill-health fix a\pply \#(plan)"#,
            "skill-health fix apply \(plan.prefix(30))'\(plan.suffix(6))'",
            "skill-health fix apply \(plan.prefix(30))\\\(plan.suffix(6))",
            // The same, split by a backslash and a new line, which the shell drops.
            "skill-health fix ap\\\nply \(plan)",
            "skill-health fix apply \(plan.prefix(30))\\\n\(plan.suffix(6))",
        ]
        for mode in ["default", "auto", "bypassPermissions", "dontAsk"] {
            for command in spellings {
                let decision = try #require(try gate(command, mode: mode), "\(mode): \(command)")
                #expect(decision.decision == "deny", "\(mode): \(command)")
                #expect(decision.reason == formReason(), "\(mode): \(command)")
            }
        }
    }

    @Test func theFormNamesThePlansOwnKindWhateverTheCommandSaid() throws {
        for kind in ["update", "undo"] {
            try writePlan(kind: kind)
            let decision = try #require(try gate("env skill-health fix apply \(plan)"))
            #expect(decision.reason == formReason(kind: kind))
        }
    }

    @Test func aPlanWithoutAReadableKindGetsAPlaceholderInTheForm() throws {
        try FileManager.default.createDirectory(at: skillHealth.appending(path: "pending"), withIntermediateDirectories: true)
        try "{garbage".write(to: skillHealth.appending(path: "pending/\(plan).json"), atomically: true, encoding: .utf8)
        let decision = try #require(try gate("env skill-health fix apply \(plan)"))
        #expect(decision.decision == "deny")
        #expect(decision.reason == formReason(kind: "<fix|update|undo>"))
    }

    @Test func theFormGivesTheFullToolPathQuotedAsThePathNeeds() throws {
        try writePlan()
        // A plain path, a space, an apostrophe, a double quote, and a path no quoting fits.
        let names = ["plain", "My Files", "o'brien", "say \"hi\"", "it's \"here\""]
        for name in names {
            let pluginRoot = try makePluginRoot(name)
            let decision = try #require(try gate("env skill-health fix apply \(plan)", pluginRoot: pluginRoot), "\(name)")
            #expect(decision.decision == "deny", "\(name)")
            let prefix = "Skill Health writes a change only from its own apply command, run by itself: "
            let suffix = ". Run it that way."
            #expect(decision.reason.hasPrefix(prefix) && decision.reason.hasSuffix(suffix), "\(name)")
            let command = String(decision.reason.dropFirst(prefix.count).dropLast(suffix.count))
            #expect(command.hasSuffix(" fix apply \(plan)"), "\(name)")
            if name == names.last {
                #expect(command == "skill-health fix apply \(plan)", "no quoting fits that path, so the bare word")
            } else {
                #expect(command.contains("bin/skill-health"), "\(name)")
            }
            // Whatever the gate suggests, the gate itself accepts.
            #expect(try gate(command, pluginRoot: pluginRoot)?.decision == "ask", "\(name): \(command)")
        }
    }

    // MARK: The tool is Skill Health's own

    @Test func underAPluginRootTheToolMustBeThePluginsOwn() throws {
        try writePlan()
        let pluginRoot = try makePluginRoot()
        let elsewhere = try makePluginRoot("elsewhere")
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: pluginRoot)
        let bin = pluginRoot.appending(path: "bin").plainPath
        let own = [
            "skill-health fix apply \(plan)",
            "\(bin)/skill-health fix apply \(plan)",
            "\(pluginRoot.plainPath)/bin//skill-health fix apply \(plan)",
            "\(bin)/../bin/skill-health fix apply \(plan)",
            "\(link.plainPath)/bin/skill-health fix apply \(plan)",
            #""\#(bin)/skill-health" fix apply \#(plan)"#,
            "'\(bin)/skill-health' fix apply \(plan)",
            "\(bin)/skill-health fix apply \(plan)\n",
        ]
        for command in own {
            #expect(try gate(command, pluginRoot: pluginRoot)?.decision == "ask", "\(command)")
        }
        let notOurs = [
            "\(elsewhere.plainPath)/bin/skill-health fix apply \(plan)",
            "\(pluginRoot.plainPath)/skill-health fix apply \(plan)",
            "\(bin)/../skill-health fix apply \(plan)",
            "\(root.plainPath)/missing/bin/skill-health fix apply \(plan)",
            "/usr/local/bin/skill-health fix apply \(plan)",
            "./skill-health fix apply \(plan)",
            #""\#(elsewhere.plainPath)/bin/skill-health" fix apply \#(plan)"#,
            "'\(elsewhere.plainPath)/bin/skill-health' fix apply \(plan)",
        ]
        for mode in ["default", "bypassPermissions"] {
            for command in notOurs {
                let decision = try #require(try gate(command, mode: mode, pluginRoot: pluginRoot), "\(command)")
                #expect(decision.decision == "deny", "\(command)")
                #expect(decision.reason == Self.notOurToolReason, "\(command)")
            }
        }
    }

    @Test func aTildePathIsReadTheWayTheShellReadsIt() throws {
        try writePlan()
        let home = root.appending(path: "home")
        let pluginRoot = home.appending(path: "plugin")
        try FileManager.default.createDirectory(at: pluginRoot.appending(path: "bin"), withIntermediateDirectories: true)
        let environment = ["HOME": home.plainPath]
        #expect(try gate("~/plugin/bin/skill-health fix apply \(plan)", pluginRoot: pluginRoot, environment: environment)?.decision == "ask")
        let other = try #require(try gate("~/other/bin/skill-health fix apply \(plan)", pluginRoot: pluginRoot, environment: environment))
        #expect(other.reason == Self.notOurToolReason)
    }

    /// Claude Code may hand the hook a plugin root that ends in a slash or is itself a link; the
    /// tool is the same file either way.
    @Test func aPluginRootThatEndsInASlashOrIsALinkNamesTheSameTool() throws {
        try writePlan()
        let pluginRoot = try makePluginRoot()
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: pluginRoot)
        let own = "\(pluginRoot.plainPath)/bin/skill-health fix apply \(plan)"
        let throughTheLink = "\(link.plainPath)/bin/skill-health fix apply \(plan)"
        for rootValue in [pluginRoot.plainPath + "/", link.plainPath, link.plainPath + "/"] {
            for command in [own, throughTheLink] {
                let decision = try gate(command, environment: ["CLAUDE_PLUGIN_ROOT": rootValue])
                #expect(decision?.decision == "ask", "\(rootValue): \(command)")
            }
        }
    }

    /// Whose tool it is gets said before anything about the plan: a command that runs some other
    /// program says nothing true about this plan.
    @Test func aToolThatIsntSkillHealthsOwnIsRefusedBeforeThePlanIsLookedAt() throws {
        let pluginRoot = try makePluginRoot()
        let elsewhere = "\(root.plainPath)/elsewhere/bin/skill-health"
        // No plan at all, then one that is used and one that is expired.
        #expect(try gate("\(elsewhere) fix apply \(plan)", pluginRoot: pluginRoot)?.reason == Self.notOurToolReason)
        try writePlan(used: true)
        #expect(try gate("\(elsewhere) fix apply \(plan)", pluginRoot: pluginRoot)?.reason == Self.notOurToolReason)
        try writePlan(expiresIn: -60)
        #expect(try gate("\(elsewhere) fix apply \(plan)", pluginRoot: pluginRoot)?.reason == Self.notOurToolReason)
    }

    @Test func withoutAPluginRootAnyPathIsAccepted() throws {
        try writePlan()
        #expect(try gate("/anywhere/bin/skill-health fix apply \(plan)")?.decision == "ask")
        #expect(try gate("/anywhere/bin/skill-health fix apply \(plan)", pluginRoot: nil, environment: ["CLAUDE_PLUGIN_ROOT": ""])?.decision == "ask")
    }

    // MARK: Refusals

    /// The plan file's own state decides before any prompt: a prompt for a change that can't be
    /// written would ask the person about nothing.
    @Test func aPlanThatIsUsedExpiredOrForAnotherCommandIsDenied() throws {
        try writePlan(used: true)
        #expect(try gate("skill-health fix apply \(plan)")?.reason == "That change has already been written.")
        try writePlan(expiresIn: -60)
        let expired = try #require(try gate("skill-health fix apply \(plan)"))
        #expect(expired.decision == "deny")
        #expect(expired.reason.contains("more than 15 minutes ago"))
        try writePlan(kind: "fix")
        let kind = try #require(try gate("skill-health undo apply \(plan)"))
        #expect(kind.decision == "deny")
        #expect(kind.reason.contains("isn't for skill-health undo apply"))
        try writePlan()
        #expect(try gate("skill-health fix apply \(plan)")?.decision == "ask")
    }

    @Test(arguments: ["bypassPermissions", "dontAsk"])
    func anApplyIsDeniedWhilePermissionPromptsAreSkipped(mode: String) throws {
        for kind in ["fix", "update", "undo"] {
            try writePlan(kind: kind)
            let decision = try #require(try gate("skill-health \(kind) apply \(plan)", mode: mode))
            #expect(decision.decision == "deny")
            #expect(decision.reason == Self.bypassReason, "\(kind)")
        }
        // The plan's own state is said first when there is one to say.
        try writePlan(used: true)
        #expect(try gate("skill-health fix apply \(plan)", mode: mode)?.reason == "That change has already been written.")
    }

    @Test func anApplyWithoutAPlanIsDenied() throws {
        // No pending folder at all, then a folder with some other plan in it.
        let first = try #require(try gate("skill-health fix apply \(plan)"))
        #expect(first.decision == "deny")
        #expect(first.reason == Self.notReadyReason)
        try writePlan(id: "3F2504E0-4F89-41D3-9A0C-0305E82C3302")
        #expect(try gate("skill-health fix apply \(plan)")?.reason == Self.notReadyReason)
    }

    @Test func aPlanThatCantBeReadOrHasNoSummaryIsNotReady() throws {
        try FileManager.default.createDirectory(at: skillHealth.appending(path: "pending"), withIntermediateDirectories: true)
        let unreadable = [("garbage", "{garbage"), ("not an object", "[1,2]"), ("no summary", #"{"schema":1,"id":"x"}"#),
                          ("empty summary", #"{"summary":""}"#), ("summary not text", #"{"summary":3}"#)]
        for (label, text) in unreadable {
            try text.write(to: skillHealth.appending(path: "pending/\(plan).json"), atomically: true, encoding: .utf8)
            let decision = try #require(try gate("skill-health fix apply \(plan)"), "\(label)")
            #expect(decision.decision == "deny", "\(label)")
            #expect(decision.reason == Self.notReadyReason, "\(label)")
        }
    }

    /// The tool never writes a summary longer than 3,000 characters, so a longer one is not a plan it made.
    @Test func aSummaryOverThreeThousandCodePointsIsDenied() throws {
        let long = "That change is too long to show in full here, so it can't be approved. Run the preview again."
        try writePlan(summary: String(repeating: "x", count: 3_000))
        let exact = try #require(try gate("skill-health fix apply \(plan)"))
        #expect(exact.decision == "ask")
        #expect(exact.reason == "Skill Health will write this change.\n\n" + String(repeating: "x", count: 3_000))
        try writePlan(summary: String(repeating: "x", count: 3_001))
        let over = try #require(try gate("skill-health fix apply \(plan)"))
        #expect(over.decision == "deny")
        #expect(over.reason == long)
        try writePlan(kind: "update", summary: String(repeating: "x", count: 5_000))
        #expect(try gate("skill-health update apply \(plan)")?.reason == long)
        // In code points, not bytes or UTF-16 units: 3,000 emoji fit, and a combining mark counts.
        try writePlan(summary: String(repeating: "\u{1F600}", count: 3_000))
        #expect(try gate("skill-health fix apply \(plan)")?.decision == "ask")
        try writePlan(summary: String(repeating: "e\u{301}", count: 1_600))
        #expect(try gate("skill-health fix apply \(plan)")?.reason == long)
        // And the prompt is skipped before it is asked: a long summary is denied in every mode.
        #expect(try gate("skill-health fix apply \(plan)", mode: "bypassPermissions")?.reason == long)
    }

    // MARK: Time

    /// A hook that runs past its timeout is let through, so nothing here may grow faster than the
    /// command. Characters the matcher could trip on, 100 KB of them, in every position.
    @Test func longInputsFinishFast() throws {
        try writePlan()
        let junk = (0..<2_700).map { _ in "3F2504E0-4F89-41D3-9A0C-0305E82C3399" }.joined(separator: " ")
        var commands: [(String, String)] = [("junk ids", "apply " + junk), ("junk ids then live", "apply \(junk) \(plan)")]
        for character in ["{", "\"", "\\", " ", "'", "/", "$", "`", "\n"] {
            let body = String(repeating: character, count: 100_000)
            commands += [
                ("\(character.debugDescription) alone", body),
                ("\(character.debugDescription) then apply", "skill-health fix apply \(plan) \(body)"),
                ("apply after \(character.debugDescription)", "\(body) skill-health fix apply \(plan)"),
                ("\(character.debugDescription) in the path", "\(body)/skill-health fix apply \(plan)"),
                ("\(character.debugDescription) in quotes", "\"\(body)/skill-health\" fix apply \(plan)"),
                ("\(character.debugDescription) after the tool", "skill-health \(body)"),
            ]
        }
        let clock = ContinuousClock()
        for (label, command) in commands {
            let input = try hookInput(command)
            let elapsed = try clock.measure { _ = try answer(input) }
            #expect(elapsed < .seconds(1), "\(label): \(elapsed)")
        }
        // Slow or not, the answer is the right one: a long command naming the plan is refused.
        #expect(try gate("skill-health fix apply \(plan) " + String(repeating: "{", count: 100_000))?.decision == "deny")
        #expect(try gate(String(repeating: "{", count: 100_000)) == nil)
    }

    // MARK: Input the gate can't read

    @Test func malformedInputNeverCrashesAndHasNoOpinionWhenItNamesNoPlan() throws {
        for stdin in ["", "not json", "{", "[]", "null", "42", #"{"tool_name":"Bash"}"#, #"{"tool_name":"Bash","tool_input":{}}"#,
                      #"{"tool_name":"Bash","tool_input":{"command":42}}"#,
                      #"{"tool_name":"Bash","tool_input":"skill-health fix apply"#,
                      #"{"tool_name":"Bash","tool_input":"skill-health update apply \#(plan)"}"#] {
            #expect(try answer(stdin) == nil, "\(stdin)")
        }
    }

    @Test func inputThatNamesALivePlanButCantBeReadIsDenied() throws {
        try writePlan()
        let truncated = try #require(try answer(#"{"tool_name":"Bash","tool_input":"skill-health fix apply \#(plan)"#))
        #expect(truncated.decision == "deny")
        let notAnObject = try #require(try answer(#"{"tool_name":"Bash","tool_input":"skill-health update apply \#(plan)"}"#))
        #expect(notAnObject.decision == "deny")
        #expect(notAnObject.reason.contains("couldn't read"))
        #expect(try answer("not json") == nil)
    }

    // MARK: Without jq

    /// A folder of the few tools the gate needs without jq, since /usr/bin has jq beside them.
    func pathWithoutJq() throws -> String {
        let folder = root.appending(path: "no-jq")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["cat", "grep", "tr"] {
            let source = try #require(["/usr/bin", "/bin"].map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) })
            try FileManager.default.createSymbolicLink(atPath: folder.appending(path: name).plainPath, withDestinationPath: source)
        }
        return folder.plainPath
    }

    @Test func withoutJqOnlyACommandNamingALivePlanIsDenied() throws {
        let path = try pathWithoutJq()
        try writePlan()
        let apply = try #require(try answer(hookInput("skill-health undo apply \(plan)"), path: path))
        #expect(apply.decision == "deny")
        #expect(apply.reason.contains("jq"))
        // Another spelling of it, in bypass mode too.
        for command in ["env skill-health fix apply \(plan)", #""$U" fix apply \#(plan.lowercased())"#, "cd x && skill-health fix apply \(plan)"] {
            #expect(try answer(hookInput(command, mode: "bypassPermissions"), path: path)?.decision == "deny", "\(command)")
        }
        // Everything else, including words that name no plan, is left alone.
        for command in ["ls -la", "git status", "skill-health fix preview",
                        "skill-health fix apply 3F2504E0-4F89-41D3-9A0C-0305E82C3399",
                        #"git commit -m "skill-health fix apply is allowed""#,
                        #"grep -rn "skill-health fix apply" docs"#] {
            #expect(try answer(hookInput(command), path: path) == nil, "\(command)")
        }
        #expect(try answer("not json", path: path) == nil)
        #expect(try answer("", path: path) == nil)
    }

    @Test func withoutJqAndWithoutAnyPlanAnApplyHasNoOpinion() throws {
        let path = try pathWithoutJq()
        #expect(try answer(hookInput("skill-health undo apply \(plan)"), path: path) == nil)
    }
}
