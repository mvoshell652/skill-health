import Foundation
import SkillHealthCore

// export-shared: the owner's step after a check, so one check serves everyone. It adds this Mac's
// checks to a known-corrections file (the plugin's data/corrections.json, which the app bundles too).
// No skill's command allows it: it's run by hand, and its file is reviewed and committed like code.

extension Tool {
    func exportShared() async throws {
        guard let path = operands(after: 1).first else {
            Self.usageError("usage: skill-health export-shared <corrections.json>  (adds this Mac's checks to that file)")
        }
        let url = URL(filePath: path)
        var existing = SharedCorrections(updatedAt: .now)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            do { existing = try Self.decoder.decode(SharedCorrections.self, from: Data(contentsOf: url)) } catch {
                Self.fail("couldn't read \(Self.shown(path)), so it was left alone. \(ProblemText.reason(error))")
            }
        }
        let view = await overview()
        if let problem = view.checkBlockingProblem { Self.fail(problem) }
        let own = try await engine.loadFindings()
        let result = existing.addingChecks(from: own, skills: view.skills, compare: view.compare)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result.shared).write(to: url, options: .atomic)

        print("Shared \(Self.plural(result.added.count, "check", "checks")) in \(Self.shown(path)): "
              + "\(Self.plural(result.shared.checked.count, "skill folder", "skill folders")) checked, "
              + "\(Self.plural(result.shared.corrections.count, "correction", "corrections")).")
        let reasons: [SharedCorrections.ShareRefusal: String] = [
            .noSource: "not installed from a GitHub repository",
            .notCompared: "its source wasn't read at the last comparison",
            .differsFromSource: "its files differ from its source's",
            .changedSinceCheck: "it changed since its check, or the check has no fingerprint",
            .notInstalled: "no longer installed",
        ]
        for (reason, words) in reasons.sorted(by: { $0.value < $1.value }) {
            let names = result.refused.filter { $0.value == reason }.keys.sorted()
            guard !names.isEmpty else { continue }
            print("Not shared, \(words): \(names.map(Self.shown).joined(separator: ", ")).")
        }
    }
}
