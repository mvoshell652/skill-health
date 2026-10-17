import Accessibility
import AppKit
import SwiftUI
import SkillHealthCore

/// The Claude Code plugin. Fixes, checks and updates run in Claude Code, so this is where the
/// person installs it. The status words carry the meaning: only the plugin's own hook can prove it
/// is connected, which is the one green check in the window. The app never installs anything: the
/// person runs the command in Terminal. The words are decided in `SettingsText`.
struct PluginRow: View {
    /// Counted up by the form to move focus to this row's control: after the folder becomes ready,
    /// and when the menu sent the person here.
    let focusRequest: Int
    @Environment(Library.self) private var library
    /// "Copied" for a few seconds, never longer than the command it was shown for.
    @State private var copied = false
    @State private var copiedReset: Task<Void, Never>?
    @FocusState private var controlFocused: Bool
    @AccessibilityFocusState private var controlSpoken: Bool

    private var step: SettingsText.PluginStep {
        SettingsText.pluginStep(folderReady: library.folderStage == .ready, plugin: library.pluginState)
    }

    private var command: String? {
        switch step.command {
        case .none: nil
        case .install: PluginInstall.command
        case .update: PluginInstall.updateCommand
        }
    }

    var body: some View {
        // One row, so the card is one unit to scroll to and the command block spans its width.
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                control
            } label: {
                Text("Claude Code plugin")
                line
            }
            if let command {
                CommandBlock(command)
                if let then = step.then {
                    Text(then)
                        .foregroundStyle(.secondary)
                }
            }
            if step.control == .connected {
                PluginCommands(commands: SettingsText.pluginCommands)
            }
            if let note = SettingsText.linkNote(plugin: library.pluginState, canOpen: library.canOpenClaudeCode) {
                Text(note)
                    .foregroundStyle(.secondary)
            }
        }
        .id(SettingsTarget.plugin)
        .onChange(of: step.command) { copied = false }
        .onChange(of: focusRequest) { focusControl() }
    }

    // MARK: Pieces

    @ViewBuilder private var line: some View {
        if step.warns {
            WarningLabel(step.line)
        } else {
            Text(markdown: step.line)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var control: some View {
        switch step.control {
        case .none:
            EmptyView()
        case .copyCommand:
            if let command {
                Button {
                    copy(command)
                } label: {
                    // Both words take the room of the longer, so the row doesn't reflow when one
                    // becomes the other.
                    Text("Copy Command")
                        .hidden()
                        .overlay { Text(copied ? "Copied" : "Copy Command") }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityInputLabels(["Copy Command", "Copy", "Copied"])
                .focused($controlFocused)
                .accessibilityFocused($controlSpoken)
            }
        case .waiting:
            Label("Waiting", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .connected:
            DoneLabel("Connected")
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        AccessibilityNotification.Announcement(SettingsText.commandCopied).post()
        copied = true
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private func focusControl() {
        guard step.control == .copyCommand else { return }
        controlFocused = true
        controlSpoken = true
    }
}

extension Text {
    /// A line with `code` spans in it, set in the monospaced face. Plain text if it won't parse.
    init(markdown: String) {
        self.init((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
    }
}

#Preview("Not installed") {
    Form {
        PluginRow(focusRequest: 0)
    }
    .formStyle(.grouped)
    .environment(Library())
    .frame(width: 520)
}
