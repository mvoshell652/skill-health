import SwiftUI

/// The plugin's commands, each one whole: all on one line when the card is wide enough, otherwise
/// two to a line in columns, so a longer name never cuts the last one short.
struct PluginCommands: View {
    let commands: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            CommandLines(commands: commands, perLine: commands.count)
            CommandLines(commands: commands, perLine: 2)
            CommandLines(commands: commands, perLine: 1)
        }
        .font(.callout.monospaced())
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(commands.joined(separator: ", "))
    }
}

private struct CommandLines: View {
    let commands: [String]
    let perLine: Int

    private var starts: [Int] { Array(stride(from: 0, to: commands.count, by: max(perLine, 1))) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
            ForEach(starts, id: \.self) { start in
                GridRow {
                    ForEach(commands[start..<min(start + perLine, commands.count)], id: \.self) { command in
                        Text(command)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

#Preview("Narrow card") {
    PluginCommands(commands: ["/skill-health:check", "/skill-health:fix", "/skill-health:update", "/skill-health:undo"])
        .frame(width: 420, alignment: .leading)
        .padding()
}
