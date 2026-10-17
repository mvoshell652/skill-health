import SwiftUI

/// A titled block read as one: "The skill says", then what it says.
struct EvidenceField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            content
        }
        .accessibilityElement(children: .combine)
    }
}
