import Foundation

/// Where a skill's copy came from. Never called "source": that word means evidence.
public struct Origin: Codable, Sendable, Hashable {
    public let repo: String          // "TerminalSkills/skills"
    public let subpath: String       // "skills/supabase"
    public let installedAt: Date
    /// Git tree hash of the folder as installed, when known. Makes later compares exact.
    public let installedTreeHash: String?

    public init(repo: String, subpath: String, installedAt: Date, installedTreeHash: String? = nil) {
        self.repo = repo
        self.subpath = subpath
        self.installedAt = installedAt
        self.installedTreeHash = installedTreeHash
    }
}
