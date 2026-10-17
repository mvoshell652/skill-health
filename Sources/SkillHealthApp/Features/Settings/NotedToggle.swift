import SwiftUI

/// A switch with a line under its title that says what it does. VoiceOver says the title and the
/// state, then the line as a hint, so the line isn't read again with every visit to the switch.
struct NotedToggle: View {
    let title: String
    let note: String
    @Binding var isOn: Bool

    init(_ title: String, note: String, isOn: Binding<Bool>) {
        self.title = title
        self.note = note
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            // The switch carries both as its label and hint; left visible to accessibility as well,
            // the row was read twice (each text, then the switch saying them again).
            Text(title)
                .accessibilityHidden(true)
            Text(note)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(title)
        .accessibilityHint(note)
    }
}

#Preview {
    Form {
        NotedToggle("Compare daily", note: "Only while Skill Health is running.", isOn: .constant(true))
    }
    .formStyle(.grouped)
    .frame(width: 520)
}
