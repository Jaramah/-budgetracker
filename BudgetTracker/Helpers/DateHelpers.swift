import Foundation

/// Date math used for month-by-month filtering and labels.
///
/// All bucketing is pinned to a single calendar/timezone so a transaction logged
/// near midnight doesn't drift into the wrong month depending on UTC vs local time.
/// Defaults to Asia/Singapore (the user's locale); falls back to current.
enum DateHelpers {
    /// A calendar pinned to the app's reporting timezone.
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Singapore") ?? .current
        return cal
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    /// First instant of the month containing `date`.
    static func startOfMonth(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    /// First instant of the next month.
    static func startOfNextMonth(_ date: Date) -> Date {
        let start = startOfMonth(date)
        return calendar.date(byAdding: .month, value: 1, to: start) ?? date
    }

    /// Move a date by a number of months (e.g. -1 for previous month).
    static func addMonths(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: date) ?? date
    }

    /// "June 2026"
    static func monthYearLabel(_ date: Date) -> String {
        formatter("LLLL yyyy").string(from: date)
    }

    /// "Jun" — short month label for chart axes.
    static func shortMonthLabel(_ date: Date) -> String {
        formatter("LLL").string(from: date)
    }

    /// "12 Jun 2026"
    static func mediumDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateStyle = .medium
        return f.string(from: date)
    }

    /// True if the two dates fall in the same calendar month & year.
    static func sameMonth(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }
}
