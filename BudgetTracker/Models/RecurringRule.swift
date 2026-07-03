import Foundation
import SwiftData

/// A rule that auto-generates transactions on a schedule (rent, telco, Netflix,
/// salary, etc.). On app launch, `RecurringMaterializer` posts any occurrences
/// that are now due and advances `nextRunDate` — idempotently, so re-launching
/// never double-posts the same period.
///
/// Money in integer cents (see `Money`).
@Model
final class RecurringRule {
    var id: UUID
    /// Positive magnitude in cents; direction from `isExpense`.
    var amountCents: Int
    var isExpense: Bool
    var note: String
    /// Optional category link (nullify on delete — mirrors Transaction).
    var category: Category?
    /// Raw PaymentMethod string, like Transaction.
    var paymentMethodRaw: String
    /// Optional card this recurring charge posts to.
    var cardID: UUID?
    /// Raw `Cadence` value.
    var cadenceRaw: String
    /// For monthly/yearly: day of month (1...28). For weekly: 1=Sun ... 7=Sat.
    var anchorDay: Int
    /// First date the rule is active from.
    var startDate: Date
    /// Optional end date; nil = runs indefinitely.
    var endDate: Date?
    /// The next occurrence still to be posted (drives materialization).
    var nextRunDate: Date
    var isActive: Bool

    init(
        id: UUID = UUID(),
        amountCents: Int,
        isExpense: Bool = true,
        note: String = "",
        category: Category? = nil,
        paymentMethod: PaymentMethod = .cash,
        cardID: UUID? = nil,
        cadence: Cadence = .monthly,
        anchorDay: Int = 1,
        startDate: Date = .now,
        endDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.amountCents = abs(amountCents)
        self.isExpense = isExpense
        self.note = note
        self.category = category
        self.paymentMethodRaw = paymentMethod.rawValue
        self.cardID = cardID
        self.cadenceRaw = cadence.rawValue
        self.anchorDay = anchorDay
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        // First run is the first valid occurrence on/after startDate.
        self.nextRunDate = Cadence(rawValue: cadence.rawValue).flatMap {
            RecurringRule.firstOccurrence(cadence: $0, anchorDay: anchorDay, onOrAfter: startDate)
        } ?? startDate
    }

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .cash }
        set { paymentMethodRaw = newValue.rawValue }
    }

    var signedCents: Int { isExpense ? -amountCents : amountCents }

    // MARK: Schedule math (pinned to Asia/Singapore via DateHelpers.calendar)

    enum Cadence: String, CaseIterable, Identifiable, Codable {
        case weekly, monthly, yearly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            case .yearly:  return "Yearly"
            }
        }
    }

    /// The first occurrence on or after `date` for the given cadence/anchor.
    static func firstOccurrence(cadence: Cadence, anchorDay: Int, onOrAfter date: Date) -> Date {
        let cal = DateHelpers.calendar
        switch cadence {
        case .weekly:
            // anchorDay: 1=Sun ... 7=Sat (Gregorian weekday numbering).
            let target = min(max(anchorDay, 1), 7)
            var d = cal.startOfDay(for: date)
            for _ in 0..<7 {
                if cal.component(.weekday, from: d) == target { return d }
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        case .monthly:
            return occurrenceInMonth(of: date, day: anchorDay, notBefore: date)
                ?? occurrenceInMonth(of: cal.date(byAdding: .month, value: 1, to: date) ?? date,
                                     day: anchorDay, notBefore: date)
                ?? date
        case .yearly:
            // Anchor month/day taken from the start date; advance a year if past.
            let comps = cal.dateComponents([.month, .day], from: date)
            var next = DateComponents()
            next.year = cal.component(.year, from: date)
            next.month = comps.month
            next.day = RecurringRule.clampedDay(comps.day ?? 1, forYear: next.year, month: comps.month, cal: cal)
            let candidate = cal.date(from: next) ?? date
            if candidate >= cal.startOfDay(for: date) { return candidate }
            next.year! += 1
            next.day = RecurringRule.clampedDay(comps.day ?? 1, forYear: next.year, month: comps.month, cal: cal)
            return cal.date(from: next) ?? date
        }
    }

    /// Advance `nextRunDate` to the following occurrence after it fires.
    func advance() {
        let cal = DateHelpers.calendar
        switch cadence {
        case .weekly:
            nextRunDate = cal.date(byAdding: .day, value: 7, to: nextRunDate) ?? nextRunDate
        case .monthly:
            // Move to day 1 of the *next* month first (always valid, never
            // overflows) before re-applying the clamped anchor day. Adding a
            // month directly to a high day-of-month date (e.g. Jan 31) is the
            // classic Foundation overflow case: it can land in March instead
            // of February, silently skipping that month's occurrence entirely.
            var comps = cal.dateComponents([.year, .month], from: nextRunDate)
            comps.day = 1
            let firstOfThisMonth = cal.date(from: comps) ?? nextRunDate
            let firstOfNextMonth = cal.date(byAdding: .month, value: 1, to: firstOfThisMonth) ?? firstOfThisMonth
            nextRunDate = RecurringRule.occurrenceInMonth(of: firstOfNextMonth, day: anchorDay, notBefore: nil) ?? firstOfNextMonth
        case .yearly:
            // Same overflow risk as monthly, specifically for Feb 29 anchors:
            // adding a year to a leap-day date can overflow into March if the
            // target year isn't a leap year. Re-derive from (year+1, month, day)
            // with clamping instead of shifting the date directly.
            var comps = cal.dateComponents([.year, .month, .day], from: nextRunDate)
            comps.year = (comps.year ?? cal.component(.year, from: nextRunDate)) + 1
            comps.day = RecurringRule.clampedDay(comps.day ?? 1, forYear: comps.year, month: comps.month, cal: cal)
            nextRunDate = cal.date(from: comps) ?? nextRunDate
        }
    }

    /// Clamp `day` to the number of days actually in `month`/`year` (e.g. Feb 29
    /// only in leap years, 30 for Apr/Jun/Sep/Nov) rather than hardcoding 28,
    /// which would needlessly move every month's occurrence 1-3 days early.
    private static func clampedDay(_ day: Int, forYear year: Int?, month: Int?, cal: Calendar) -> Int {
        var probe = DateComponents()
        probe.year = year
        probe.month = month
        probe.day = 1
        guard let probeDate = cal.date(from: probe),
              let range = cal.range(of: .day, in: .month, for: probeDate)
        else { return min(day, 28) }
        return min(day, range.upperBound - 1)
    }

    /// The date for `day` within the month of `ref`, clamped to the month length
    /// (so day 31 in February becomes the 28th/29th). Optionally require >= notBefore.
    private static func occurrenceInMonth(of ref: Date, day: Int, notBefore: Date?) -> Date? {
        let cal = DateHelpers.calendar
        let range = cal.range(of: .day, in: .month, for: ref) ?? (1..<29)
        let clamped = min(max(day, 1), range.upperBound - 1)
        var comps = cal.dateComponents([.year, .month], from: ref)
        comps.day = clamped
        guard let d = cal.date(from: comps) else { return nil }
        if let nb = notBefore, d < cal.startOfDay(for: nb) { return nil }
        return d
    }
}
