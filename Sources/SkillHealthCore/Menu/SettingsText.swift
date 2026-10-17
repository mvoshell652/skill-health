import Foundation

/// The words of the settings window (also the first-run setup), decided here from plain values so a
/// test can read every state. The views draw what this says and add nothing. The same rules as the
/// menu: the spec's word list, sentence case for statements, Title Case for buttons, no dashes, and
/// none, one and many in every count.
public enum SettingsText {
    /// Where the Claude folder stands. Sample skills are a state of their own: a folder that is
    /// ready, but isn't the person's.
    public enum Folder: Sendable, Equatable {
        case notChosen
        case reading
        case failed
        case sample
        case ready
    }

    // MARK: What shows

    /// The bottom bar's Not Now: only while there is still something to set up. Once a real folder
    /// is ready the settings apply as they change, so nothing closes the window but the window.
    public static func showsNotNow(folder: Folder) -> Bool { folder != .ready }

    /// The plugin is the person's own Claude Code's: sample skills never reach it, so its row is hidden.
    public static func showsPluginRow(folder: Folder) -> Bool { folder != .sample }

    /// Comparing needs skills to compare, real or sample.
    public static func showsCompare(folder: Folder) -> Bool { folder == .ready || folder == .sample }

    // MARK: The top line

    /// The plain lines above the cards: what Skill Health is for, then the next step, or, once everything
    /// is set up, that it is. Each line is its own paragraph.
    public static func topLines(folder: Folder, plugin: PluginState, menuBarShown: Bool) -> [String] {
        let purpose = "Skill Health tells you when a skill you use has a failing or deprecated instruction. You fix it in Claude Code, with the Skill Health plugin."
        switch folder {
        case .notChosen, .failed:
            return [purpose, "Next: choose your Claude folder."]
        case .reading:
            return [purpose]
        case .sample:
            return ["These are sample skills, so you can try Skill Health without Claude Code.",
                    "Next: choose your Claude folder to see your own."]
        case .ready:
            switch plugin {
            case .notInstalled: return ["Next: install the Claude Code plugin."]
            case .installedNotConnected: return ["Next: start a Claude Code session to connect the plugin."]
            case .older: return ["Next: update the Claude Code plugin."]
            case .connected:
                return ["Skill Health is set up.",
                        menuBarShown
                            ? "It shows a dot in the menu bar when a skill you use needs a fix."
                            : "The icon is hidden. The plugin's note at the start of a Claude Code session tells you when a skill you use needs a fix."]
            }
        }
    }

    // MARK: The Claude folder

    public static let folderNotChosen = "To see which skills you use, Skill Health reads this hidden folder. In the next window, click Allow."
    public static let folderReading = "Reading your skills…"
    public static let folderSample = "Using sample skills"

    /// The reason comes last, since the system's can be long.
    public static func folderFailed(_ why: String) -> String {
        reasoned("Skill Health couldn't read your Claude folder", why)
    }

    public static func usageFailed(_ why: String) -> String {
        reasoned("Skill Health couldn't read which skills you use", why)
    }

    /// "1,639 skills, at least 79 used in the last 90 days." `usedPhrase` is the usage report's own
    /// words (`UsageReport.usedPhrase`), nil until usage is read.
    public static func folderCounts(skills: Int, usedPhrase: String?) -> String {
        guard skills > 0 else { return "No skills in this folder." }
        let count = skills == 1 ? "1 skill" : "\(NumberText.count(skills)) skills"
        guard let usedPhrase else { return count + "." }
        return "\(count), \(usedPhrase)."
    }

    /// The counts line while usage is being read.
    public static func folderCountsReading(skills: Int) -> String {
        guard skills > 0 else { return "No skills in this folder." }
        return folderCounts(skills: skills, usedPhrase: nil) + " Reading which ones you use…"
    }

    /// What usage reading has made of the folder, for the lines under a ready folder.
    public enum UsageLine: Sendable, Equatable {
        case reading
        /// `usedPhrase` is `UsageReport.usedPhrase`; the caveat is `coverageCaveat`.
        case read(usedPhrase: String, caveat: String?)
        case failed(String)
    }

    /// The lines under a ready folder's path: what is in it, and what is wrong or partial about
    /// knowing which skills are used. A failed read keeps the skill count (that part is known).
    public struct ReadyLines: Sendable, Equatable {
        public var counts: String
        /// Gets a warning sign. Only when usage couldn't be read.
        public var problem: String?
        /// Only while the count of skills you use is a lower bound.
        public var caveat: String?
    }

    public static func readyLines(skills: Int, usage: UsageLine) -> ReadyLines {
        switch usage {
        case .reading:
            return ReadyLines(counts: folderCountsReading(skills: skills))
        case .read(let usedPhrase, let caveat):
            // With no skills there is nothing to be a lower bound of.
            return ReadyLines(counts: folderCounts(skills: skills, usedPhrase: usedPhrase), caveat: skills > 0 ? caveat : nil)
        case .failed(let why):
            return ReadyLines(counts: folderCounts(skills: skills, usedPhrase: nil), problem: usageFailed(why))
        }
    }

    /// Information, not a fault: the window still works, it just reads again less often.
    public static let watcherNote = "Skill Health can't watch this folder for changes, so it reads it again when you come back to Skill Health and once an hour."

    /// The faults to list under Needs attention: each once, in the order given, none empty.
    public static func problems(_ found: [String?]) -> [String] {
        var seen = Set<String>()
        return found.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The path as a person types it: the home folder abbreviated to `~`, the open panel's trailing
    /// slash gone. `home` is the real home folder, never the sandbox container.
    public static func displayPath(_ path: String, home: String) -> String {
        func trimmed(_ text: String) -> String { text.count > 1 && text.hasSuffix("/") ? String(text.dropLast()) : text }
        let path = trimmed(path), home = trimmed(home)
        if path == home { return "~" }
        if home != "/", path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Why the count of skills you use is a lower bound, in one sentence, only while it is one.
    /// The date is the person's own day, in English like the rest of the window.
    public static func coverageCaveat(_ report: UsageReport, now: Date = .now, timeZone: TimeZone = .current) -> String? {
        guard !report.coversWindow else { return nil }
        guard let since = report.completeSince else { return "There are no Claude Code sessions in this folder yet." }
        return "Claude Code has kept sessions only since \(DayLabel.short(since, now: now, timeZone: timeZone))."
    }

    // MARK: The Claude Code plugin

    /// What the plugin step says for each state. The command itself belongs to the app, which knows
    /// where the plugin is published; this says only which one is wanted.
    /// The plugin's commands, shown on a line of their own once it is connected: run together in a
    /// sentence, a line break can fall inside one ("/ skill-health:undo").
    public static let pluginCommands = [ClaudeCodeCommand.check, ClaudeCodeCommand.fixAll, ClaudeCodeCommand.update, ClaudeCodeCommand.undo]

    public struct PluginStep: Equatable, Sendable {
        public enum Command: Equatable, Sendable {
            case none
            case install
            case update
        }

        /// The one control in the row's trailing slot, or the status standing in for one.
        public enum Control: Equatable, Sendable {
            case none
            case copyCommand
            /// Installed; the next Claude Code session connects it.
            case waiting
            /// The only green check in the window.
            case connected
        }

        public var line: String
        /// The line is a problem (the plugin is older), so it carries a warning sign.
        public var warns: Bool
        public var command: Command
        /// Under the command block.
        public var then: String?
        public var control: Control
    }

    public static func pluginStep(folderReady: Bool, plugin: PluginState) -> PluginStep {
        guard folderReady else {
            return PluginStep(line: "Skill Health looks for the plugin once it can read your Claude folder.", warns: false, command: .none, control: .none)
        }
        switch plugin {
        case .notInstalled:
            return PluginStep(line: "To fix, check and update skills in Claude Code, install the plugin. Run this in Terminal:",
                              warns: false, command: .install, then: "Then start a Claude Code session to connect it.", control: .copyCommand)
        case .installedNotConnected:
            return PluginStep(line: "Installed. Start a Claude Code session to connect it.", warns: false, command: .none, control: .waiting)
        case .connected:
            return PluginStep(line: "Run these in Claude Code:", warns: false, command: .none, control: .connected)
        case .older:
            return PluginStep(line: "Some menu items need a newer plugin. To update it, run this in Terminal:",
                              warns: true, command: .update, then: "Then start a new Claude Code session.", control: .copyCommand)
        }
    }

    /// Only while menu items can hand off to Claude Code and nothing can open it yet: no Claude app,
    /// and Claude Code hasn't registered its terminal link.
    public static func linkNote(plugin: PluginState, canOpen: Bool) -> String? {
        guard plugin.canHandOff, !canOpen else { return nil }
        return "Until you've sent Claude Code one prompt, menu items copy their command instead of opening Claude Code."
    }

    // MARK: Where commands open

    /// The choice shows only when it is one: menu items can hand off, and both places are on this Mac.
    public static func showsOpenIn(plugin: PluginState, available: Set<ClaudeCodeCommand.Destination>) -> Bool {
        plugin.canHandOff && available.count > 1
    }

    public static let openInTitle = "Open commands in"

    /// The choice's name in the pop-up menu.
    public static func destinationName(_ destination: ClaudeCodeCommand.Destination) -> String {
        switch destination {
        case .claudeApp: "Claude App"
        case .terminal: "Terminal"
        }
    }

    /// The line under the title: what the chosen place does.
    public static func openInNote(_ destination: ClaudeCodeCommand.Destination) -> String {
        switch destination {
        case .claudeApp: "A new Code session in the Claude app, with the command typed in. The app asks each time before it uses Skill Health's folder."
        case .terminal: "A new window in the terminal you last used Claude Code in, with the command typed in."
        }
    }

    public static let commandCopied = "Command copied. Paste it in Terminal and press Return."

    /// Said while the window is open, when the plugin moves on a step.
    public static func pluginAnnouncement(from old: PluginState, to new: PluginState) -> String? {
        guard old != new else { return nil }
        switch new {
        case .installedNotConnected: return "Claude Code plugin installed. Start a Claude Code session to connect it."
        case .connected: return "Claude Code plugin connected."
        case .notInstalled, .older: return nil
        }
    }

    // MARK: Comparing with GitHub

    /// What the status line under Compare with GitHub says. Each line is its own paragraph.
    public struct CompareSummary: Equatable, Sendable {
        public enum Tone: Equatable, Sendable {
            case plain
            /// A comparison GitHub's limit stopped.
            case paused
            /// Nothing could be compared.
            case warning
        }

        public var lines: [String]
        public var tone: Tone

        /// All of it as one sentence run, for VoiceOver.
        public var spoken: String { lines.joined(separator: " ") }
    }

    /// What the last comparison actually established, from the file it left, the skills and whether
    /// usage is known (without it, which skills you use is unknown, so only when it ran is said).
    public static func compareSummary(compare: CompareFile, skills: [Skill], usageKnown: Bool, dailyOn: Bool,
                                      samples: Bool, now: Date) -> CompareSummary {
        let noun = samples ? "sample skills" : "skills you use"
        if let stopped = compare.stopped {
            // The stop names a reset time, which is past an hour later.
            if let at = compare.checkedAt, now.timeIntervalSince(at) > 60 * 60 {
                return CompareSummary(lines: ["Paused at GitHub's hourly limit, which has reset since. Choose Compare Again to finish."], tone: .paused)
            }
            let again = dailyOn ? " Skill Health will finish comparing after that." : " Choose Compare Again after that."
            return CompareSummary(lines: ["Paused. " + sentence(stopped) + again], tone: .paused)
        }
        guard let checkedAt = compare.checkedAt else {
            return CompareSummary(lines: [
                "Skill Health can tell you when \(samples ? "a sample skill" : "a skill you use") has a newer copy at its source. It sends GitHub the names of the repositories \(samples ? "the sample skills" : "your skills") came from, and when \(samples ? "they were installed" : "you installed them").",
                "After this, Skill Health compares once a day while it's running. You can turn that off.",
            ], tone: .plain)
        }
        let compared = "Compared \(ago(checkedAt, now: now))."
        guard usageKnown else { return CompareSummary(lines: [compared], tone: .plain) }

        // The skills a comparison is about: those you use that came from somewhere, by where.
        let sourced = skills.compactMap { skill in skill.isUsed ? skill.origin.map { (skill: skill, repo: $0.repo) } : nil }
        let problems = Dictionary(sourced.compactMap { entry in
            compare.sources[entry.repo]?.problem.map { (entry.repo, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let reached = sourced.filter { problems[$0.repo] == nil }
        let newer = reached.count { $0.skill.isSafeUpdate }
        // A newer copy that is left alone because it was changed here too: it is a newer copy, so
        // "none has one" would be untrue, but it isn't one an update can take.
        let held = reached.count { $0.skill.copy == .changedBoth }

        if !sourced.isEmpty, reached.isEmpty {
            // Sorted by repository, so the same problem is named every time.
            let first = problems.sorted { $0.key < $1.key }[0].value
            return CompareSummary(lines: ["Skill Health couldn't reach GitHub, so nothing was compared. " + sentence(first)], tone: .warning)
        }
        if !problems.isEmpty {
            let count = problems.count
            let unreached = count == 1 ? "1 source couldn't be reached, so its skills weren't compared."
                : "\(NumberText.count(count)) sources couldn't be reached, so their skills weren't compared."
            let others = reached.count
            let rest: String
            switch (newer, others) {
            case (0, 1) where held == 1: rest = "The other \(samples ? "sample skill" : "skill") has a newer copy, but you changed it on this Mac, so updating would write over your changes."
            case (0, 1): rest = "The other \(samples ? "sample skill" : "skill") has no newer copy."
            case (0, _) where held > 0: rest = "None of the other \(NumberText.count(others)) has a newer copy that's safe to take."
            case (0, _): rest = "None of the other \(NumberText.count(others)) has a newer copy."
            case (1, 1): rest = "The other \(samples ? "sample skill" : "skill") has a newer copy."
            case (1, _): rest = "1 of the others has a newer copy."
            default: rest = "\(NumberText.count(newer)) of the others have newer copies."
            }
            let alone = newer == 0 && others == 1 && held == 1
            return CompareSummary(lines: ["\(compared) \(unreached) \(rest)" + handOff(newer: newer, samples: samples)
                                          + (alone ? "" : heldNote(held, alongside: newer))], tone: .plain)
        }
        let found: String
        switch (newer, sourced.count) {
        case (_, 0): found = "None of the \(noun) has a source, so there was nothing to compare."
        case (0, 1) where held == 1:
            found = "The 1 \(samples ? "sample skill" : "skill you use") that has a source has a newer copy, but you changed it on this Mac, so updating would write over your changes."
        case (0, 1): found = "The 1 \(samples ? "sample skill" : "skill you use") that has a source has no newer copy."
        case (0, let total) where held > 0:
            found = "None of the \(NumberText.count(total)) \(noun) that have a source has a newer copy that's safe to take.\(heldNote(held, alongside: 0))"
        case (0, let total): found = "None of the \(NumberText.count(total)) \(noun) that have a source has a newer copy."
        case (1, _): found = "1 \(samples ? "sample skill has" : "skill you use has") a newer copy.\(handOff(newer: 1, samples: samples))\(heldNote(held, alongside: 1))"
        default: found = "\(NumberText.count(newer)) \(samples ? "sample skills have" : "skills you use have") newer copies.\(handOff(newer: newer, samples: samples))\(heldNote(held, alongside: newer))"
        }
        return CompareSummary(lines: ["\(compared) \(found)"], tone: .plain)
    }

    /// Newer copies an update leaves alone because they were changed on this Mac as well.
    private static func heldNote(_ held: Int, alongside newer: Int) -> String {
        guard held > 0 else { return "" }
        let more = newer > 0 ? " more" : ""
        return held == 1 ? " 1\(more) has a newer copy, but you changed it on this Mac, so updating would write over your changes."
            : " \(NumberText.count(held))\(more) have newer copies, but you changed them on this Mac, so updating would write over your changes."
    }

    /// What to do about newer copies. Sample skills never hand off to Claude Code.
    private static func handOff(newer: Int, samples: Bool) -> String {
        guard newer > 0, !samples else { return "" }
        return " Run \(ClaudeCodeCommand.update) in Claude Code to update \(newer == 1 ? "it" : "them")."
    }

    /// "just now", "5 minutes ago", "3 hours ago", "yesterday", "4 days ago". A time in the future
    /// (a clock set wrong) reads "just now". In English whatever the Mac's region, like the words
    /// around it.
    public static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(max(now.timeIntervalSince(date), 0) / 60)
        switch minutes {
        case 0: return "just now"
        case 1: return "1 minute ago"
        case 2..<60: return "\(minutes) minutes ago"
        default:
            let hours = minutes / 60
            if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
            let days = hours / 24
            return days == 1 ? "yesterday" : "\(days) days ago"
        }
    }

    public static let compareDailyNote = "Only while Skill Health is running. It sends GitHub the names of the repositories your skills came from, and when you installed them."
    public static let comparing = "Comparing with GitHub…"

    // MARK: On this Mac

    /// Under "Show Skill Health in the menu bar", for each state of the switch. With the icon hidden and
    /// Launch at login on, the window is also what opens at every start.
    public static func menuBarNote(shown: Bool, launchesAtLogin: Bool) -> String {
        if shown { return "A dot on the icon means a skill you use has a failing or deprecated instruction." }
        let hidden = "Skill Health isn't in the menu bar. Open it from Finder or Spotlight to see this window again."
        return launchesAtLogin ? hidden + " This window opens each time Skill Health starts, including at login." : hidden
    }

    public static let launchAtLoginNote = "Keeps the dot and the daily comparison working."

    // MARK: Launching at login, offered once

    /// Offered once, right after a real folder is ready, so the person is asked at the moment Skill Health becomes
    /// useful and not left to find a switch at the bottom of Settings. Never for the sample skills (a demo
    /// installs nothing), never while it is already on, and never again once they have answered.
    public static func showsLoginOffer(folder: Folder, loginOn: Bool, answered: Bool) -> Bool {
        folder == .ready && !loginOn && !answered
    }

    public static let loginOfferTitle = "Open Skill Health when you log in?"
    public static let loginOfferNote = "It keeps the dot in the menu bar and the daily comparison working. You can change this later in Settings."
    public static let loginOfferAccept = "Open at Login"
    /// Not "Not Now": the window's own bar uses that for "close this window".
    public static let loginOfferDecline = "No Thanks"
    public static let needsApproval = "macOS needs your approval to launch Skill Health at login."
    public static let launchAtLoginOn = "Launch at login is on."

    public static func launchAtLoginFailed(turningOn: Bool, _ why: String) -> String {
        reasoned("Skill Health couldn't turn launch at login \(turningOn ? "on" : "off")", why)
    }

    public static let comeBack = "To come back to this window, choose Settings… in Skill Health's menu, or open Skill Health from Finder or Spotlight."

    // MARK: Pieces

    /// "<what>: <why>", with the reason last and no colon when there is none.
    private static func reasoned(_ what: String, _ why: String) -> String {
        let why = why.trimmingCharacters(in: .whitespacesAndNewlines)
        return why.isEmpty ? what + "." : "\(what): \(why)"
    }

    /// A sentence ends in a stop, so what follows it reads as another.
    private static func sentence(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = text.last else { return text }
        return ".!?".contains(last) ? text : text + "."
    }
}
