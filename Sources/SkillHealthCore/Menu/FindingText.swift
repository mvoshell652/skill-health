import Foundation

extension Severity {
    /// The word the menu and the evidence window use: "Failing" where the file says `breaks`.
    /// `displayName` keeps "Breaks" for older readers of the same case.
    public var plainName: String {
        switch self {
        case .breaks: "Failing"
        case .deprecated: "Deprecated"
        case .oldVersion: "Old version"
        case .cosmetic: "Cosmetic"
        }
    }
}

/// The sentences the evidence window prints about one finding. Pure, so the day-only dates and the
/// wording are tested rather than eyeballed.
public enum FindingText {
    /// A whole sentence, so it never reads "Wrong since: since it was written". Both dates name a
    /// day (midnight UTC), so both are formatted in UTC.
    public static func wrongSince(_ wrongSince: WrongSince) -> String {
        switch wrongSince {
        case .written(let date): "Wrong since it was written (\(DayLabel.utc(date)))"
        case .since(let date): "Wrong since \(DayLabel.utc(date))"
        case .installed(let date): "Already wrong when installed (\(DayLabel.utc(date)))"
        case .undated: "When this became wrong can't be dated from the evidence"
        }
    }

    /// Where the finding came from and what tested it: a known correction, or a check on this Mac,
    /// and whether a second look tried to disprove it.
    public static func provenance(of finding: Finding, timeZone: TimeZone = .current) -> String {
        let kept = finding.keptBySecondCheck == true ? " and kept after a second look tried to disprove it" : ""
        if let from = finding.sharedFrom {
            // A shared correction's date is the day it was checked (midnight UTC).
            let date = DayLabel.full(finding.foundOn, timeZone: timeZone)
            return "A known correction from \(from), found on \(date)\(kept). Your \(finding.filePath) is identical to that one, byte for byte."
        }
        let date = DayLabel.full(finding.foundOn, timeZone: timeZone)
        if finding.keptBySecondCheck == false { return "Checked on \(date). A second look couldn't confirm it." }
        return "Checked on \(date)\(kept)."
    }
}
