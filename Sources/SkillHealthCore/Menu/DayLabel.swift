import Foundation

/// A day as a short label ("Sep 26"), in English whatever the Mac's region, because the words around
/// it are English.
///
/// Some dates Skill Health stores name a day, not a moment: a finding's "wrong since" and a shared
/// correction's "checked on" are midnight UTC. Formatted in the Mac's time zone, west of UTC they
/// read a day early ("Feb 17" for a line that was wrong from Feb 18). Those are formatted in UTC. A
/// moment (a check that ran at 9:41 pm) is the person's own day, so it is formatted in their time zone.
public enum DayLabel {
    private static let locale = Locale(identifier: "en_US")

    /// True for a date at exactly 00:00:00 UTC, which is how Skill Health stores a day. A real moment lands
    /// on it once in 86,400 seconds, and then reads as that day in UTC: off by a day at worst.
    public static func isDayOnly(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400) == 0
    }

    /// "Sep 26, 2026". A day-only date in UTC, any other in `timeZone`.
    public static func full(_ date: Date, timeZone: TimeZone = .current) -> String {
        style(isDayOnly(date) ? .gmt : timeZone).month(.abbreviated).day().year()
            .format(date)
    }

    /// "Feb 18, 2026", always in UTC, for a date that is known to name a day.
    public static func utc(_ date: Date) -> String {
        style(.gmt).month(.abbreviated).day().year().format(date)
    }

    /// "Sep 26", or "Sep 26, 2025" when the year isn't `now`'s, so a check from last year isn't
    /// read as this year's.
    public static func short(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let zone = isDayOnly(date) ? TimeZone.gmt : timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var nowCalendar = Calendar(identifier: .gregorian)
        nowCalendar.timeZone = timeZone
        let sameYear = calendar.component(.year, from: date) == nowCalendar.component(.year, from: now)
        let base = style(zone).month(.abbreviated).day()
        return sameYear ? base.format(date) : base.year().format(date)
    }

    private static func style(_ zone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: locale,
                         calendar: Calendar(identifier: .gregorian), timeZone: zone)
    }
}
