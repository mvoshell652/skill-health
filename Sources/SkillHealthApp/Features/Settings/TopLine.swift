import SwiftUI

/// What Skill Health is for, then the next step, or that it is all set up. Plain text above the cards in
/// the primary tone, one paragraph per line, so the next step is the first thing read.
struct TopLine: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    TopLine(lines: ["Skill Health is set up.", "It shows a dot in the menu bar when a skill you use needs a fix."])
        .padding(30)
        .frame(width: 520)
}
