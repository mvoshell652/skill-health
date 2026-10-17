import Foundation

/// The `.openskills.json` receipt openskills writes into each skill folder it installs.
struct OpenSkillsReceipt: Decodable {
    let source: String
    let subpath: String
    let installedAt: Date
}
