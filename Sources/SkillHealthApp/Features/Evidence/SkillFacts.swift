import SwiftUI
import SkillHealthCore

/// What Skill Health knows about one skill, at the top of its page: how often it's used, where it came
/// from, and when it was checked. Read from what Skill Health already holds, so it costs no tokens.
struct SkillFacts: View {
    let skillName: String
    @Environment(Library.self) private var library

    var body: some View {
        if let skill = library.skills.first(where: { $0.name == skillName }) {
            Section {
                ForEach(lines(for: skill), id: \.label) { line in
                    LabeledContent(line.label) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(line.value)
                            if let detail = line.detail {
                                Text(detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private func lines(for skill: Skill) -> [SkillPageText.Line] {
        let report = library.usageReport
        return [
            SkillPageText.used(loads: skill.usesLast90Days, keptSince: report?.coversWindow == false ? report?.completeSince : nil),
            SkillPageText.source(origin: skill.origin, copy: skill.copy),
            SkillPageText.checked(checkedOn: library.findingsFile.audited[skill.name], covered: library.covered[skill.name],
                                  fingerprinted: library.savedFindings.trees[skill.name] != nil),
        ]
    }
}
