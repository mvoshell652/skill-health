import Foundation

/// An installed skill folder and what Skill Health knows about it.
public struct Skill: Identifiable, Codable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let folder: URL
    /// nil means "no record of origin".
    public var origin: Origin?
    public var usesLast90Days: Int
    /// How the copy relates to its source; nil until a check has compared it (or when there is
    /// no record of where it came from).
    public var copy: CopyState?
    /// Keep this copy; don't offer updates for it (copy drift only).
    public var isPinned: Bool

    public init(name: String, folder: URL, origin: Origin? = nil, usesLast90Days: Int = 0,
                copy: CopyState? = nil, isPinned: Bool = false) {
        self.name = name
        self.folder = folder
        self.origin = origin
        self.usesLast90Days = usesLast90Days
        self.copy = copy
        self.isPinned = isPinned
    }

    public var isUsed: Bool { usesLast90Days > 0 }

    /// A newer copy exists and nothing here would be lost by taking it.
    public var isBehind: Bool { copy == .behind }
    public var changedOnThisMachine: Bool { copy == .changedHere || copy == .changedBoth }

    /// Behind, used, not pinned and not changed on this machine: safe to offer in a batch.
    public var isSafeUpdate: Bool { isBehind && isUsed && !isPinned }
}
