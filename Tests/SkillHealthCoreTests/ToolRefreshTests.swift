import Foundation
import Testing
@testable import SkillHealthCore

/// `skill-health refresh`: the plugin's own way to write what its SessionStart hook prints, so Claude gets
/// the corrections with no Mac app. The real binary on a scratch .claude folder, as ToolTests runs it.
extension ToolTests {
    var statusFile: URL { home.appending(path: "skill-health/status.json") }
    var hookNote: URL { home.appending(path: "skill-health/hook-note.json") }
    var hookQuiet: URL { home.appending(path: "skill-health/hook-quiet.json") }
    var refreshedStamp: URL { home.appending(path: "skill-health/.refreshed") }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    @Test func refreshWritesWhatTheSessionHookPrints() throws {
        try setUp()
        let result = try run("refresh")
        #expect(result.status == 0)
        #expect(result.out.contains("Claude will get 1 correction at the start of a session."))
        for file in [statusFile, hookNote, hookQuiet, refreshedStamp] { #expect(exists(file), "\(file.lastPathComponent)") }
        let quiet = try String(contentsOf: hookQuiet, encoding: .utf8)
        #expect(quiet.contains("npm install -g supabase"))
        #expect(quiet.contains("Global installs are refused."))
        let status = try json(String(contentsOf: statusFile, encoding: .utf8))
        #expect((status["corrections"] as? [[String: Any]])?.count == 1)
        let note = try String(contentsOf: hookNote, encoding: .utf8)
        #expect(note.contains("skill-health: 1 skill you use has instructions that now fail (supa)"))
        #expect(note.contains(StatusSnapshot.correctionsTail))
    }

    @Test func refreshSendsNothingAndChangesNoSkill() throws {
        try setUp()
        _ = try run("refresh")
        #expect(try Data(contentsOf: file) == Data(original.utf8))
        // Nothing but Skill Health's own files and its usage cache appeared.
        let made = try FileManager.default.contentsOfDirectory(atPath: home.appending(path: "skill-health").path(percentEncoded: false)).sorted()
        #expect(Set(made).isSubset(of: ["findings.json", "status.json", "hook-note.json", "hook-quiet.json", ".refreshed", "usage-cache.json", "audit-plan.json"]), "\(made)")
        #expect(!exists(home.appending(path: "skill-health/compare.json")))
    }

    @Test func refreshStampsEvenWhenNothingChanged() throws {
        try setUp()
        _ = try run("refresh")
        let old = Date.now.addingTimeInterval(-3 * 3600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: refreshedStamp.path(percentEncoded: false))
        #expect(try run("refresh").status == 0)
        let stamped = try #require(try FileManager.default.attributesOfItem(atPath: refreshedStamp.path(percentEncoded: false))[.modificationDate] as? Date)
        #expect(stamped.timeIntervalSince(old) > 3 * 3600 - 60)
    }

    @Test func nothingToTellClaudeWritesNoHookFilesButStillStamps() throws {
        try setUp()
        try #"{"version":1,"audited":{"supa":"2026-10-01T00:00:00Z"},"findings":[]}"#
            .write(to: home.appending(path: "skill-health/findings.json"), atomically: true, encoding: .utf8)
        let result = try run("refresh")
        #expect(result.status == 0)
        #expect(result.out.contains("Claude has nothing to be told"))
        #expect(exists(statusFile) && exists(refreshedStamp))
        #expect(!exists(hookNote) && !exists(hookQuiet))
    }

    @Test func refreshLeavesTheFilesAloneWhileTheResultsCantBeRead() throws {
        try setUp()
        _ = try run("refresh")
        let before = try Data(contentsOf: hookQuiet)
        try "not json".write(to: home.appending(path: "skill-health/findings.json"), atomically: true, encoding: .utf8)
        let result = try run("refresh")
        #expect(result.status == 1)
        #expect(result.err.hasPrefix("skill-health: "))
        #expect(try Data(contentsOf: hookQuiet) == before)   // the corrections Claude had are not silenced
    }

    @Test func refreshLeavesTheFilesAloneWhileTheKnownCorrectionsCantBeRead() throws {
        try setUp()
        _ = try run("refresh")
        let before = try Data(contentsOf: hookQuiet)
        try "not json".write(to: home.appending(path: "corrections.json"), atomically: true, encoding: .utf8)
        let result = try run("refresh")
        #expect(result.status == 1)
        #expect(result.err.contains("known corrections"))
        #expect(try Data(contentsOf: hookQuiet) == before)
    }

    /// Dotfile managers and a shared ~/.agents/skills make ~/.claude/skills itself a symlink. Foundation's
    /// URL listing refuses that, which once read as "no skills" and wrote an all-clear.
    @Test func aSkillsFolderThatIsASymlinkIsListedLikeAnyOther() throws {
        try setUp()
        let real = home.appending(path: "dotfiles-skills")
        try FileManager.default.moveItem(at: home.appending(path: "skills"), to: real)
        try FileManager.default.createSymbolicLink(at: home.appending(path: "skills"), withDestinationURL: real)
        let result = try run("refresh")
        #expect(result.status == 0, "\(result.err)")
        #expect(result.out.contains("Claude will get 1 correction"), "\(result.out)")
        #expect(try run("status").out.hasPrefix("2 skills"))
    }

    @Test func refreshLeavesTheFilesAloneWhileTheSkillsCantBeListed() throws {
        try setUp()
        _ = try run("refresh")
        let before = try Data(contentsOf: hookQuiet)
        // A file where the skills folder was: it exists, but can't be listed.
        try FileManager.default.removeItem(at: home.appending(path: "skills"))
        try "x".write(to: home.appending(path: "skills"), atomically: true, encoding: .utf8)
        let result = try run("refresh")
        #expect(result.status == 1)
        #expect(result.err.contains("couldn't list the skills"), "\(result.err)")
        #expect(try Data(contentsOf: hookQuiet) == before)   // not an all-clear
        // The commands that read say so too, instead of "no skills" and "nothing to fix".
        #expect(try run("findings").status == 1)
        #expect(try run("plan").status == 1)
        let status = try json(run("status", "--json").out)
        #expect((status["skillsProblem"] as? String)?.contains("couldn't list the skills") == true)
        #expect(try run("status").out.contains("couldn't list the skills"))
    }

    @Test func withoutASkillsFolderRefreshSaysSoAndMakesNothing() throws {
        let result = try run("refresh")
        #expect(result.status == 1)
        #expect(result.err.contains("There's no skills folder at"))
        #expect(!exists(home.appending(path: "skill-health")))
    }

    // MARK: after a command that changes what Claude would be told

    @Test func anAppliedFixBringsTheFilesUpToDateOnItsOwn() throws {
        try setUp()
        _ = try run("refresh")
        #expect(exists(hookQuiet))
        let id = try plan(from: run("fix", "preview", findingID).out)
        #expect(try run("fix", "apply", id).status == 0)
        #expect(!exists(hookQuiet))   // the line is fixed, so there is nothing to tell Claude
        let status = try json(String(contentsOf: statusFile, encoding: .utf8))
        #expect((status["corrections"] as? [Any])?.isEmpty == true)
    }

    @Test func aDecisionBringsThemUpToDateBothWays() throws {
        try setUp()
        _ = try run("refresh")
        #expect(try run("decide", findingID, "set-aside", "30").status == 0)
        #expect(!exists(hookQuiet))
        #expect(try run("decide", findingID, "reopen").status == 0)
        #expect(exists(hookQuiet))
    }

    @Test func savingACheckBringsThemUpToDate() throws {
        try setUp()
        _ = try run("refresh")
        // A later check of the same skill that finds nothing replaces its findings.
        let save = try run(["save-findings", "-"], stdin: #"{"audited":["supa"],"findings":[]}"#)
        #expect(save.status == 0, "\(save.err)")
        #expect(!exists(hookQuiet))
    }

    @Test func aFailedWriteLeavesTheFilesAloneAndKeepsItsOwnFailure() throws {
        try setUp()
        _ = try run("refresh")
        let before = try Data(contentsOf: hookQuiet)
        let bad = try run("decide", findingID, "set-aside", "7")   // not 30, 90 or until-update
        #expect(bad.status != 0)
        #expect(try Data(contentsOf: hookQuiet) == before)
    }

    /// A set-aside "until the source changes" reopens when a comparison finds the source moved.
    @Test func aComparisonBringsThemUpToDateToo() throws {
        try setUp()
        let result = try run("compare")
        #expect(result.status == 0, "\(result.err)")
        #expect(exists(refreshedStamp) && exists(hookQuiet))
    }

    @Test func readingCommandsStartNoRefresh() throws {
        try setUp()
        for command in [["status", "--json"], ["findings", "--json"], ["plan", "--json"], ["fix", "preview", findingID]] {
            _ = try run(command)
        }
        #expect(!exists(refreshedStamp) && !exists(hookQuiet) && !exists(statusFile))
    }

    // MARK: what /skill-health:status reads

    /// Every field the skill's text names has to exist in the JSON it reads, and the other way round for the
    /// fields it relies on: a rename on either side would otherwise go unnoticed until someone read a wrong answer.
    @Test func theStatusSkillsFieldsAreTheOnesTheToolPrints() throws {
        try setUp()
        let body = try PluginSkill.load("status").body
        let status = try json(run("status", "--json").out)
        for field in ["used", "usedIsLowerBound", "checkedUsed", "failing", "deprecated", "bySkill", "setAsideFailing", "setAsideDeprecated",
                      "due", "dueSkills", "withSource", "comparedProblems", "compareStopped", "skillsProblem", "findingsProblem",
                      "correctionsProblem", "decisionsProblem", "usageProblem", "compareProblem"] {
            #expect(status.keys.contains(field), "status --json has no \(field)")
            #expect(body.contains("`\(field)`"), "the status skill doesn't name \(field)")
        }
        let list = try json(run("update", "list", "--json").out)
        for field in ["comparedAt", "stale", "eligible", "stopped"] {
            #expect(list.keys.contains(field), "update list --json has no \(field)")
            #expect(body.contains("`\(field)`"), "the status skill doesn't name \(field)")
        }
        for field in ["skill", "checkedDay", "failing", "deprecated", "loads"] { #expect(body.contains("`\(field)`"), "\(field)") }
    }

    @Test func statusSaysWhatIsDueWithoutThePlan() throws {
        try setUp()
        let status = try json(run("status", "--json").out)
        // supa was checked on Oct 1 but its files aren't fingerprinted, so it is due; `other` is never loaded.
        #expect(status["due"] as? Int == 1)
        let due = try #require(status["dueSkills"] as? [[String: Any]])
        #expect(due.first?["skill"] as? String == "supa")
        #expect(due.first?["checkedOn"] as? String != nil)
        #expect((due.first?["checkedDay"] as? String)?.contains("Oct") == true)
        #expect(status["withSource"] as? Int == 0)
        try setUp(checked: false)
        let never = try json(run("status", "--json").out)
        #expect((never["dueSkills"] as? [[String: Any]])?.first?["checkedOn"] is NSNull)
    }
}
