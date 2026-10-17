import Foundation
import SkillHealthCore

extension Finding {
    /// A sample from a debug launch, never a real finding: it may be shown, never acted on. Nothing a
    /// sample is shown in offers a hand-off to Claude Code, and nothing publishes it.
    var isSample: Bool { id.uuidString.hasPrefix("00000000-5A3B-4E00-8000-") }

    /// The real 27 Sep 2026 gcp-cloud-run finding, for previews.
    /// Fixed, so debug builds can recognise the sample and keep it inert.
    static let sampleID = UUID(uuidString: "00000000-5A3B-4E00-8000-000000000001")!

    static let sample = Finding(
        id: sampleID,
        skillName: "gcp-cloud-run",
        severity: .breaks,
        skillSays: "gcloud builds submit --tag gcr.io/MY_PROJECT_ID/my-app:latest",
        trueNow: "Container Registry shut down on March 18, 2025, and no longer accepts new images. Push to Artifact Registry (pkg.dev) instead.",
        source: URL(string: "https://docs.cloud.google.com/artifact-registry/docs/transition/prepare-gcr-shutdown") ?? URL(filePath: "/"),
        foundOn: .now,
        wrongSince: .written(on: .now),
        suggestedText: "gcloud builds submit --tag REGION-docker.pkg.dev/MY_PROJECT_ID/REPOSITORY/my-app:latest",
        keptBySecondCheck: true)

    #if DEBUG
    /// Distinct copies of the sample, for a launch with `-debugSampleFindings N`.
    static func samples(_ count: Int) -> [Finding] {
        (1...count).map { index in
            Finding(id: UUID(uuidString: String(format: "00000000-5A3B-4E00-8000-%012d", index + 1))!, skillName: "\(sample.skillName)-\(index)", severity: sample.severity, skillSays: sample.skillSays,
                    trueNow: sample.trueNow, source: sample.source, foundOn: sample.foundOn, wrongSince: sample.wrongSince)
        }
    }
    #endif
}
