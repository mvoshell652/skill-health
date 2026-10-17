import SwiftUI
import SkillHealthCore

/// A skill's page: what Skill Health knows about it, then its open failing and deprecated instructions,
/// one section each, then the one thing to do in Claude Code.
struct EvidenceDetail: View {
    let skillName: String
    @Environment(Library.self) private var library

    var body: some View {
        let findings = library.openFindings(for: skillName)
        let isSample = library.showsSamples || findings.contains(where: \.isSample)
        Form {
            SkillFacts(skillName: skillName)
            if findings.isEmpty {
                Section {
                    Text(SkillPageText.noFindings)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(findings.enumerated(), id: \.element.id) { index, finding in
                EvidenceFinding(finding: finding, position: findings.count > 1 ? (index + 1, findings.count) : nil)
            }
        }
        .formStyle(.grouped)
        // Fix when there is something to fix; otherwise check, when it's due.
        .safeAreaBar(edge: .bottom) {
            if !findings.isEmpty {
                EvidenceFooter(skillName: skillName, isSample: isSample, purpose: .fix)
            } else if library.dueSkills().contains(where: { $0.name == skillName }) {
                EvidenceFooter(skillName: skillName, isSample: isSample, purpose: .check)
            }
        }
    }
}
