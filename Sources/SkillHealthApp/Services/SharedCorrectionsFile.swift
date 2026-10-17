import Foundation
import SkillHealthCore

/// The shared corrections snapshot that ships inside the app (copied from plugin/data/corrections.json,
/// the same file the plugin's command-line tool reads), so
/// Skill Health can flag known wrong instructions from the first launch: no network, no tokens, no plugin.
enum SharedCorrectionsFile {
    static func bundled() -> SharedCorrections? {
        guard let url = Bundle.main.url(forResource: "corrections", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SharedCorrections.self, from: data)
    }
}
