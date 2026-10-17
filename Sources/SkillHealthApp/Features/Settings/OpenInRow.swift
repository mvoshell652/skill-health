import SwiftUI
import SkillHealthCore

/// Where menu items open their command: the Claude app or a terminal. Shown only when both are on
/// this Mac (see `SettingsText.showsOpenIn`); with one, there is nothing to choose. The Claude app
/// comes first because it opens with no permission prompt. The words are decided in `SettingsText`.
struct OpenInRow: View {
    @AppStorage(Library.openInKey) private var destination = ClaudeCodeCommand.Destination.claudeApp

    var body: some View {
        Picker(selection: $destination) {
            ForEach(ClaudeCodeCommand.Destination.allCases, id: \.self) { place in
                Text(SettingsText.destinationName(place)).tag(place)
            }
        } label: {
            // The picker carries both as its label and hint, as `NotedToggle` does, so the row is
            // read once.
            Text(SettingsText.openInTitle)
                .accessibilityHidden(true)
            Text(SettingsText.openInNote(destination))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .pickerStyle(.menu)
        .accessibilityLabel(SettingsText.openInTitle)
        .accessibilityHint(SettingsText.openInNote(destination))
    }
}

#Preview {
    Form {
        OpenInRow()
    }
    .formStyle(.grouped)
    .frame(width: 520)
}
