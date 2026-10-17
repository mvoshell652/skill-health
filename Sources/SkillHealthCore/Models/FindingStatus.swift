import Foundation

/// Where a finding stands. A set-aside always carries a date, and is capped at 180 days
/// by `cappedSetAside(until:now:)`: nothing is set aside forever.
public enum FindingStatus: Codable, Sendable, Hashable {
    case open
    case patched(on: Date)
    case usingAnotherSkill(name: String)
    case setAside(until: Date)
    case notForThisProject

    /// 180 days, the longest any finding stays set aside.
    public static let longestSetAside: TimeInterval = 180 * 24 * 60 * 60

    /// The only way the app should build a set-aside: no later than 180 days from now.
    public static func cappedSetAside(until date: Date, now: Date = .now) -> FindingStatus {
        .setAside(until: min(date, now.addingTimeInterval(longestSetAside)))
    }
}
