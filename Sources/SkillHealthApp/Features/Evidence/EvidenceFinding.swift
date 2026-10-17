import SwiftUI
import SkillHealthCore

/// One finding as evidence. Severity is a word and a shape, never a color alone.
struct EvidenceFinding: View {
    let finding: Finding
    /// "1 of 3", when the skill has more than one.
    let position: (number: Int, count: Int)?

    var body: some View {
        Section {
            EvidenceField(title: "The skill says") {
                Text(finding.skillSays)
                    .monospaced()
                    .textSelection(.enabled)
                if finding.filePath != "SKILL.md" {
                    Text("In \(finding.filePath)")
                        .foregroundStyle(.secondary)
                }
            }
            EvidenceField(title: "True now") {
                Text(finding.trueNow)
                    .textSelection(.enabled)
            }
            EvidenceLinkRow(evidence: finding.source)
            Text(FindingText.wrongSince(finding.wrongSince))
            Text(FindingText.provenance(of: finding))
                .foregroundStyle(.secondary)
        } header: {
            Label(heading, systemImage: symbol)
                .font(.headline)
        }
    }

    private var heading: String {
        guard let position else { return finding.severity.plainName }
        return "\(finding.severity.plainName), \(position.number) of \(position.count)"
    }

    private var symbol: String {
        switch finding.severity {
        case .breaks: "xmark.octagon"
        case .deprecated: "exclamationmark.triangle"
        case .oldVersion, .cosmetic: "info.circle"
        }
    }
}

#Preview {
    Form {
        EvidenceFinding(finding: .sample, position: nil)
    }
    .formStyle(.grouped)
    .frame(width: 520)
}
