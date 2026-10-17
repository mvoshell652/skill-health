import Foundation
import Synchronization
import Testing
@testable import SkillHealthCore

/// The SessionStart hook starts `skill-health refresh` in the background when what Claude gets is a day old or
/// was never made, so the plugin works without the Mac app. The tool here is a stub that notes it ran and
/// then takes a few seconds: the hook must not wait for it, and must not start it twice.
extension HookScriptTests {
    /// A plugin root whose tool is the stub. `log` gets one line per run, the arguments it was given.
    func stubPluginRoot(toolSeconds: Int = 3, withSkills: Bool = true) throws -> (root: URL, log: URL) {
        if withSkills { try FileManager.default.createDirectory(at: root.appending(path: "skills"), withIntermediateDirectories: true) }
        let pluginRoot = root.appending(path: "plugin-root")
        try FileManager.default.createDirectory(at: pluginRoot.appending(path: "bin"), withIntermediateDirectories: true)
        let log = root.appending(path: "tool-ran.log")
        let tool = pluginRoot.appending(path: "bin/skill-health")
        try "#!/bin/sh\necho \"$*\" >> \"\(log.plainPath)\"\nsleep \(toolSeconds)\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.plainPath)
        return (pluginRoot, log)
    }

    /// True once the stub has run (it starts after the hook has already returned).
    func ran(_ log: URL, within seconds: Double) -> Bool {
        let deadline = Date.now.addingTimeInterval(seconds)
        repeat {
            if FileManager.default.fileExists(atPath: log.plainPath) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date.now < deadline
        return false
    }

    func ranTimes(_ log: URL) -> Int {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    /// Dates a file of Skill Health's (a folder for the lock) `hours` ago; negative for the future.
    func age(_ name: String, hours: Double) throws {
        let url = skillHealth.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.plainPath) {
            if name == ".refresh-lock" {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                FileManager.default.createFile(atPath: url.plainPath, contents: Data())
            }
        }
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-hours * 3600)], ofItemAtPath: url.plainPath)
    }

    func env(_ pluginRoot: URL, _ extra: [String: String] = [:]) -> [String: String] {
        ["CLAUDE_PLUGIN_ROOT": pluginRoot.plainPath].merging(extra) { _, new in new }
    }

    @Test func neverMadeStartsARefreshAndTheHookDoesNotWaitForIt() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 3)
        try files()
        let started = Date.now
        let printed = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(Date.now.timeIntervalSince(started) < 2, "the hook waited for the tool")
        #expect(printed == #"{"systemMessage":"note"}"#)   // this session prints what is already there
        #expect(ran(log, within: 3))
        #expect(try String(contentsOf: log, encoding: .utf8) == "refresh\n")
    }

    @Test func aFreshStatusFileMeansNoRefresh() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        try age("status.json", hours: 1)
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(!ran(log, within: 1))
    }

    @Test func theToolsOwnStampAloneCountsAsFresh() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        try age(".refreshed", hours: 5)
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(!ran(log, within: 1))
    }

    @Test func aDayOldEverythingStartsARefresh() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        try age("status.json", hours: 21)
        try age(".refreshed", hours: 22)
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(ran(log, within: 3))
    }

    @Test func justUnderTwentyHoursIsStillFresh() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        try age("status.json", hours: 19)
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(!ran(log, within: 1))
    }

    /// Twenty hooks running at the same moment, as when a few Claude Code windows open together. Checking
    /// a stamp's age and then touching it let several through; making the lock folder lets one.
    @Test func sessionsStartingAtTheSameMomentStartOneRefresh() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 2)
        try files()
        let environment = env(pluginRoot)
        let failures = Mutex(0)
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            let ok = (try? self.run(pluginData: self.pluginData, environment: environment)) != nil
            if !ok { failures.withLock { $0 += 1 } }
        }
        #expect(failures.withLock { $0 } == 0)
        #expect(ran(log, within: 3))
        Thread.sleep(forTimeInterval: 0.5)
        #expect(ranTimes(log) == 1)
    }

    @Test func aSecondSessionAMomentLaterStartsNoneWhileTheLockIsYoung() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        for _ in 0..<3 { _ = try run(pluginData: pluginData, environment: env(pluginRoot)) }
        #expect(ran(log, within: 3))
        Thread.sleep(forTimeInterval: 0.5)
        #expect(ranTimes(log) == 1)
    }

    @Test func aRefreshThatNeverFinishedIsTriedAgainAfterTenMinutes() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        try age(".refresh-lock", hours: 0.5)
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(ran(log, within: 3))
    }

    @Test func aLockFiveMinutesOldStillHoldsTheStartBack() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        try age(".refresh-lock", hours: 5.0 / 60)
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(!ran(log, within: 1))
    }

    /// A clock that ran ahead once leaves files dated in the future. They are not "written in the last
    /// 20 hours": the hook starts a refresh, and (see Engine.writeStatus) that rewrites them.
    @Test func filesDatedInTheFutureDontHoldARefreshBack() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        try age("status.json", hours: -30 * 24)
        try age(".refreshed", hours: -3 * 24)
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(ran(log, within: 3))
    }

    @Test func aLockDatedInTheFutureIsReplaced() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        try age(".refresh-lock", hours: -24)
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(ran(log, within: 3))
    }

    @Test func withoutASkillsFolderNothingStartsAndNoLockIsMade() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0, withSkills: false)
        try files()
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(!ran(log, within: 1))
        #expect(!FileManager.default.fileExists(atPath: skillHealth.appending(path: ".refresh-lock").plainPath))
    }

    @Test func aSkillsFolderThatIsASymlinkCounts() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0, withSkills: false)
        let elsewhere = root.appending(path: "shared-skills")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "skills"), withDestinationURL: elsewhere)
        try files()
        _ = try run(pluginData: pluginData, environment: env(pluginRoot))
        #expect(ran(log, within: 3))
    }

    /// Skill Health reads ~/.claude. With Claude Code pointed at another folder it would read the skills of a
    /// profile Claude Code isn't using, so it starts nothing.
    @Test func aCustomConfigFolderStartsNoRefresh() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        _ = try run(pluginData: pluginData, environment: env(pluginRoot, ["HOME": root.plainPath, "CLAUDE_CONFIG_DIR": "/somewhere/else"]))
        #expect(!ran(log, within: 1))
        try? FileManager.default.removeItem(at: skillHealth.appending(path: ".refresh-lock"))
        _ = try run(pluginData: pluginData, environment: env(pluginRoot, ["HOME": root.plainPath, "CLAUDE_CONFIG_DIR": root.appending(path: ".claude").plainPath]))
        #expect(ran(log, within: 3))
    }

    @Test func bothOptionsOffStartNoRefresh() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
        try files()
        let off = Self.noteOff.merging(Self.correctionsOff) { mine, _ in mine }
        _ = try run(pluginData: pluginData, environment: env(pluginRoot, off))
        #expect(!ran(log, within: 1))
    }

    @Test func oneOptionOffStillRefreshes() throws {
        for off in [Self.noteOff, Self.correctionsOff] {
            let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: skillHealth.appending(path: ".refresh-lock"))
            try files()
            _ = try run(pluginData: pluginData, environment: env(pluginRoot, off))
            #expect(ran(log, within: 3), "\(off)")
        }
    }

    @Test func withoutTheToolNothingStartsAndNothingFails() throws {
        let pluginRoot = root.appending(path: "empty-plugin-root")
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        try files()
        #expect(try run(pluginData: pluginData, environment: env(pluginRoot)) == #"{"systemMessage":"note"}"#)
        #expect(!FileManager.default.fileExists(atPath: skillHealth.appending(path: ".refresh-lock").plainPath))
    }

    @Test func aFirstRunMakesTheFolderStartsTheRefreshAndConnects() throws {
        let (pluginRoot, log) = try stubPluginRoot(toolSeconds: 0)   // a skills folder, no Skill Health folder yet
        #expect(!FileManager.default.fileExists(atPath: skillHealth.plainPath))
        #expect(try run(pluginData: pluginData, environment: env(pluginRoot)) == "")   // nothing to say yet
        #expect(ran(log, within: 3))
        #expect(FileManager.default.fileExists(atPath: skillHealth.appending(path: "plugin.json").plainPath))
    }

    @Test func theHookKeepsItsOutputWhetherOrNotARefreshStarts() throws {
        let (pluginRoot, _) = try stubPluginRoot(toolSeconds: 0)
        try files(note: Self.noteAndCorrections, quiet: Self.corrections)
        #expect(try run(pluginData: pluginData, environment: env(pluginRoot)) == Self.noteAndCorrections)
        #expect(try run(source: "clear", pluginData: pluginData, environment: env(pluginRoot)) == Self.corrections)
    }
}
