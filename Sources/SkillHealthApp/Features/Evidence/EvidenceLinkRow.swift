import SwiftUI

/// The finding's evidence link. It comes from third-party web evidence, so only an https link is
/// clickable.
struct EvidenceLinkRow: View {
    let evidence: URL

    var body: some View {
        LabeledContent("Evidence") {
            if evidence.scheme == "https" {
                Link(evidence.absoluteString, destination: evidence)
            } else {
                Text(evidence.absoluteString)
                    .textSelection(.enabled)
            }
        }
    }
}
