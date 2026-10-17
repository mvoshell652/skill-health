import Foundation

/// The commands the menu opens in Claude Code, and how it opens them. Two links, one per place a
/// command can open, both typing the command in without sending it:
///   - the Claude app's `claude://code/new?q=…&folder=…` starts a new Code session;
///   - Claude Code's own `claude-cli://open?q=…&cwd=…` starts a new terminal session.
/// Either starts in an empty folder of Skill Health's own (`workspace`), so Claude Code asks about
/// trusting one folder, once, and a session that may edit files without asking in its working
/// folder is never working in the folder that holds Skill Health's pending changes.
///
/// Never the browser: Claude Code on the web runs in the cloud, on a copy of a GitHub repository,
/// so it can't read or change the skills on this Mac.
public enum ClaudeCodeCommand {
    public static let check = "/skill-health:check"
    public static let fixAll = "/skill-health:fix"
    public static let update = "/skill-health:update"
    /// Not opened from the menu: the setup window names it among what the plugin runs.
    public static let undo = "/skill-health:undo"

    /// `/skill-health:fix <skill>`, or nil when the name isn't one that may go into a command.
    public static func fix(skill: String) -> String? {
        SkillName.isValid(skill) ? "\(fixAll) \(skill)" : nil
    }

    /// `/skill-health:check <skill>`, or nil when the name isn't one that may go into a command.
    public static func check(skill: String) -> String? {
        SkillName.isValid(skill) ? "\(check) \(skill)" : nil
    }

    /// True for `/skill-health:check` and `/skill-health:check <skill>`: a check was opened.
    public static func isCheck(_ command: String) -> Bool {
        command == check || command.hasPrefix(check + " ")
    }

    // MARK: Where a command opens

    /// Where a command can open, in the order Skill Health tries them: the Claude app, which needs no
    /// permission, then a terminal, which Claude Code drives and macOS may ask about.
    public enum Destination: String, CaseIterable, Sendable {
        /// A new Code session in the Claude app.
        case claudeApp
        /// A new window in a terminal: Claude Code picks the one it last ran in.
        case terminal
    }

    /// The Claude app's bundle identifier: `claude://` goes to the Claude app only when the app
    /// that handles it is one of these.
    public static let claudeAppBundleID = "com.anthropic.claudefordesktop"

    /// What a command opens in: the person's choice when it's on this Mac, otherwise the first that is.
    /// Nil when neither is, and the command is copied instead.
    public static func destination(preferring preferred: Destination, available: Set<Destination>) -> Destination? {
        available.contains(preferred) ? preferred : Destination.allCases.first(where: available.contains)
    }

    /// The link alone, which is what asks the system whether any app handles it.
    public static func probe(_ destination: Destination) -> URL? {
        switch destination {
        case .claudeApp: URL(string: "claude://code/new")
        case .terminal: URL(string: "claude-cli://open")
        }
    }

    /// The link that opens `command` in Claude Code, starting in `folder` (the workspace).
    /// Everything but unreserved characters is percent-encoded, so a space, a slash or an `&` can't
    /// end the value early. Nil for a command with control characters in it.
    public static func url(for command: String, to destination: Destination, in folder: URL) -> URL? {
        guard !command.isEmpty, !command.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        var path = folder.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        guard let q = encode(command), let folder = encode(path) else { return nil }
        switch destination {
        case .claudeApp: return URL(string: "claude://code/new?q=\(q)&folder=\(folder)")
        case .terminal: return URL(string: "claude-cli://open?q=\(q)&cwd=\(folder)")
        }
    }

    /// The folder Claude Code is opened in: `workspace` inside Skill Health's own folder (~/.claude/skill-health).
    /// Never Skill Health's folder itself: its pending plans sit there, and in a session's working folder
    /// acceptEdits mode lets file edits through without a prompt.
    public static func workspace(in skillHealthFolder: URL) -> URL {
        skillHealthFolder.appending(path: "workspace", directoryHint: .isDirectory)
    }

    /// What the workspace's README says, so a person who finds the folder knows what it is for.
    public static let workspaceReadme = """
    # Skill Health workspace

    Skill Health opens Claude Code in this folder when you choose a menu item that fixes, checks or
    updates skills. It holds nothing but this note.

    Skill Health's own files (what a check found, changes waiting for your approval, backups) are in the
    folder above this one. They are kept out of this folder on purpose: Claude Code asks before it
    edits files outside the folder a session works in.

    You can delete this folder. Skill Health makes it again the next time it opens Claude Code.

    """

    /// Makes the workspace (and its README) if it isn't there, and returns it. The README is
    /// written again only when it differs, so opening Claude Code twice touches nothing.
    @discardableResult
    public static func prepareWorkspace(in skillHealthFolder: URL) throws -> URL {
        let folder = workspace(in: skillHealthFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = folder.appending(path: "README.md")
        if (try? String(contentsOf: readme, encoding: .utf8)) != workspaceReadme {
            try workspaceReadme.write(to: readme, atomically: true, encoding: .utf8)
        }
        return folder
    }

    /// The link that opens `command` in Claude Code, started in the workspace, which is made (with its
    /// README) first. Nil for a command that can't go in a link. Throws when the workspace can't be
    /// made: the caller then doesn't open Claude Code at all, rather than open it in Skill Health's folder.
    public static func link(for command: String, to destination: Destination, skillHealthFolder: URL) throws -> URL? {
        let folder = try prepareWorkspace(in: skillHealthFolder)
        return url(for: command, to: destination, in: folder)
    }

    private static func encode(_ text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
    }

    // MARK: The alert shown when the link can't be opened

    public static let alertTitle = "Couldn't Open Claude Code"
    public static let alertButton = "OK"

    public static func alertBody(for command: String) -> String {
        "\(command) is copied. Paste it into a Claude Code session and press Return."
    }

    // MARK: The note before the first command opens in a terminal

    // Claude Code drives Terminal and iTerm with AppleScript, so macOS asks whether it may. The
    // request is Claude Code's, and its link handler runs the versioned binary, so macOS names it
    // by the binary's file name ("2.1.289"), and likely asks again when an update brings a new one.
    // Skill Health can't change that text, or see whether the window opened; it says so first, once.

    public static let terminalNoteTitle = "Claude Code May Ask to Control Your Terminal"
    public static let terminalNoteContinue = "Continue"
    public static let terminalNoteCancel = "Cancel"

    public static func terminalNoteBody(for command: String) -> String {
        "Claude Code opens \(command) in a new terminal window. macOS may ask whether Claude Code can "
            + "control your terminal: the first time, and again after Claude Code updates. The request shows "
            + "Claude Code's version number, like “2.1.289”, instead of its name. Choose Allow. If you choose "
            + "Don't Allow, no window opens until you turn it on in System Settings > Privacy & Security > "
            + "Automation. Nothing runs until you press Return."
    }
}
