import Foundation

/// The words at the top of a skill's page: what Skill Health knows about it, read from what it already
/// holds, so learning about a skill costs no tokens. Fixing it is the page's one hand-off.
public enum SkillPageText {
    public struct Line: Equatable, Sendable {
        public let label: String
        public let value: String
        /// A second line under the value, when there is more to say.
        public let detail: String?

        public init(label: String, value: String, detail: String? = nil) {
            self.label = label
            self.value = value
            self.detail = detail
        }
    }

    /// "Used": "195 times in the last 90 days". When Claude Code hasn't kept 90 days of sessions,
    /// the window is the one it kept, so a count is never claimed for days Skill Health can't see.
    public static func used(loads: Int, keptSince: Date?, now: Date = .now, timeZone: TimeZone = .current) -> Line {
        let window = keptSince.map { "since \(DayLabel.short($0, now: now, timeZone: timeZone))" } ?? "in the last 90 days"
        let value = switch loads {
        case ...0: "Not \(window)"
        case 1: "Once \(window)"
        default: "\(NumberText.count(loads)) times \(window)"
        }
        return Line(label: "Used", value: value)
    }

    /// "Source": where it came from, and how this copy stands against it after the last comparison.
    public static func source(origin: Origin?, copy: CopyState?, now: Date = .now, timeZone: TimeZone = .current) -> Line {
        guard let origin else { return Line(label: "Source", value: "No install record, so Skill Health can't compare it with a source") }
        let value = "\(origin.repo), installed \(DayLabel.short(origin.installedAt, now: now, timeZone: timeZone))"
        let detail: String? = switch copy {
        case nil: nil
        case .current: "The same as its source at the last comparison."
        case .behind: "A newer copy is at its source. Run /skill-health:update in Claude Code to take it."
        case .changedHere: "Changed on this Mac since it was installed."
        case .changedBoth: "Changed on this Mac and at its source, so an update would write over your changes."
        case .removedAtSource: "Its source no longer has it."
        }
        return Line(label: "Source", value: value, detail: detail)
    }

    /// "Checked": when, and whether that check still covers the files (`Coverage`).
    /// - Parameters:
    ///   - checkedOn: the last check, of any files.
    ///   - covered: the last check that covered the files as they are now.
    ///   - fingerprinted: whether that last check saved a fingerprint, so "changed since" can be known.
    public static func checked(checkedOn: Date?, covered: Date?, fingerprinted: Bool,
                               now: Date = .now, timeZone: TimeZone = .current) -> Line {
        let day = { (date: Date) in DayLabel.short(date, now: now, timeZone: timeZone) }
        if let covered {
            let due = Coverage.due(after: covered)
            return due > now
                ? Line(label: "Checked", value: "\(day(covered)), unchanged since", detail: "Due for another check \(day(due)).")
                : Line(label: "Checked", value: day(covered), detail: "Over 90 days ago, so it's due for another check.")
        }
        guard let checkedOn else { return Line(label: "Checked", value: "Never", detail: "/skill-health:check in Claude Code can check it.") }
        return fingerprinted
            ? Line(label: "Checked", value: "\(day(checkedOn)), changed since", detail: "So it's due for another check.")
            : Line(label: "Checked", value: day(checkedOn))
    }

    /// Under the findings, when there are none.
    public static let noFindings = "No open failing or deprecated instructions."
}
