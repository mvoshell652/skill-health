import SwiftUI

/// A skill's page, read-only: what Skill Health knows about it (use, source, checks), and what a check
/// found: severity, what the skill says, what is true now, the evidence and where it came from. One
/// window per skill, titled with its name, opened from the skill's row in the menu. It is a real
/// window because a menu closes the moment focus moves. Learning about a skill here costs no
/// tokens; fixing and checking happen in Claude Code.
struct EvidenceWindow: View {
    let skillName: String?
    @Environment(WindowActivation.self) private var windows

    var body: some View {
        Group {
            if let skillName {
                EvidenceDetail(skillName: skillName)
                    .navigationTitle(skillName)
            } else {
                ContentUnavailableView {
                    Label {
                        Text("Nothing to review")
                    } icon: {
                        Image(nsImage: PhosphorIcon.image(side: 64, color: "#8E8E93"))
                    }
                }
            }
        }
        // As tall as its findings, up to the same cap as the setup window; past it the form scrolls.
        .frame(width: Layout.evidenceWindowWidth)
        .frame(minHeight: 280, maxHeight: Layout.mainWindowMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: windows.windowOpened)
        .onDisappear(perform: windows.windowClosed)
    }
}
