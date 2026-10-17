import Foundation

/// Bringing one copy up to its source (spec flow G). Only a copy that is behind and unchanged on
/// this Mac gets one, so nothing of the person's is replaced: what is replaced is the copy they
/// installed, and it goes to backups. Built by `Engine.prepareUpdates`, which downloads every new
/// file and checks it against the id GitHub listed; nothing is written until `applyUpdates`.
public struct CopyUpdate: Identifiable, Sendable, Hashable {
    public var id: String { skill }
    public let skill: String
    public let folder: URL
    /// The install this update was prepared against; its record holds only while it stays.
    public let origin: Origin
    public let repo: String
    /// The commit the copy is brought up to.
    public let commit: String
    public let changes: [FileChange]
    public let historyURL: URL?

    public init(skill: String, folder: URL, origin: Origin, repo: String, commit: String, changes: [FileChange], historyURL: URL?) {
        self.skill = skill
        self.folder = folder
        self.origin = origin
        self.repo = repo
        self.commit = commit
        self.changes = changes
        self.historyURL = historyURL
    }
}

public struct FileChange: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case added, changed, removed
    }

    public var id: String { path }
    /// Inside the skill folder, "/"-separated.
    public let path: String
    public let kind: Kind
    /// This Mac's copy; nil when the file is new.
    public let before: Data?
    /// The source's; nil when the source removed the file.
    public let after: Data?
    /// Whether the source has it executable; nil when unknown, which leaves the mode as it is.
    public let executable: Bool?

    public init(path: String, kind: Kind, before: Data?, after: Data?, executable: Bool? = nil) {
        self.path = path
        self.kind = kind
        self.before = before
        self.after = after
        self.executable = executable
    }

    /// Every removed and inserted line, numbered, as the person reads it before agreeing, with the
    /// unchanged middle of a very long line left out (ProposedWrite.condensedDiff). Nil when either
    /// side isn't UTF-8 text (an image, an archive): those are listed but not shown. Read with every
    /// byte kept: a leading byte-order mark is part of the file, and an update that adds or drops
    /// one should show it.
    public var lines: String? {
        guard let old = before.map({ SkillText.exact($0) }) ?? "",
              let new = after.map({ SkillText.exact($0) }) ?? "" else { return nil }
        return ProposedWrite(file: URL(filePath: "/" + path), before: old, after: new).condensedDiff
    }
}

extension FileChange.Kind {
    /// What a change is, from its two blobs alone: nothing before means added, nothing after means
    /// removed. Nil when there is neither, which isn't a change.
    public init?<Before, After>(before: Before?, after: After?) {
        switch (before == nil, after == nil) {
        case (true, false): self = .added
        case (false, true): self = .removed
        case (false, false): self = .changed
        case (true, true): return nil
        }
    }
}

/// What an update run did, per skill.
public struct UpdateOutcome: Sendable, Equatable {
    public var updated: [String] = []
    /// Skill to why it was left as it was.
    public var skipped: [String: String] = [:]
    /// Skill to what went wrong when it could not be fully updated or put back, or wasn't
    /// recorded. Never shown as "left as they were".
    public var damaged: [String: String] = [:]
    /// Where the replaced copies went.
    public var backups: URL?

    public init() {}
}
