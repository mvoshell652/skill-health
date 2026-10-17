import SwiftUI

/// What the plugin step shows once Claude Code has connected it: a check and a word. The word
/// carries the meaning and the check is only a shape, so nothing here depends on seeing its color,
/// and VoiceOver skips the check.
struct DoneLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    DoneLabel("Connected")
        .padding()
}
