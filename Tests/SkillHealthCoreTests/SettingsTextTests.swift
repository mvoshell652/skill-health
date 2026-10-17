import Foundation
import Testing
@testable import SkillHealthCore

/// The settings window says what the brief says, word for word, in every state it can be in.
@Suite("The settings window's words")
struct SettingsTextTests {
    static func day(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }
    static let now = day("2026-10-04T19:00:00Z")

    // MARK: The top line

    let purpose = "Skill Health tells you when a skill you use has a failing or deprecated instruction. You fix it in Claude Code, with the Skill Health plugin."

    @Test(arguments: [SettingsText.Folder.notChosen, .failed])
    func withoutAFolderTheTopLineSaysWhatSkillHealthIsForThenTheNextStep(folder: SettingsText.Folder) {
        #expect(SettingsText.topLines(folder: folder, plugin: .notInstalled, menuBarShown: true)
                == [purpose, "Next: choose your Claude folder."])
    }

    @Test func whileReadingThereIsNoNextStep() {
        #expect(SettingsText.topLines(folder: .reading, plugin: .notInstalled, menuBarShown: true) == [purpose])
    }

    @Test func sampleSkillsSayTheyAreSamplesAndPointBackToTheRealFolder() {
        for plugin in [PluginState.notInstalled, .connected] {
            #expect(SettingsText.topLines(folder: .sample, plugin: plugin, menuBarShown: true)
                    == ["These are sample skills, so you can try Skill Health without Claude Code.",
                        "Next: choose your Claude folder to see your own."])
        }
    }

    @Test func aReadyFolderPointsAtThePluginStep() {
        func lines(_ plugin: PluginState) -> [String] { SettingsText.topLines(folder: .ready, plugin: plugin, menuBarShown: true) }
        #expect(lines(.notInstalled) == ["Next: install the Claude Code plugin."])
        #expect(lines(.installedNotConnected) == ["Next: start a Claude Code session to connect the plugin."])
        #expect(lines(.older) == ["Next: update the Claude Code plugin."])
    }

    @Test func whenEverythingIsReadyTheTopLineSaysSoAndWhatTheIconDoes() {
        #expect(SettingsText.topLines(folder: .ready, plugin: .connected, menuBarShown: true)
                == ["Skill Health is set up.", "It shows a dot in the menu bar when a skill you use needs a fix."])
        #expect(SettingsText.topLines(folder: .ready, plugin: .connected, menuBarShown: false)
                == ["Skill Health is set up.",
                    "The icon is hidden. The plugin's note at the start of a Claude Code session tells you when a skill you use needs a fix."])
    }

    // MARK: The Claude folder

    @Test func theFolderLinesAreWholeSentencesWithTheReasonLast() {
        #expect(SettingsText.folderNotChosen
                == "To see which skills you use, Skill Health reads this hidden folder. In the next window, click Allow.")
        #expect(SettingsText.folderReading == "Reading your skills…")
        #expect(SettingsText.folderSample == "Using sample skills")
        #expect(SettingsText.folderFailed("The folder doesn't exist.") == "Skill Health couldn't read your Claude folder: The folder doesn't exist.")
        #expect(SettingsText.usageFailed("No permission.") == "Skill Health couldn't read which skills you use: No permission.")
        // No reason, no dangling colon.
        #expect(SettingsText.folderFailed("") == "Skill Health couldn't read your Claude folder.")
    }

    @Test func theFolderNeverPromisesWhatSkillHealthKeepsBeyondWhatItDoes() throws {
        // "Skill Health keeps only skill names and when each was used" is not true: the usage cache also
        // holds the path of every session file, and a path names the person's project folders.
        let home = URL.temporaryDirectory.appending(path: "skill-health-keeps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let skills = home.appending(path: "skills").path(percentEncoded: false)
        let session = home.appending(path: "projects/-Users-me-a-secret-project/s1.jsonl")
        try FileManager.default.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        let load = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: \#(skills)/vite\n\nBody"}]},"isMeta":true,"uuid":"u1","timestamp":"2026-10-03T10:00:00.000Z"}"#
        try load.write(to: session, atomically: true, encoding: .utf8)
        let paths = SkillHealthPaths(claudeHome: home)
        _ = try UsageReader(paths: paths).read(now: try Date("2026-10-04T12:00:00Z", strategy: .iso8601))
        let cache = try String(contentsOf: paths.home.appending(path: "usage-cache.json"), encoding: .utf8)
        #expect(cache.contains("-Users-me-a-secret-project"))
        // So the sentence is not said.
        #expect(!SettingsText.folderNotChosen.contains("keeps only"))
        #expect(!SettingsText.folderNotChosen.contains("on this Mac"))
    }

    @Test func countsHandleNoneOneAndMany() {
        #expect(SettingsText.folderCounts(skills: 1_639, usedPhrase: "at least 79 used in the last 90 days")
                == "1,639 skills, at least 79 used in the last 90 days.")
        #expect(SettingsText.folderCounts(skills: 1, usedPhrase: "1 used in the last 90 days") == "1 skill, 1 used in the last 90 days.")
        #expect(SettingsText.folderCounts(skills: 0, usedPhrase: "0 used in the last 90 days") == "No skills in this folder.")
        #expect(SettingsText.folderCounts(skills: 12, usedPhrase: nil) == "12 skills.")
        #expect(SettingsText.folderCountsReading(skills: 12) == "12 skills. Reading which ones you use…")
        #expect(SettingsText.folderCountsReading(skills: 1) == "1 skill. Reading which ones you use…")
        #expect(SettingsText.folderCountsReading(skills: 0) == "No skills in this folder.")
    }

    @Test func theHomeFolderIsAbbreviatedWithTheRealHomeNotTheContainer() {
        let home = "/Users/me"
        #expect(SettingsText.displayPath("/Users/me/.claude", home: home) == "~/.claude")
        // The open panel hands the folder back with a trailing slash.
        #expect(SettingsText.displayPath("/Users/me/.claude/", home: home) == "~/.claude")
        #expect(SettingsText.displayPath("/Users/me/work/claude-two", home: home) == "~/work/claude-two")
        #expect(SettingsText.displayPath("/Users/me", home: home) == "~")
        // A sibling that only starts with the same letters is not inside the home folder.
        #expect(SettingsText.displayPath("/Users/mellow/.claude", home: home) == "/Users/mellow/.claude")
        #expect(SettingsText.displayPath("/Volumes/Backup/.claude", home: home) == "/Volumes/Backup/.claude")
        // The sandbox container is not the home folder: a path inside it stays as it is.
        #expect(SettingsText.displayPath("/Users/me/Library/Containers/app/Data/.claude", home: "/Users/me/Library/Containers/app/Data")
                == "~/.claude")
        #expect(SettingsText.displayPath("/Users/me/Library/Containers/app/Data/.claude", home: home)
                == "~/Library/Containers/app/Data/.claude")
    }

    @Test func theCoverageCaveatIsOneSentenceAndOnlyForALowerBound() {
        let start = Self.now.addingTimeInterval(-90 * 86_400)
        let covered = UsageReport(loads: ["a": 1], windowStart: start, completeSince: start.addingTimeInterval(-86_400))
        #expect(SettingsText.coverageCaveat(covered, now: Self.now, timeZone: .gmt) == nil)

        let since = Self.day("2026-08-25T15:00:00Z")
        let partial = UsageReport(loads: ["a": 1], windowStart: start, completeSince: since)
        #expect(SettingsText.coverageCaveat(partial, now: Self.now, timeZone: .gmt) == "Claude Code has kept sessions only since Aug 25.")
        // Last year's date keeps its year, so it isn't read as this year's.
        let january = Self.day("2026-01-05T12:00:00Z")
        let old = UsageReport(loads: [:], windowStart: january.addingTimeInterval(-90 * 86_400), completeSince: Self.day("2025-12-31T15:00:00Z"))
        #expect(SettingsText.coverageCaveat(old, now: january, timeZone: .gmt) == "Claude Code has kept sessions only since Dec 31, 2025.")

        let none = UsageReport(loads: [:], windowStart: start, completeSince: nil)
        #expect(SettingsText.coverageCaveat(none, now: Self.now) == "There are no Claude Code sessions in this folder yet.")
    }

    // MARK: The plugin

    @Test func beforeTheFolderIsReadyThePluginStepWaitsForIt() {
        for plugin in [PluginState.notInstalled, .connected] {
            let step = SettingsText.pluginStep(folderReady: false, plugin: plugin)
            #expect(step.line == "Skill Health looks for the plugin once it can read your Claude folder.")
            #expect(step.command == .none)
            #expect(step.then == nil)
            #expect(!step.warns)
        }
    }

    @Test func eachPluginStateSaysWhatToDoAndWhichCommand() {
        let missing = SettingsText.pluginStep(folderReady: true, plugin: .notInstalled)
        #expect(missing.line == "To fix, check and update skills in Claude Code, install the plugin. Run this in Terminal:")
        #expect(missing.command == .install)
        #expect(missing.then == "Then start a Claude Code session to connect it.")
        #expect(!missing.warns)

        let waiting = SettingsText.pluginStep(folderReady: true, plugin: .installedNotConnected)
        #expect(waiting.line == "Installed. Start a Claude Code session to connect it.")
        #expect(waiting.command == .none)

        let connected = SettingsText.pluginStep(folderReady: true, plugin: .connected)
        #expect(connected.line == "Run these in Claude Code:")
        #expect(SettingsText.pluginCommands == ["/skill-health:check", "/skill-health:fix", "/skill-health:update", "/skill-health:undo"])
        #expect(connected.command == .none)

        let older = SettingsText.pluginStep(folderReady: true, plugin: .older)
        #expect(older.line == "Some menu items need a newer plugin. To update it, run this in Terminal:")
        #expect(older.command == .update)
        #expect(older.then == "Then start a new Claude Code session.")
        #expect(older.warns)
    }

    @Test func theLinkNoteShowsOnlyWhenMenuItemsCouldHandOffAndNothingHandlesTheLink() {
        let note = "Until you've sent Claude Code one prompt, menu items copy their command instead of opening Claude Code."
        #expect(SettingsText.linkNote(plugin: .connected, canOpen: false) == note)
        #expect(SettingsText.linkNote(plugin: .installedNotConnected, canOpen: false) == note)
        #expect(SettingsText.linkNote(plugin: .connected, canOpen: true) == nil)
        #expect(SettingsText.linkNote(plugin: .notInstalled, canOpen: false) == nil)
        #expect(SettingsText.linkNote(plugin: .older, canOpen: false) == nil)
    }

    @Test func theChoiceOfWhereCommandsOpenShowsOnlyWhenThereIsOne() {
        #expect(SettingsText.showsOpenIn(plugin: .connected, available: [.claudeApp, .terminal]))
        #expect(SettingsText.showsOpenIn(plugin: .installedNotConnected, available: [.claudeApp, .terminal]))
        #expect(!SettingsText.showsOpenIn(plugin: .connected, available: [.claudeApp]))
        #expect(!SettingsText.showsOpenIn(plugin: .connected, available: [.terminal]))
        #expect(!SettingsText.showsOpenIn(plugin: .notInstalled, available: [.claudeApp, .terminal]))
        #expect(!SettingsText.showsOpenIn(plugin: .older, available: [.claudeApp, .terminal]))
    }

    @Test func eachPlaceSaysWhatOpens() {
        #expect(SettingsText.openInTitle == "Open commands in")
        #expect(ClaudeCodeCommand.Destination.allCases.map(SettingsText.destinationName) == ["Claude App", "Terminal"])
        #expect(SettingsText.openInNote(.claudeApp) == "A new Code session in the Claude app, with the command typed in. The app asks each time before it uses Skill Health's folder.")
        #expect(SettingsText.openInNote(.terminal) == "A new window in the terminal you last used Claude Code in, with the command typed in.")
    }

    @Test func theWindowSaysWhenThePluginMovesOnAStep() {
        #expect(SettingsText.pluginAnnouncement(from: .notInstalled, to: .installedNotConnected)
                == "Claude Code plugin installed. Start a Claude Code session to connect it.")
        #expect(SettingsText.pluginAnnouncement(from: .installedNotConnected, to: .connected) == "Claude Code plugin connected.")
        #expect(SettingsText.pluginAnnouncement(from: .older, to: .connected) == "Claude Code plugin connected.")
        #expect(SettingsText.pluginAnnouncement(from: .connected, to: .connected) == nil)
        #expect(SettingsText.pluginAnnouncement(from: .connected, to: .notInstalled) == nil)
        #expect(SettingsText.commandCopied == "Command copied. Paste it in Terminal and press Return.")
    }

    // MARK: Time

    @Test func relativeTimeIsLiveEnglishAndNeverNegative() {
        func ago(_ seconds: Double) -> String { SettingsText.ago(Self.now.addingTimeInterval(-seconds), now: Self.now) }
        #expect(ago(0) == "just now")
        #expect(ago(59) == "just now")
        #expect(ago(60) == "1 minute ago")
        #expect(ago(5 * 60) == "5 minutes ago")
        #expect(ago(3_599) == "59 minutes ago")
        #expect(ago(3_600) == "1 hour ago")
        #expect(ago(3 * 3_600) == "3 hours ago")
        #expect(ago(23 * 3_600 + 59 * 60) == "23 hours ago")
        #expect(ago(24 * 3_600) == "yesterday")
        #expect(ago(47 * 3_600) == "yesterday")
        #expect(ago(48 * 3_600) == "2 days ago")
        // A clock that ran ahead: the time is in the future.
        #expect(ago(-3_600) == "just now")
    }

    // MARK: Comparing with GitHub

    static func skill(_ name: String, repo: String? = "owner/skills", loads: Int = 3, copy: CopyState? = .current, pinned: Bool = false) -> Skill {
        Skill(name: name, folder: URL(filePath: "/x/\(name)"),
              origin: repo.map { Origin(repo: $0, subpath: "skills/\(name)", installedAt: .now) },
              usesLast90Days: loads, copy: copy, isPinned: pinned)
    }

    static func compared(minutesAgo: Double = 5, problems: [String: String] = [:], stopped: String? = nil) -> CompareFile {
        var file = CompareFile()
        file.checkedAt = now.addingTimeInterval(-minutesAgo * 60)
        file.stopped = stopped
        for (repo, problem) in problems {
            var source = CompareFile.Source()
            source.problem = problem
            file.sources[repo] = source
        }
        return file
    }

    static func summary(_ compare: CompareFile, _ skills: [Skill], usageKnown: Bool = true, dailyOn: Bool = true, samples: Bool = false) -> SettingsText.CompareSummary {
        SettingsText.compareSummary(compare: compare, skills: skills, usageKnown: usageKnown, dailyOn: dailyOn, samples: samples, now: now)
    }

    @Test func neverComparedSaysWhatItSendsAndThatItWillCompareDaily() {
        let result = Self.summary(CompareFile(), [Self.skill("a")])
        #expect(result.lines == [
            "Skill Health can tell you when a skill you use has a newer copy at its source. It sends GitHub the names of the repositories your skills came from, and when you installed them.",
            "After this, Skill Health compares once a day while it's running. You can turn that off.",
        ])
        #expect(result.tone == .plain)
        let samples = Self.summary(CompareFile(), [Self.skill("a")], samples: true)
        #expect(samples.lines[0] == "Skill Health can tell you when a sample skill has a newer copy at its source. It sends GitHub the names of the repositories the sample skills came from, and when they were installed.")
    }

    @Test func pausedSaysWhyAndWhatToDoWhenDailyIsOff() {
        // The stop says what GitHub allows and when it resets; what happens next is the app's to say.
        let stopped = SkillHealthError.rateLimited(resetAt: nil).plainDescription
        #expect(!stopped.contains("finish comparing"))
        let on = Self.summary(Self.compared(stopped: stopped), [Self.skill("a")])
        #expect(on.lines == ["Paused. \(stopped) Skill Health will finish comparing after that."])
        #expect(on.tone == .paused)
        let off = Self.summary(Self.compared(stopped: stopped), [Self.skill("a")], dailyOn: false)
        #expect(off.lines == ["Paused. \(stopped) Choose Compare Again after that."])
        // A reason without a stop gets one, so the next sentence reads as another.
        #expect(Self.summary(Self.compared(stopped: "Try again soon"), [], dailyOn: false).lines == ["Paused. Try again soon. Choose Compare Again after that."])
        // An hour on, the limit has reset, so the stop's reset time isn't repeated.
        #expect(Self.summary(Self.compared(minutesAgo: 90, stopped: stopped), [Self.skill("a")]).lines
                == ["Paused at GitHub's hourly limit, which has reset since. Choose Compare Again to finish."])
        // Paused wins over never compared and over unknown usage.
        var never = CompareFile()
        never.stopped = stopped
        #expect(Self.summary(never, [], usageKnown: false).tone == .paused)
    }

    @Test func nothingNewerNamesHowManySkillsWereLookedAt() {
        let skills = (1...41).map { Self.skill("s\($0)") } + [Self.skill("local", repo: nil), Self.skill("idle", loads: 0)]
        #expect(Self.summary(Self.compared(), skills).lines
                == ["Compared 5 minutes ago. None of the 41 skills you use that have a source has a newer copy."])
        // One skill: no "None of the 1".
        #expect(Self.summary(Self.compared(), [Self.skill("only")]).lines
                == ["Compared 5 minutes ago. The 1 skill you use that has a source has no newer copy."])
        // A thousand and more print with the separator.
        let many = (1...1_200).map { Self.skill("m\($0)") }
        #expect(Self.summary(Self.compared(), many).lines[0].contains("None of the 1,200 skills you use that have a source"))
    }

    /// A newer copy that an update leaves alone (changed here too) is still a newer copy: never
    /// "none has a newer copy", and never offered as an update either.
    @Test func aNewerCopyThatWasChangedHereIsNotCalledNoNewerCopy() {
        let skills = (1...64).map { Self.skill("s\($0)") } + [Self.skill("mine", copy: .changedBoth)]
        #expect(Self.summary(Self.compared(), skills).lines
                == ["Compared 5 minutes ago. None of the 65 skills you use that have a source has a newer copy that's safe to take. 1 has a newer copy, but you changed it on this Mac, so updating would write over your changes."])
        // Alongside copies an update can take: both are said, and only the safe ones get the hand-off.
        let both = [Self.skill("a", copy: .behind), Self.skill("b", copy: .behind), Self.skill("c", copy: .changedBoth), Self.skill("d", copy: .changedBoth)]
        #expect(Self.summary(Self.compared(), both).lines
                == ["Compared 5 minutes ago. 2 skills you use have newer copies. Run /skill-health:update in Claude Code to update them. 2 more have newer copies, but you changed them on this Mac, so updating would write over your changes."])
        // One skill with a source, and it is the held one.
        #expect(Self.summary(Self.compared(), [Self.skill("only", copy: .changedBoth)]).lines
                == ["Compared 5 minutes ago. The 1 skill you use that has a source has a newer copy, but you changed it on this Mac, so updating would write over your changes."])
        // Changed here with the source unchanged has nothing newer, so it isn't mentioned.
        #expect(Self.summary(Self.compared(), [Self.skill("a"), Self.skill("edited", copy: .changedHere)]).lines
                == ["Compared 5 minutes ago. None of the 2 skills you use that have a source has a newer copy."])
        // Some sources unreachable: the held ones are still said for the rest.
        let partial = Self.summary(Self.compared(problems: ["owner/down": "owner/down isn't on GitHub any more, or it's private."]),
                                   [Self.skill("a"), Self.skill("held", copy: .changedBoth), Self.skill("x", repo: "owner/down")]).lines[0]
        #expect(partial.hasSuffix("None of the other 2 has a newer copy that's safe to take. 1 has a newer copy, but you changed it on this Mac, so updating would write over your changes."))
    }

    @Test func noSkillWithASourceSaysThereWasNothingToCompare() {
        #expect(Self.summary(Self.compared(), [Self.skill("local", repo: nil), Self.skill("idle", loads: 0)]).lines
                == ["Compared 5 minutes ago. None of the skills you use has a source, so there was nothing to compare."])
        #expect(Self.summary(Self.compared(), []).lines
                == ["Compared 5 minutes ago. None of the skills you use has a source, so there was nothing to compare."])
    }

    @Test func newerCopiesCountOnlySkillsYouUseAndSayWhatToRun() {
        let one = Self.summary(Self.compared(minutesAgo: 0), [Self.skill("a", copy: .behind), Self.skill("b")])
        #expect(one.lines == ["Compared just now. 1 skill you use has a newer copy. Run /skill-health:update in Claude Code to update it."])
        let skills = (1...23).map { Self.skill("n\($0)", copy: .behind) } + [Self.skill("ok")]
        let many = Self.summary(Self.compared(minutesAgo: 180), skills)
        #expect(many.lines == ["Compared 3 hours ago. 23 skills you use have newer copies. Run /skill-health:update in Claude Code to update them."])
        // Not used, pinned, changed here: none of those is offered, so none is counted.
        let quiet = [Self.skill("idle", loads: 0, copy: .behind), Self.skill("pinned", copy: .behind, pinned: true), Self.skill("mine", copy: .changedHere)]
        #expect(Self.summary(Self.compared(), quiet).lines[0].contains("None of the 2 skills you use that have a source has a newer copy."))
    }

    @Test func someSourcesFailedSaysSoAndOnlyCountsTheRest() {
        let skills = (1...38).map { Self.skill("ok\($0)") }
            + [Self.skill("x1", repo: "gone/one"), Self.skill("x2", repo: "gone/one"), Self.skill("y1", repo: "gone/two"), Self.skill("z1", repo: "gone/three")]
        let problems = ["gone/one": "gone/one isn't on GitHub any more, or it's private.", "gone/two": "x", "gone/three": "y"]
        #expect(Self.summary(Self.compared(problems: problems), skills).lines
                == ["Compared 5 minutes ago. 3 sources couldn't be reached, so their skills weren't compared. None of the other 38 has a newer copy."])
        // One source, and newer copies among the rest.
        let newer = [Self.skill("a", copy: .behind), Self.skill("b", copy: .behind), Self.skill("c"), Self.skill("x", repo: "gone/one")]
        #expect(Self.summary(Self.compared(problems: ["gone/one": "x"]), newer).lines
                == ["Compared 5 minutes ago. 1 source couldn't be reached, so its skills weren't compared. 2 of the others have newer copies. Run /skill-health:update in Claude Code to update them."])
        let one = [Self.skill("a", copy: .behind), Self.skill("b"), Self.skill("x", repo: "gone/one")]
        #expect(Self.summary(Self.compared(problems: ["gone/one": "x"]), one).lines[0].contains("1 of the others has a newer copy. Run /skill-health:update in Claude Code to update it."))
        // The others are one skill.
        let alone = [Self.skill("a"), Self.skill("x", repo: "gone/one")]
        #expect(Self.summary(Self.compared(problems: ["gone/one": "x"]), alone).lines[0].hasSuffix("The other skill has no newer copy."))
        let aloneNewer = [Self.skill("a", copy: .behind), Self.skill("x", repo: "gone/one")]
        #expect(Self.summary(Self.compared(problems: ["gone/one": "x"]), aloneNewer).lines[0].contains("The other skill has a newer copy."))
        // A source that failed for a skill you don't use doesn't count.
        let unused = [Self.skill("a"), Self.skill("x", repo: "gone/one", loads: 0)]
        #expect(Self.summary(Self.compared(problems: ["gone/one": "x"]), unused).lines
                == ["Compared 5 minutes ago. The 1 skill you use that has a source has no newer copy."])
    }

    @Test func whenEverySourceFailedNothingWasCompared() {
        let skills = [Self.skill("a", repo: "gone/one"), Self.skill("b", repo: "gone/two"), Self.skill("c", repo: nil)]
        let problems = ["gone/two": "Skill Health couldn't reach GitHub: The Internet connection appears to be offline.", "gone/one": "gone/one isn't on GitHub any more, or it's private."]
        let result = Self.summary(Self.compared(problems: problems), skills)
        // The first problem by repository name, so the same one is named every time.
        #expect(result.lines == ["Skill Health couldn't reach GitHub, so nothing was compared. gone/one isn't on GitHub any more, or it's private."])
        #expect(result.tone == .warning)
    }

    @Test func whenUsageIsUnknownOnlyWhenItRanIsSaid() {
        let skills = [Self.skill("a", copy: .behind)]
        #expect(Self.summary(Self.compared(minutesAgo: 90), skills, usageKnown: false).lines == ["Compared 1 hour ago."])
        #expect(Self.summary(Self.compared(problems: ["owner/skills": "x"]), skills, usageKnown: false).lines == ["Compared 5 minutes ago."])
    }

    @Test func sampleSkillsGetTheSameShapesWithoutAHandOff() {
        func lines(_ skills: [Skill], problems: [String: String] = [:]) -> [String] {
            Self.summary(Self.compared(problems: problems), skills, samples: true).lines
        }
        #expect(lines([Self.skill("a", copy: .behind)]) == ["Compared 5 minutes ago. 1 sample skill has a newer copy."])
        #expect(lines([Self.skill("a", copy: .behind), Self.skill("b", copy: .behind), Self.skill("c")])
                == ["Compared 5 minutes ago. 2 sample skills have newer copies."])
        #expect(lines([Self.skill("a"), Self.skill("b")])
                == ["Compared 5 minutes ago. None of the 2 sample skills that have a source has a newer copy."])
        #expect(lines([Self.skill("a")]) == ["Compared 5 minutes ago. The 1 sample skill that has a source has no newer copy."])
        #expect(lines([Self.skill("a", repo: nil)]) == ["Compared 5 minutes ago. None of the sample skills has a source, so there was nothing to compare."])
        #expect(lines([Self.skill("a", repo: "gone/one"), Self.skill("b", copy: .behind), Self.skill("c")], problems: ["gone/one": "x"])
                == ["Compared 5 minutes ago. 1 source couldn't be reached, so its skills weren't compared. 1 of the others has a newer copy."])
        // Nothing here ever says to run a command.
        for skills in [[Self.skill("a", copy: .behind)], [Self.skill("a"), Self.skill("b", copy: .behind)]] {
            #expect(!lines(skills).joined().contains("/skill-health:"))
        }
    }

    @Test func aTimeInTheFutureReadsJustNowInTheStatus() {
        let ahead = Self.summary(Self.compared(minutesAgo: -45), [Self.skill("a")])
        #expect(ahead.lines[0].hasPrefix("Compared just now."))
    }

    @Test func theSpokenSummaryIsTheStatusSentenceWhole() {
        let result = Self.summary(CompareFile(), [])
        #expect(result.spoken == result.lines.joined(separator: " "))
        let compared = Self.summary(Self.compared(minutesAgo: 0), [Self.skill("a", copy: .behind)])
        #expect(compared.spoken == "Compared just now. 1 skill you use has a newer copy. Run /skill-health:update in Claude Code to update it.")
    }

    @Test func compareDailyAndComparingHaveTheirOwnWords() {
        #expect(SettingsText.compareDailyNote == "Only while Skill Health is running. It sends GitHub the names of the repositories your skills came from, and when you installed them.")
        #expect(SettingsText.comparing == "Comparing with GitHub…")
    }

    // MARK: On this Mac

    @Test func theMenuBarNoteFollowsTheSwitchAndLaunchAtLogin() {
        #expect(SettingsText.menuBarNote(shown: true, launchesAtLogin: false)
                == "A dot on the icon means a skill you use has a failing or deprecated instruction.")
        #expect(SettingsText.menuBarNote(shown: true, launchesAtLogin: true) == SettingsText.menuBarNote(shown: true, launchesAtLogin: false))
        #expect(SettingsText.menuBarNote(shown: false, launchesAtLogin: false)
                == "Skill Health isn't in the menu bar. Open it from Finder or Spotlight to see this window again.")
        #expect(SettingsText.menuBarNote(shown: false, launchesAtLogin: true)
                == "Skill Health isn't in the menu bar. Open it from Finder or Spotlight to see this window again. This window opens each time Skill Health starts, including at login.")
    }

    @Test func launchAtLoginSaysWhatItDoesAndWhatWentWrong() {
        #expect(SettingsText.launchAtLoginNote == "Keeps the dot and the daily comparison working.")
        #expect(SettingsText.needsApproval == "macOS needs your approval to launch Skill Health at login.")
        #expect(SettingsText.launchAtLoginOn == "Launch at login is on.")
        #expect(SettingsText.launchAtLoginFailed(turningOn: true, "Operation not permitted.")
                == "Skill Health couldn't turn launch at login on: Operation not permitted.")
        #expect(SettingsText.launchAtLoginFailed(turningOn: false, "Operation not permitted.")
                == "Skill Health couldn't turn launch at login off: Operation not permitted.")
        #expect(SettingsText.comeBack
                == "To come back to this window, choose Settings… in Skill Health's menu, or open Skill Health from Finder or Spotlight.")
    }

    @Test func launchAtLoginIsOfferedOnceAfterARealFolderIsReady() {
        #expect(SettingsText.showsLoginOffer(folder: .ready, loginOn: false, answered: false))
        for folder in [SettingsText.Folder.notChosen, .reading, .failed, .sample] {
            #expect(!SettingsText.showsLoginOffer(folder: folder, loginOn: false, answered: false), "\(folder)")
        }
        #expect(!SettingsText.showsLoginOffer(folder: .ready, loginOn: true, answered: false))   // already on
        #expect(!SettingsText.showsLoginOffer(folder: .ready, loginOn: false, answered: true))   // answered, either way
    }

    @Test func theLoginOfferIsAPlainQuestionWithTwoClearAnswers() {
        #expect(SettingsText.loginOfferTitle == "Open Skill Health when you log in?")
        #expect(SettingsText.loginOfferNote
                == "It keeps the dot in the menu bar and the daily comparison working. You can change this later in Settings.")
        #expect(SettingsText.loginOfferAccept == "Open at Login")
        // The window's own bar says Not Now for "close this window": the two must not be confused.
        #expect(SettingsText.loginOfferDecline == "No Thanks")
        #expect(SettingsText.loginOfferDecline != "Not Now")
        // It promises what the switch under On this Mac promises, in the same words.
        #expect(SettingsText.loginOfferNote.contains("the dot"))
        #expect(SettingsText.loginOfferNote.contains("daily comparison"))
        #expect(SettingsText.launchAtLoginNote.contains("daily comparison"))
    }

    // MARK: What shows

    @Test func theBottomBarShowsOnlyUntilARealFolderIsReady() {
        for folder in [SettingsText.Folder.notChosen, .reading, .failed, .sample] {
            #expect(SettingsText.showsNotNow(folder: folder), "\(folder)")
        }
        #expect(!SettingsText.showsNotNow(folder: .ready))
    }

    @Test func sampleSkillsHideThePluginRowAndEveryOtherStateShowsIt() {
        #expect(!SettingsText.showsPluginRow(folder: .sample))
        for folder in [SettingsText.Folder.notChosen, .reading, .failed, .ready] {
            #expect(SettingsText.showsPluginRow(folder: folder), "\(folder)")
        }
    }

    @Test func comparingShowsOnceThereAreSkillsToCompareRealOrSample() {
        #expect(SettingsText.showsCompare(folder: .ready))
        #expect(SettingsText.showsCompare(folder: .sample))
        for folder in [SettingsText.Folder.notChosen, .reading, .failed] {
            #expect(!SettingsText.showsCompare(folder: folder), "\(folder)")
        }
    }

    // MARK: A ready folder's lines

    @Test func aReadyFolderSaysWhatIsInItAndHowMuchOfItIsKnown() {
        let read = SettingsText.readyLines(skills: 1_639, usage: .read(usedPhrase: "at least 79 used in the last 90 days",
                                                                        caveat: "Claude Code has kept sessions only since Aug 25."))
        #expect(read == .init(counts: "1,639 skills, at least 79 used in the last 90 days.", problem: nil,
                              caveat: "Claude Code has kept sessions only since Aug 25."))
        // Exact count: no caveat to carry.
        #expect(SettingsText.readyLines(skills: 3, usage: .read(usedPhrase: "2 used in the last 90 days", caveat: nil))
                == .init(counts: "3 skills, 2 used in the last 90 days.", problem: nil, caveat: nil))
        #expect(SettingsText.readyLines(skills: 1, usage: .read(usedPhrase: "1 used in the last 90 days", caveat: nil)).counts
                == "1 skill, 1 used in the last 90 days.")
    }

    @Test func aFolderWithNoSkillsHasNothingForACaveatToQualify() {
        let none = SettingsText.readyLines(skills: 0, usage: .read(usedPhrase: "at least 0 used in the last 90 days", caveat: "There are no Claude Code sessions in this folder yet."))
        #expect(none == .init(counts: "No skills in this folder.", problem: nil, caveat: nil))
    }

    @Test func whileUsageIsBeingReadTheCountsSaySo() {
        #expect(SettingsText.readyLines(skills: 12, usage: .reading)
                == .init(counts: "12 skills. Reading which ones you use…", problem: nil, caveat: nil))
        #expect(SettingsText.readyLines(skills: 1, usage: .reading).counts == "1 skill. Reading which ones you use…")
    }

    @Test func unreadableUsageKeepsTheSkillCountAndNamesTheProblemWithTheReasonLast() {
        let failed = SettingsText.readyLines(skills: 12, usage: .failed("No permission."))
        #expect(failed == .init(counts: "12 skills.", problem: "Skill Health couldn't read which skills you use: No permission.", caveat: nil))
        // A caveat from an earlier read is not carried over a failed one.
        #expect(SettingsText.readyLines(skills: 0, usage: .failed("x")).counts == "No skills in this folder.")
    }

    @Test func theWatcherNoteIsInformationNotAFault() {
        #expect(SettingsText.watcherNote
                == "Skill Health can't watch this folder for changes, so it reads it again when you come back to Skill Health and once an hour.")
    }

    // MARK: Needs attention

    @Test func needsAttentionListsEachFaultOnceInOrderAndNeverAnEmptyOne() {
        #expect(SettingsText.problems([nil, nil]) == [])
        #expect(SettingsText.problems(["a", nil, "b"]) == ["a", "b"])
        #expect(SettingsText.problems(["a", "b", "a"]) == ["a", "b"])
        #expect(SettingsText.problems(["  ", "", " a \n"]) == ["a"])
    }

    // MARK: The plugin's control

    @Test func eachPluginStateHasOneControlOrStatusInItsTrailingSlot() {
        func control(_ plugin: PluginState, ready: Bool = true) -> SettingsText.PluginStep.Control {
            SettingsText.pluginStep(folderReady: ready, plugin: plugin).control
        }
        #expect(control(.notInstalled) == .copyCommand)
        #expect(control(.older) == .copyCommand)
        #expect(control(.installedNotConnected) == .waiting)
        #expect(control(.connected) == .connected)
        for plugin in [PluginState.notInstalled, .installedNotConnected, .connected, .older] {
            #expect(control(plugin, ready: false) == .none, "\(plugin)")
        }
    }

    @Test func aCopyControlGoesWithACommandAndNothingElseDoes() {
        for plugin in [PluginState.notInstalled, .installedNotConnected, .connected, .older] {
            let step = SettingsText.pluginStep(folderReady: true, plugin: plugin)
            #expect((step.control == .copyCommand) == (step.command != .none), "\(plugin)")
            // The sentence after the command block is for a step that has a command.
            #expect((step.then != nil) == (step.command != .none), "\(plugin)")
        }
    }

    // MARK: What App Review is told

    @Test func theReviewNotesDescribeWhatTheSampleSkillsActuallyShowAndFitTheField() throws {
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repo.appending(path: "docs/app-store/review-notes.md"), encoding: .utf8)
        let note = try #require(text.components(separatedBy: "\n---\n").dropFirst().first)
        #expect(note.utf8.count <= 4_000)

        // The first header of the sample menu, and the item under it, as the notes say.
        let menu = MenuModel(MenuInput(skills: [.init(name: "supabase-basics", failing: 1, deprecated: 0, loads: 5)], sampleMode: true))
        #expect(menu.groups.first?.header == "These are sample skills")
        #expect(menu.groups.first?.items.first?.title == "supabase-basics")
        #expect(note.contains(#"says "These are sample skills""#))
        #expect(note.contains(#"under it "supabase-basics" opens that skill's page"#))

        // And the sentence Settings says after Compare Now on the samples.
        let samples = [Self.skill("supabase-basics", copy: .current), Self.skill("python-env", copy: .behind), Self.skill("git-hygiene", loads: 0)]
        #expect(Self.summary(Self.compared(minutesAgo: 0), samples, samples: true).lines == ["Compared just now. 1 sample skill has a newer copy."])
        #expect(note.contains(#""1 sample skill has a newer copy""#))
    }

    // MARK: The words never use what the spec bans

    @Test func noPersonFacingLineUsesABannedWordOrADash() {
        var all = [purpose, SettingsText.folderNotChosen, SettingsText.folderReading, SettingsText.folderSample, SettingsText.commandCopied,
                   SettingsText.comeBack, SettingsText.needsApproval, SettingsText.compareDailyNote, SettingsText.launchAtLoginNote,
                   SettingsText.watcherNote, SettingsText.launchAtLoginOn, SettingsText.comparing]
        for folder in [SettingsText.Folder.notChosen, .reading, .failed, .sample, .ready] {
            for plugin in [PluginState.notInstalled, .installedNotConnected, .connected, .older] {
                for shown in [true, false] { all += SettingsText.topLines(folder: folder, plugin: plugin, menuBarShown: shown) }
                let step = SettingsText.pluginStep(folderReady: folder == .ready, plugin: plugin)
                all += [step.line] + (step.then.map { [$0] } ?? [])
            }
        }
        for line in all {
            for banned in ["audit", "patch", "!", " - ", "—", "–", "UI/UX"] { #expect(!line.contains(banned), "\(line) says \(banned)") }
        }
    }
}
