import Foundation

/// When a finding became wrong. Diagnostic only: it labels a finding and never changes
/// which decisions are offered. Labels keep the stored JSON readable.
public enum WrongSince: Codable, Sendable, Hashable {
    /// Already false the day the skill was first committed.
    case written(on: Date)
    /// True when written, false from this date.
    case since(date: Date)
    /// Already false the day this copy was installed, and nothing dates it earlier. It says nothing
    /// about when the skill was written: the install day is only when this person got it.
    case installed(on: Date)
    /// The evidence doesn't date it either way. Never guessed.
    case undated
}
