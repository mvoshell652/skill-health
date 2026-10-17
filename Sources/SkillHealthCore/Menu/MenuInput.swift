import Foundation

/// Everything the menu bar menu and its icon depend on, gathered by the app and handed to
/// `MenuModel`, which turns it into words. A plain value with no SwiftUI and no file access, so
/// every state the menu can be in is built and checked in a test.
public struct MenuInput: Equatable, Sendable {
    /// Where the Claude folder stands.
    public enum Load: Equatable, Sendable {
        case needsFolder
        case loading
        case failed
        case loaded
    }

    /// Whether Skill Health knows which skills the person loads. Reading covers "not started" too: the
    /// menu says the same thing for both.
    public enum Usage: Equatable, Sendable {
        case reading
        case failed
        case read
    }

    /// One skill you use with at least one open failing or deprecated instruction.
    /// A skill named under a header, with how often it was used.
    public struct Listed: Equatable, Sendable {
        public var name: String
        /// Loads in the last 90 days.
        public var loads: Int

        public init(name: String, loads: Int) {
            self.name = name
            self.loads = loads
        }
    }

    /// A skill due for a check, and why.
    public struct Due: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            case neverChecked
            /// Its files changed since the check on this date.
            case changedSince(Date)
            /// Unchanged, but last checked on this date, over 90 days ago.
            case checkedLongAgo(Date)
        }

        public var name: String
        public var loads: Int
        public var reason: Reason

        public init(name: String, loads: Int, reason: Reason) {
            self.name = name
            self.loads = loads
            self.reason = reason
        }
    }

    public struct SkillIssues: Equatable, Sendable {
        public var name: String
        public var failing: Int
        public var deprecated: Int
        /// Loads in the last 90 days.
        public var loads: Int

        public init(name: String, failing: Int, deprecated: Int, loads: Int) {
            self.name = name
            self.failing = failing
            self.deprecated = deprecated
            self.loads = loads
        }
    }

    public var load: Load
    public var usage: Usage
    /// True when the kept sessions reach back over the whole 90 days, so a count of skills you use is
    /// exact. Otherwise it is "at least".
    public var usageCoversWindow: Bool
    /// Installed skills loaded in the last 90 days.
    public var usedCount: Int
    /// Of those, the ones that have been checked (by a check, or by a shared correction).
    public var checkedUsedCount: Int
    /// The oldest check among them, which is how far back "all checked" reaches.
    public var oldestCheck: Date?
    /// Skills you use with an open failing or deprecated instruction. All of them: the menu lists
    /// five and counts every one.
    public var skills: [SkillIssues]
    /// Failing instructions in skills you use that the person set aside. They are still failing, so
    /// no line may say "none failing" while there are any.
    public var setAsideFailing: Int
    /// findings.json exists but couldn't be read: nothing about what's been checked is known.
    public var findingsUnreadable: Bool
    /// Problems with findings.json or decisions.json, each already in words.
    public var problems: [String]
    /// Skills you use that are behind their source and unchanged on this Mac.
    public var newerCopies: Int
    /// Those skills, by name, most used first.
    public var newer: [Listed]
    /// Skills you use that are due for a check: never checked, changed since their check, or checked
    /// over 90 days ago (`Coverage`). Most used first.
    public var due: [Due]
    public var plugin: PluginState
    /// Whether a command can open in Claude Code here: the Claude app is installed, or Claude Code
    /// has registered its terminal link (after the person's first prompt). Otherwise items copy it.
    public var canOpenClaudeCode: Bool
    /// True while the skills shown are samples (the sample library, or a debug launch's injected
    /// findings). Samples never hand anything to Claude Code.
    public var sampleMode: Bool
    /// When a check was last opened from the menu, until it is forgotten.
    public var checkOpenedAt: Date?
    /// True once findings.json has changed since that check was opened: its results landed.
    public var findingsChangedSinceCheck: Bool
    public var now: Date
    public var timeZone: TimeZone

    public init(load: Load = .loaded, usage: Usage = .read, usageCoversWindow: Bool = true,
                usedCount: Int = 0, checkedUsedCount: Int = 0, oldestCheck: Date? = nil,
                skills: [SkillIssues] = [], setAsideFailing: Int = 0, findingsUnreadable: Bool = false,
                problems: [String] = [], newerCopies: Int = 0, newer: [Listed] = [], due: [Due] = [], plugin: PluginState = .connected,
                canOpenClaudeCode: Bool = true, sampleMode: Bool = false, checkOpenedAt: Date? = nil,
                findingsChangedSinceCheck: Bool = false, now: Date = .now, timeZone: TimeZone = .current) {
        self.load = load
        self.usage = usage
        self.usageCoversWindow = usageCoversWindow
        self.usedCount = usedCount
        self.checkedUsedCount = checkedUsedCount
        self.oldestCheck = oldestCheck
        self.skills = skills
        self.setAsideFailing = setAsideFailing
        self.findingsUnreadable = findingsUnreadable
        self.problems = problems
        self.newerCopies = newerCopies
        self.newer = newer
        self.due = due
        self.plugin = plugin
        self.canOpenClaudeCode = canOpenClaudeCode
        self.sampleMode = sampleMode
        self.checkOpenedAt = checkOpenedAt
        self.findingsChangedSinceCheck = findingsChangedSinceCheck
        self.now = now
        self.timeZone = timeZone
    }
}
