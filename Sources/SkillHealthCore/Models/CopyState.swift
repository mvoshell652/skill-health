import Foundation

/// How an installed copy relates to where it came from. Copy drift only: it says nothing about
/// whether the skill's instructions are true (that is what findings are for).
public enum CopyState: String, Codable, Sendable, Hashable, CaseIterable {
    /// The same files as the source today.
    case current
    /// Unchanged here since install, and the source has changed since: a newer copy exists.
    case behind
    /// Changed on this Mac since install; the source hasn't moved.
    case changedHere
    /// Changed here and at the source. Needs a person; never part of a batch update.
    case changedBoth
    /// The source no longer has this skill.
    case removedAtSource
}
