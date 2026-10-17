import SwiftUI
import SkillHealthCore

/// What the evidence window offers below the findings. It never changes a skill: with the plugin
/// connected it hands the skill to Claude Code; without it, it says where fixing happens and how to
/// set that up; for sample skills it says they are samples and offers nothing.
struct EvidenceFooter: View {
    enum Purpose { case fix, check }

    let skillName: String
    let isSample: Bool
    var purpose: Purpose = .fix
    @Environment(Library.self) private var library
    @Environment(WindowActivation.self) private var windows
    @Environment(\.openWindow) private var openWindow

    private enum Mode {
        case sample
        case fix(command: String)
        /// The plugin can take it, but the skill's name isn't one that may go into a command.
        case runInClaudeCode
        case setUp
    }

    private var mode: Mode {
        if isSample { return .sample }
        guard library.pluginState.canHandOff else { return .setUp }
        let command = purpose == .fix ? ClaudeCodeCommand.fix(skill: skillName) : ClaudeCodeCommand.check(skill: skillName)
        return command.map { .fix(command: $0) } ?? .runInClaudeCode
    }

    var body: some View {
        HStack {
            switch mode {
            case .sample:
                Text("These are sample skills. Choose your Claude folder to see your own.")
                    .foregroundStyle(.secondary)
                Spacer()
            case .fix(let command):
                Spacer()
                Button(purpose == .fix ? "Fix in Claude Code…" : "Check in Claude Code…") { library.open(command: command) }
                    .keyboardShortcut(.defaultAction)
            case .runInClaudeCode:
                Text(purpose == .fix ? "Fixes happen in Claude Code. Run /skill-health:fix there." : "Checks happen in Claude Code. Run /skill-health:check there.")
                    .foregroundStyle(.secondary)
                Spacer()
            case .setUp:
                Text(purpose == .fix ? "Fixes happen in Claude Code with the Skill Health plugin." : "Checks happen in Claude Code with the Skill Health plugin.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Set Up Plugin…", action: showSetup)
            }
        }
        .padding([.horizontal, .bottom])
    }

    private func showSetup() {
        windows.showSettings(.plugin, using: openWindow)
    }
}

#Preview("Plugin not set up") {
    EvidenceFooter(skillName: "supabase", isSample: false)
        .environment(Library())
        .environment(WindowActivation())
        .frame(width: 520)
}

#Preview("Sample skills") {
    EvidenceFooter(skillName: "supabase-basics", isSample: true)
        .environment(Library())
        .environment(WindowActivation())
        .frame(width: 520)
}
