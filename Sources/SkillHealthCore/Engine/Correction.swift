import Foundation

/// One known correction handed to Claude at session start by the plugin's hook.
/// `source` is the finding's evidence link. It keeps its stored name, which status.json and the hook
/// files already use; Claude is told it as "Evidence:".
public struct Correction: Codable, Sendable, Hashable {
    public let skillName: String
    public let skillSays: String
    public let trueNow: String
    public let source: URL

    public init(skillName: String, skillSays: String, trueNow: String, source: URL) {
        self.skillName = skillName
        self.skillSays = skillSays
        self.trueNow = trueNow
        self.source = source
    }
}
