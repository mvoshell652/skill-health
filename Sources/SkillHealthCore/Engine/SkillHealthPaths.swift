import Foundation

/// Where Skill Health keeps its own state: outside any plugin cache, which Claude Code replaces on update.
public struct SkillHealthPaths: Sendable {
    public let claudeHome: URL
    public let skills: URL
    public let home: URL

    /// No default: inside the sandbox the home directory APIs return the app's container, so
    /// every caller names the folder, the app from its granted bookmark.
    public init(claudeHome: URL) {
        self.claudeHome = claudeHome
        skills = claudeHome.appending(path: "skills")
        home = claudeHome.appending(path: "skill-health")
    }

    /// The account's real ~/.claude, read from the password database, which the sandbox
    /// doesn't redirect. Only a default to offer; access still comes from the person's grant.
    public static var defaultClaudeHome: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return URL(filePath: home).appending(path: ".claude")
    }

    public var status: URL { home.appending(path: "status.json") }
    /// A stamp for the last `skill-health refresh`, touched even when nothing changed. The plugin's
    /// session hook reads it, with status.json, to know whether another refresh is due.
    public var refreshed: URL { home.appending(path: ".refreshed") }
    public var findings: URL { home.appending(path: "findings.json") }
    public var backups: URL { home.appending(path: "backups") }
    /// What the plugin's SessionStart hook prints, rendered by the app (M2): with the person's
    /// note, and without it. The hook only chooses between them.
    public var hookNote: URL { home.appending(path: "hook-note.json") }
    public var hookQuiet: URL { home.appending(path: "hook-quiet.json") }
    /// Touched by the hook each time it runs: how the app knows Claude Code reads its notes.
    public var hookRead: URL { home.appending(path: "hook-read") }
    public var settings: URL { home.appending(path: "settings.json") }
    public var compare: URL { home.appending(path: "compare.json") }
    public var updateRecords: URL { home.appending(path: "updates.json") }
    public var decisions: URL { home.appending(path: "decisions.json") }
    public var auditPlan: URL { home.appending(path: "audit-plan.json") }
    /// Written by the plugin's SessionStart hook each run: its version and when it ran, so the app
    /// knows the plugin is connected and whether it is new enough for the menu's commands.
    public var pluginHandshake: URL { home.appending(path: "plugin.json") }
    /// Changes the plugin's tool has prepared and the person hasn't approved yet, one file each
    /// (plus a folder of staged downloads for an update). Only the tool and its gate hook read them.
    public var pending: URL { home.appending(path: "pending") }
    /// The cross-process write lock: a directory, made atomically (FileLock).
    public var lock: URL { home.appending(path: ".lock") }
}
