import AppKit
import SkillHealthCore

/// Opens a command in Claude Code, or, when that can't be done from here, copies it and says so.
/// The command is typed into a new session and waits for Return: Skill Health never sends one.
enum ClaudeCodeLauncher {
    typealias Destination = ClaudeCodeCommand.Destination

    /// Where a command can open on this Mac. The Claude app counts only when the app that handles
    /// `claude://` is the Claude app. Claude Code registers `claude-cli://` after the person's
    /// first interactive prompt, so a Mac that has only just installed it may have neither.
    static func available() -> Set<Destination> {
        Set(Destination.allCases.filter(isAvailable))
    }

    private static func isAvailable(_ destination: Destination) -> Bool {
        guard let probe = ClaudeCodeCommand.probe(destination),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        switch destination {
        case .claudeApp:
            return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: ClaudeCodeCommand.claudeAppBundleID)
                .contains { $0.standardizedFileURL.path == handler.standardizedFileURL.path }
        case .terminal:
            return true
        }
    }

    /// Opens Claude Code in Skill Health's workspace, an empty folder made for it inside `skillHealthFolder`.
    /// Never in `skillHealthFolder` itself: its pending changes sit there, and a session may edit files
    /// in its working folder without asking. False when nothing handles the link, the workspace
    /// can't be made, or the system refused to open it.
    static func open(_ command: String, in destination: Destination, skillHealthFolder: URL) -> Bool {
        guard isAvailable(destination),
              let url = try? ClaudeCodeCommand.link(for: command, to: destination, skillHealthFolder: skillHealthFolder) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Asked before the first command opens in a terminal, so the request macOS shows next (whether
    /// "2.1.289" may control Terminal) isn't a mystery: it's Claude Code's, under its version number.
    /// True to go on. Cancel opens nothing, and the note comes back next time.
    static func confirmTerminal(for command: String, defaults: UserDefaults = .standard) -> Bool {
        guard !terminalNoteShown(defaults) else { return true }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = ClaudeCodeCommand.terminalNoteTitle
        alert.informativeText = ClaudeCodeCommand.terminalNoteBody(for: command)
        alert.addButton(withTitle: ClaudeCodeCommand.terminalNoteContinue)
        // Titled Cancel, so Escape chooses it.
        alert.addButton(withTitle: ClaudeCodeCommand.terminalNoteCancel)
        NSApplication.shared.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Once per Mac, counted from the first terminal link that actually opened: a Continue followed
    /// by a failed open (and the copy alert) leaves the note to be shown before the next one.
    static func terminalNoteShown(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: terminalNoteShownKey)
    }

    static func rememberTerminalNoteShown(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: terminalNoteShownKey)
    }

    private static let terminalNoteShownKey = "terminalNoteShown"

    /// Copies the command and says what happened, in an alert: the person asked for something that
    /// didn't happen, so the answer interrupts. VoiceOver reads the alert itself.
    static func copyAndExplain(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = ClaudeCodeCommand.alertTitle
        alert.informativeText = ClaudeCodeCommand.alertBody(for: command)
        alert.addButton(withTitle: ClaudeCodeCommand.alertButton)
        NSApplication.shared.activate()
        alert.runModal()
    }
}
