import Foundation

/// How bad following an instruction is today. Stored by name, not position, so adding a
/// case never re-grades findings already on disk. `rank` is the one sort order.
public enum Severity: String, Codable, Sendable, CaseIterable, Comparable {
    case breaks
    case deprecated
    case oldVersion
    case cosmetic

    /// The word shown to the person. Never "outdated" (spec section 3).
    public var displayName: String {
        switch self {
        case .breaks: "Breaks"
        case .deprecated: "Deprecated"
        case .oldVersion: "Old version"
        case .cosmetic: "Cosmetic"
        }
    }

    /// Worst first.
    public var rank: Int {
        switch self {
        case .breaks: 0
        case .deprecated: 1
        case .oldVersion: 2
        case .cosmetic: 3
        }
    }

    /// Breaks and Deprecated are urgent: they light the icon and the session note.
    public var isUrgent: Bool { self == .breaks || self == .deprecated }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
}
