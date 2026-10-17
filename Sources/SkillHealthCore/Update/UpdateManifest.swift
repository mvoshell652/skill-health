import Foundation

/// What an update changed in one skill, saved beside its backups
/// (backups/<skill>/<stamp>-update/.manifest.json) the moment its files land, so the update can be
/// undone: which files it added, replaced and removed, each with its git blob id and mode before and
/// after, and the update record it replaced. Without it an update's added files are recorded nowhere
/// and the commit the copy came from before is overwritten.
public struct UpdateManifest: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public let path: String
        public let kind: FileChange.Kind
        public let before: String?
        public let after: String?
        public let beforeMode: Int?
        public let afterMode: Int?
    }

    public var version = 1
    public let skill: String
    public let folder: String
    public let repo: String
    public let toCommit: String
    public let updatedAt: Date
    /// The record this update replaced; nil when the copy was as installed.
    public let previousRecord: UpdateRecords.Record?
    /// The commit the copy came from before, as the last comparison had it.
    public let previousInstalledFrom: String?
    public let files: [File]

    public static let fileName = ".manifest.json"
}

extension FileChange.Kind: Codable {}

/// A copy's difference from its source, by path, as blob ids (nil where the file is absent).
public struct SourceDelta: Sendable, Equatable {
    public struct Blobs: Sendable, Equatable {
        public let before: String?
        public let after: String?

        public init(before: String?, after: String?) {
            self.before = before
            self.after = after
        }
    }

    public let repo: String
    public let commit: String
    public let changes: [String: Blobs]
}
