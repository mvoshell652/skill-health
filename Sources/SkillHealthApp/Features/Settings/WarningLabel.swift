import SwiftUI

/// A problem in a sentence: an orange triangle, then the words. The words say what is wrong; the
/// triangle only points at it, so VoiceOver skips it.
struct WarningLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.primary)
                // A reason can be long: it wraps, it is never cut.
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    WarningLabel("Skill Health couldn't read your Claude folder: The folder doesn't exist.")
        .padding()
        .frame(width: 400)
}
