import SwiftUI
import SkillHealthCore

/// The Claude folder: where Skill Health reads which skills you use. Its trailing slot holds one control,
/// never a status; what Skill Health found there is said in the lines under the title. The result of
/// choosing a folder is spoken to VoiceOver by the library, since the button that was pressed is gone.
/// The words are decided in `SettingsText`.
struct FolderRow: View {
    @Environment(Library.self) private var library
    @Environment(FolderAccess.self) private var folderAccess
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch library.state {
            case .needsFolder: notChosen
            case .loading: reading
            case .failed(let why): failed(why)
            case .loaded:
                if library.isSample { sample } else { ready }
            }
        }
        .animation(reduceMotion ? nil : .default, value: library.state)
    }

    // MARK: States

    /// The default path is not shown: nothing is chosen yet, and showing it would read as chosen.
    @ViewBuilder private var notChosen: some View {
        LabeledContent {
        } label: {
            title
            Text(SettingsText.folderNotChosen)
                .foregroundStyle(.secondary)
        }
        // For anyone without Claude Code yet, App Review included. A bordered button: grey
        // borderless text read as a caption, not something to press.
        HStack {
            Button("Try with Sample Skills", action: trySample)
            Spacer()
            Button("Choose Folder…", action: choose)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var reading: some View {
        LabeledContent {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Reading your skills")
        } label: {
            title
            Text(SettingsText.folderReading)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func failed(_ why: String) -> some View {
        LabeledContent {
            Button("Choose Again…", action: choose)
                .keyboardShortcut(.defaultAction)
        } label: {
            title
            WarningLabel(SettingsText.folderFailed(why))
        }
    }

    @ViewBuilder private var sample: some View {
        LabeledContent {
            Button("Choose Claude Folder…", action: choose)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } label: {
            title
            Text(SettingsText.folderSample)
                .foregroundStyle(.secondary)
            watcherNote
        }
    }

    @ViewBuilder private var ready: some View {
        let lines = SettingsText.readyLines(skills: library.skills.count, usage: library.usageLine)
        LabeledContent {
            // One control: when which skills you use can't be read, trying again is the next step.
            if lines.problem != nil {
                Button("Read Skills Again", action: library.readUsageAgain)
            } else {
                Button("Change…", action: choose)
            }
        } label: {
            title
            // Every line under the title is set to .secondary: past the second line the system
            // falls back to a tertiary gray, measured at 2.24:1 against the row.
            Text(shownPath)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
                .help(fullPath)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            Text(lines.counts)
                .foregroundStyle(.secondary)
            if let caveat = lines.caveat {
                Text(caveat)
                    .foregroundStyle(.secondary)
            }
            if let problem = lines.problem {
                WarningLabel(problem)
            }
            watcherNote
        }
        // The folder can still be changed while Read Skills Again holds the trailing slot: a read
        // that fails is often the folder.
        if lines.problem != nil {
            HStack {
                Spacer()
                Button("Change…", action: choose)
            }
        }
    }

    // MARK: Pieces

    private var title: some View {
        Text("Claude folder")
    }

    @ViewBuilder private var watcherNote: some View {
        if !library.watchesFolder {
            Text(SettingsText.watcherNote)
                .foregroundStyle(.secondary)
        }
    }

    private var fullPath: String {
        let path = (folderAccess.folder ?? FolderAccess.defaultClaudeFolder).path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// ~/.claude for the home folder's own .claude. The home is the real one, from the password
    /// database: inside the sandbox NSHomeDirectory() is the app's container.
    private var shownPath: String {
        let home = FolderAccess.defaultClaudeFolder.deletingLastPathComponent().path(percentEncoded: false)
        return SettingsText.displayPath(fullPath, home: home)
    }

    private func choose() {
        library.chooseFolder(using: folderAccess)
    }

    private func trySample() {
        library.trySample(using: folderAccess)
    }
}
