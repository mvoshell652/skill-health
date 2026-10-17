import Foundation
import Testing
@testable import SkillHealthCore

@Suite("What the menu and the evidence window lean on")
struct MenuSupportTests {
    static func day(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    // MARK: Skill names

    @Test(arguments: ["gcp-cloud-run", "a", "Vite.js_2", "0day", String(repeating: "a", count: 128)])
    func plainNamesMayGoInACommand(name: String) {
        #expect(SkillName.isValid(name))
        #expect(ClaudeCodeCommand.fix(skill: name) == "/skill-health:fix \(name)")
    }

    @Test(arguments: ["", "-lead", ".hidden", "_x", "has space", "semi;colon", "$(whoami)", "back`tick", "new\nline",
                      "trailing\n", "pipe|x", "quo\"te", "naïve", "a/b", String(repeating: "a", count: 129)])
    func anythingElseNeverDoes(name: String) {
        #expect(!SkillName.isValid(name))
        #expect(ClaudeCodeCommand.fix(skill: name) == nil)
    }

    // MARK: The link

    @Test func theLinkCarriesTheCommandAndTheFolderFullyEncoded() {
        let folder = URL(filePath: "/Users/me/.claude/skill-health/workspace")
        #expect(ClaudeCodeCommand.url(for: "/skill-health:fix supabase", to: .terminal, in: folder)?.absoluteString
                == "claude-cli://open?q=%2Fskill-health%3Afix%20supabase&cwd=%2FUsers%2Fme%2F.claude%2Fskill-health%2Fworkspace")
        #expect(ClaudeCodeCommand.url(for: "/skill-health:check", to: .terminal, in: folder)?.absoluteString
                == "claude-cli://open?q=%2Fskill-health%3Acheck&cwd=%2FUsers%2Fme%2F.claude%2Fskill-health%2Fworkspace")
    }

    @Test func theClaudeAppLinkStartsANewCodeSessionWithTheCommandTypedIn() {
        let folder = URL(filePath: "/Users/me/.claude/skill-health/workspace")
        #expect(ClaudeCodeCommand.url(for: "/skill-health:update", to: .claudeApp, in: folder)?.absoluteString
                == "claude://code/new?q=%2Fskill-health%3Aupdate&folder=%2FUsers%2Fme%2F.claude%2Fskill-health%2Fworkspace")
        // The same rules as the terminal link: one value each, nothing added, nothing unsafe.
        #expect(ClaudeCodeCommand.url(for: "/skill-health:fix a&folder=/etc", to: .claudeApp, in: folder)?.absoluteString
                == "claude://code/new?q=%2Fskill-health%3Afix%20a%26folder%3D%2Fetc&folder=%2FUsers%2Fme%2F.claude%2Fskill-health%2Fworkspace")
        #expect(ClaudeCodeCommand.url(for: "/skill-health:fix\nrm", to: .claudeApp, in: folder) == nil)
    }

    @Test func bothLinksStartInTheWorkspace() throws {
        let (skillHealth, cleanup) = Self.scratchSkillHealthFolder()
        defer { cleanup() }
        let app = try #require(try ClaudeCodeCommand.link(for: ClaudeCodeCommand.check, to: .claudeApp, skillHealthFolder: skillHealth))
        let query = try #require(URLComponents(url: app, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.map(\.name) == ["q", "folder"])
        #expect(query.first { $0.name == "folder" }?.value == Self.path(skillHealth) + "/workspace")
    }

    // MARK: Where a command opens

    @Test func theClaudeAppComesFirstThenATerminal() {
        #expect(ClaudeCodeCommand.Destination.allCases == [.claudeApp, .terminal])
        #expect(ClaudeCodeCommand.destination(preferring: .claudeApp, available: [.claudeApp, .terminal]) == .claudeApp)
        #expect(ClaudeCodeCommand.destination(preferring: .claudeApp, available: [.terminal]) == .terminal)
        #expect(ClaudeCodeCommand.destination(preferring: .claudeApp, available: []) == nil)
    }

    @Test func thePersonsChoiceWinsWhenItIsOnThisMac() {
        #expect(ClaudeCodeCommand.destination(preferring: .terminal, available: [.claudeApp, .terminal]) == .terminal)
        // Chosen, then uninstalled: the other one, rather than nothing.
        #expect(ClaudeCodeCommand.destination(preferring: .terminal, available: [.claudeApp]) == .claudeApp)
    }

    @Test func eachPlaceHasTheLinkAppsRegisterFor() {
        #expect(ClaudeCodeCommand.probe(.claudeApp)?.absoluteString == "claude://code/new")
        #expect(ClaudeCodeCommand.probe(.terminal)?.absoluteString == "claude-cli://open")
        #expect(ClaudeCodeCommand.claudeAppBundleID == "com.anthropic.claudefordesktop")
    }

    @Test func theNoteBeforeTheFirstTerminalWindowSaysWhoIsAsking() {
        #expect(ClaudeCodeCommand.terminalNoteTitle == "Claude Code May Ask to Control Your Terminal")
        #expect(ClaudeCodeCommand.terminalNoteBody(for: "/skill-health:update")
                == "Claude Code opens /skill-health:update in a new terminal window. macOS may ask whether Claude Code can "
                + "control your terminal: the first time, and again after Claude Code updates. The request shows "
                + "Claude Code's version number, like “2.1.289”, instead of its name. Choose Allow. If you choose "
                + "Don't Allow, no window opens until you turn it on in System Settings > Privacy & Security > "
                + "Automation. Nothing runs until you press Return.")
        #expect([ClaudeCodeCommand.terminalNoteContinue, ClaudeCodeCommand.terminalNoteCancel] == ["Continue", "Cancel"])
    }

    @Test func aFolderWithASpaceOrATrailingSlashStaysOneValue() {
        #expect(ClaudeCodeCommand.url(for: "/skill-health:update", to: .terminal, in: URL(filePath: "/Users/me/My Claude/skill-health/workspace/"))?.absoluteString
                == "claude-cli://open?q=%2Fskill-health%3Aupdate&cwd=%2FUsers%2Fme%2FMy%20Claude%2Fskill-health%2Fworkspace")
    }

    // MARK: The workspace Claude Code opens in

    /// A fresh Claude folder's Skill Health folder, which doesn't exist yet.
    static func scratchSkillHealthFolder() -> (skillHealth: URL, cleanup: () -> Void) {
        let root = URL.temporaryDirectory.appending(path: "skill-health-workspace-\(UUID().uuidString)")
        return (root.appending(path: "skill-health"), { try? FileManager.default.removeItem(at: root) })
    }

    static func path(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    @Test func theWorkspaceIsAFolderInsideSkillHealthsOwn() {
        let workspace = ClaudeCodeCommand.workspace(in: URL(filePath: "/Users/me/.claude/skill-health"))
        #expect(Self.path(workspace) == "/Users/me/.claude/skill-health/workspace")
    }

    @Test func theDeepLinkStartsInTheWorkspaceNeverInSkillHealthsOwnFolder() throws {
        let (skillHealth, cleanup) = Self.scratchSkillHealthFolder()
        defer { cleanup() }
        let link = try #require(try ClaudeCodeCommand.link(for: "/skill-health:fix supabase", to: .terminal, skillHealthFolder: skillHealth))
        let query = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "q" }?.value == "/skill-health:fix supabase")
        let cwd = try #require(query.first { $0.name == "cwd" }?.value)
        // Where the pending plans are, a session working in its folder may edit files without asking.
        #expect(cwd == Self.path(skillHealth) + "/workspace")
        #expect(cwd != Self.path(skillHealth))
    }

    @Test func theLinkIsMadeForEveryCommandTheMenuOpens() throws {
        let (skillHealth, cleanup) = Self.scratchSkillHealthFolder()
        defer { cleanup() }
        for command in [ClaudeCodeCommand.check, ClaudeCodeCommand.fixAll, ClaudeCodeCommand.update, "/skill-health:fix gcp-cloud-run"] {
            let link = try #require(try ClaudeCodeCommand.link(for: command, to: .terminal, skillHealthFolder: skillHealth))
            let query = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(query.first { $0.name == "q" }?.value == command)
            #expect(query.first { $0.name == "cwd" }?.value == Self.path(skillHealth) + "/workspace")
        }
        // A command that can't go in a link gets none.
        #expect(try ClaudeCodeCommand.link(for: "/skill-health:fix\nrm", to: .terminal, skillHealthFolder: skillHealth) == nil)
    }

    @Test func preparingTheWorkspaceMakesTheFolderAndAReadmeSayingWhatItIsFor() throws {
        let (skillHealth, cleanup) = Self.scratchSkillHealthFolder()
        defer { cleanup() }
        // Not even Skill Health's own folder exists yet: a fresh Claude folder.
        let workspace = try ClaudeCodeCommand.prepareWorkspace(in: skillHealth)
        #expect(workspace.lastPathComponent == "workspace")
        let names = try FileManager.default.contentsOfDirectory(atPath: workspace.path(percentEncoded: false))
        #expect(names == ["README.md"])
        let readme = try String(contentsOf: workspace.appending(path: "README.md"), encoding: .utf8)
        #expect(readme == ClaudeCodeCommand.workspaceReadme)
        #expect(readme.contains("folder above this one"))
        #expect(readme.contains("You can delete this folder."))
    }

    @Test func preparingTheWorkspaceAgainTouchesNothingAndPutsBackAChangedReadme() throws {
        let (skillHealth, cleanup) = Self.scratchSkillHealthFolder()
        defer { cleanup() }
        let workspace = try ClaudeCodeCommand.prepareWorkspace(in: skillHealth)
        let readme = workspace.appending(path: "README.md")
        let first = try readme.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        Thread.sleep(forTimeInterval: 0.05)
        try ClaudeCodeCommand.prepareWorkspace(in: skillHealth)
        #expect(try readme.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == first)
        try "something else".write(to: readme, atomically: true, encoding: .utf8)
        try ClaudeCodeCommand.prepareWorkspace(in: skillHealth)
        #expect(try String(contentsOf: readme, encoding: .utf8) == ClaudeCodeCommand.workspaceReadme)
    }

    @Test func aWorkspaceThatCantBeMadeGivesNoLinkRatherThanOneToSkillHealthsFolder() throws {
        // Skill Health's folder would sit inside a file, so nothing can be made there.
        let root = URL.temporaryDirectory.appending(path: "skill-health-workspace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root)
        #expect(throws: (any Error).self) {
            try ClaudeCodeCommand.link(for: "/skill-health:check", to: .terminal, skillHealthFolder: root.appending(path: "skill-health"))
        }
    }

    @Test func aCommandCantEndTheValueEarlyOrAddAnother() {
        let folder = URL(filePath: "/x/skill-health/workspace")
        let link = ClaudeCodeCommand.url(for: "/skill-health:fix a&cwd=/etc", to: .terminal, in: folder)?.absoluteString
        #expect(link == "claude-cli://open?q=%2Fskill-health%3Afix%20a%26cwd%3D%2Fetc&cwd=%2Fx%2Fskill-health%2Fworkspace")
        #expect(ClaudeCodeCommand.url(for: "/skill-health:fix\nrm", to: .terminal, in: folder) == nil)
        #expect(ClaudeCodeCommand.url(for: "", to: .terminal, in: folder) == nil)
    }

    @Test func whichCommandsAreChecks() {
        #expect(ClaudeCodeCommand.isCheck("/skill-health:check"))
        #expect(ClaudeCodeCommand.isCheck("/skill-health:check vite"))
        #expect(!ClaudeCodeCommand.isCheck("/skill-health:checkout"))
        #expect(!ClaudeCodeCommand.isCheck("/skill-health:fix"))
    }

    @Test func theAlertSaysWhatWasCopiedAndWhatToDo() {
        #expect(ClaudeCodeCommand.alertTitle == "Couldn't Open Claude Code")
        #expect(ClaudeCodeCommand.alertBody(for: "/skill-health:fix supabase")
                == "/skill-health:fix supabase is copied. Paste it into a Claude Code session and press Return.")
        #expect(ClaudeCodeCommand.alertButton == "OK")
    }

    // MARK: Days

    @Test func aDayOnlyDateIsTheSameDayWestOfUTC() {
        let written = Self.day("2026-02-18T00:00:00Z")
        #expect(DayLabel.utc(written) == "Feb 18, 2026")
        // Formatted in Los Angeles it would read Feb 17: the bug this guards.
        #expect(DayLabel.full(written, timeZone: losAngeles) == "Feb 18, 2026")
        #expect(DayLabel.short(written, now: Self.day("2026-10-04T12:00:00Z"), timeZone: losAngeles) == "Feb 18")
    }

    @Test func aMomentIsTheDayItWasForThePerson() {
        let evening = Self.day("2026-10-04T03:41:00Z")   // 8:41 pm on Oct 3 in Los Angeles
        #expect(DayLabel.full(evening, timeZone: losAngeles) == "Oct 3, 2026")
        #expect(DayLabel.full(evening, timeZone: .gmt) == "Oct 4, 2026")
        #expect(DayLabel.isDayOnly(Self.day("2026-10-04T00:00:00Z")))
        #expect(!DayLabel.isDayOnly(evening))
    }

    @Test func aShortDayKeepsItsYearWhenItIsNotThisOne() {
        let now = Self.day("2026-01-02T12:00:00Z")
        #expect(DayLabel.short(Self.day("2025-12-31T00:00:00Z"), now: now, timeZone: .gmt) == "Dec 31, 2025")
        #expect(DayLabel.short(Self.day("2026-01-01T00:00:00Z"), now: now, timeZone: .gmt) == "Jan 1")
    }

    @Test func countsPrintInEnglishWhateverTheRegion() {
        #expect(NumberText.count(1_639) == "1,639")
        #expect(NumberText.count(79) == "79")
    }

    // MARK: Plugin state

    @Test func thePluginStateFromWhatItLeavesBehind() {
        let ok = PluginHandshake(version: "0.4.0", readAt: .now)
        let old = PluginHandshake(version: "0.3.9", readAt: .now)
        #expect(PluginState(installed: false, lastRead: nil, handshake: nil) == .notInstalled)
        #expect(PluginState(installed: true, lastRead: nil, handshake: nil) == .installedNotConnected)
        #expect(PluginState(installed: true, lastRead: .now, handshake: ok) == .connected)
        #expect(PluginState(installed: false, lastRead: nil, handshake: ok) == .connected)
        #expect(PluginState(installed: true, lastRead: .now, handshake: old) == .older)
        // A plugin from before the handshake touched hook-read and wrote no plugin.json.
        #expect(PluginState(installed: true, lastRead: .now, handshake: nil) == .older)
        #expect(PluginState(installed: false, lastRead: .now, handshake: nil) == .older)
    }

    @Test func whichPluginStatesMayHandOff() {
        #expect(PluginState.connected.canHandOff)
        #expect(PluginState.installedNotConnected.canHandOff)
        #expect(!PluginState.notInstalled.canHandOff)
        #expect(!PluginState.older.canHandOff)
    }

    @Test func theHandshakeIsReadWithOrWithoutFractionalSecondsAndNeverThrows() throws {
        let folder = URL.temporaryDirectory.appending(path: "skill-health-handshake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "plugin.json")
        #expect(PluginHandshake.read(from: file) == nil)

        try Data(#"{"version":"0.4.1","readAt":"2026-10-04T18:00:00Z"}"#.utf8).write(to: file)
        #expect(PluginHandshake.read(from: file) == PluginHandshake(version: "0.4.1", readAt: Self.day("2026-10-04T18:00:00Z")))

        try Data(#"{"version":"0.4.1","readAt":"2026-10-04T18:00:00.250Z"}"#.utf8).write(to: file)
        #expect(PluginHandshake.read(from: file)?.version == "0.4.1")

        try Data(#"{"version":"0.4.1","readAt":"yesterday"}"#.utf8).write(to: file)
        #expect(PluginHandshake.read(from: file) == nil)
        try Data("not json".utf8).write(to: file)
        #expect(PluginHandshake.read(from: file) == nil)
    }

    // MARK: Words about a finding

    func finding(wrongSince: WrongSince = .undated, found: Date = .now, kept: Bool? = true, from: String? = nil, file: String? = nil) -> Finding {
        Finding(skillName: "supabase", severity: .breaks, skillSays: "npm install -g supabase", trueNow: "npx supabase",
                source: URL(string: "https://github.com/supabase/cli/issues/4496")!, foundOn: found, wrongSince: wrongSince,
                file: file, keptBySecondCheck: kept, sharedFrom: from)
    }

    @Test func severityInWordsNeverSaysBreaks() {
        #expect(Severity.breaks.plainName == "Failing")
        #expect(Severity.deprecated.plainName == "Deprecated")
        #expect(Severity.oldVersion.plainName == "Old version")
        #expect(Severity.cosmetic.plainName == "Cosmetic")
    }

    @Test func whenItBecameWrongIsAWholeSentenceInUTC() {
        let day = Self.day("2026-02-18T00:00:00Z")
        #expect(FindingText.wrongSince(.written(on: day)) == "Wrong since it was written (Feb 18, 2026)")
        #expect(FindingText.wrongSince(.since(date: day)) == "Wrong since Feb 18, 2026")
        #expect(FindingText.wrongSince(.installed(on: day)) == "Already wrong when installed (Feb 18, 2026)")
        #expect(FindingText.wrongSince(.undated) == "When this became wrong can't be dated from the evidence")
    }

    @Test func provenanceOfAFindingFromACheck() {
        let found = Self.day("2026-10-03T16:00:00Z")
        #expect(FindingText.provenance(of: finding(found: found, kept: true), timeZone: losAngeles)
                == "Checked on Oct 3, 2026 and kept after a second look tried to disprove it.")
        #expect(FindingText.provenance(of: finding(found: found, kept: false), timeZone: losAngeles)
                == "Checked on Oct 3, 2026. A second look couldn't confirm it.")
        #expect(FindingText.provenance(of: finding(found: found, kept: nil), timeZone: losAngeles) == "Checked on Oct 3, 2026.")
    }

    @Test func provenanceOfAKnownCorrectionUsesItsDayInUTC() {
        let checked = Self.day("2026-09-27T00:00:00Z")
        let shared = finding(found: checked, kept: true, from: "TerminalSkills/skills · nextjs", file: "references/api.md")
        #expect(FindingText.provenance(of: shared, timeZone: losAngeles)
                == "A known correction from TerminalSkills/skills · nextjs, found on Sep 27, 2026 and kept after a second look tried to disprove it. Your references/api.md is identical to that one, byte for byte.")
    }
}

@Suite("The menu's counts")
struct MenuCountsTests {
    let source = URL(string: "https://example.com/e")!

    func finding(_ skill: String, _ severity: Severity, _ status: FindingStatus = .open, says: String = "x") -> Finding {
        Finding(skillName: skill, severity: severity, skillSays: says, trueNow: "y", source: source,
                foundOn: .now, wrongSince: .undated, status: status)
    }

    func skill(_ name: String, loads: Int) -> Skill { Skill(name: name, folder: URL(filePath: "/x/\(name)"), usesLast90Days: loads) }

    @Test func eachSkillCountsItsFailingAndDeprecatedAndCarriesItsLoads() {
        let urgent = [finding("a", .breaks, says: "1"), finding("a", .breaks, says: "2"), finding("a", .deprecated), finding("b", .deprecated)]
        let rows = MenuInput.skillIssues(urgent: urgent, skills: [skill("a", loads: 175), skill("b", loads: 1)])
        #expect(rows == [.init(name: "a", failing: 2, deprecated: 1, loads: 175), .init(name: "b", failing: 0, deprecated: 1, loads: 1)])
    }

    @Test func oldVersionAndCosmeticNeverReachTheMenu() {
        let rows = MenuInput.skillIssues(urgent: [finding("a", .oldVersion), finding("a", .cosmetic)], skills: [skill("a", loads: 5)])
        #expect(rows.isEmpty)
    }

    @Test func onlyFailingInstructionsSetAsideAreCounted() {
        let now = Date.now
        let later = now.addingTimeInterval(86_400)
        let skills = [skill("a", loads: 3), skill("unused", loads: 0)]
        let findings = [
            finding("a", .breaks, .setAside(until: later), says: "1"),                       // counted
            finding("a", .breaks, .notForThisProject, says: "2"),                            // counted
            finding("a", .breaks, .setAside(until: now.addingTimeInterval(-60)), says: "3"), // came back: open, not set aside
            finding("a", .deprecated, .setAside(until: later), says: "4"),                   // deprecated isn't failing
            finding("a", .breaks, .patched(on: now), says: "5"),                             // fixed, not set aside
            finding("a", .breaks, .usingAnotherSkill(name: "b"), says: "6"),                 // replaced, not set aside
            finding("unused", .breaks, .setAside(until: later)),                             // not a skill you use
        ]
        #expect(MenuInput.setAsideFailing(in: findings, skills: skills, now: now) == 2)
    }

    @Test func checkedCountsOnlySkillsYouUseAndFindsTheOldestCheck() {
        let old = Date(timeIntervalSince1970: 1_000), recent = Date(timeIntervalSince1970: 9_000)
        let skills = [skill("a", loads: 3), skill("b", loads: 1), skill("c", loads: 9), skill("unused", loads: 0)]
        let audited = ["a": recent, "b": old, "unused": Date(timeIntervalSince1970: 1)]
        let checked = MenuInput.checkedUsed(skills: skills, audited: audited)
        #expect(checked.count == 2)
        #expect(checked.oldest == old)
        #expect(MenuInput.checkedUsed(skills: skills, audited: [:]).oldest == nil)
    }
}
