import SwiftUI

/// A command to run in Terminal, set apart from the sentence around it: monospaced, in the primary
/// tone (it is what to do, not a caption), selectable, and the width of the card.
struct CommandBlock: View {
    let command: String

    init(_ command: String) {
        self.command = command
    }

    var body: some View {
        Text(command)
            .font(.callout.monospaced())
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 6))
    }
}

#Preview {
    CommandBlock("claude plugin marketplace add mvoshell652/skill-health && claude plugin install skill-health@skill-health")
        .padding()
        .frame(width: 420)
}
