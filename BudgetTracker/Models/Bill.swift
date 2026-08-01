import Foundation
import SwiftData

/// A recurring/upcoming bill shown on the Bills & Recurring screen (rent, telco,
/// subscriptions). Distinct from `RecurringRule` (which auto-posts transactions):
/// a Bill is a lightweight reminder the user can "Mark paid" each cycle.
/// Money in integer cents (see `Money`).
@Model
final class Bill {
    var id: UUID
    var name: String
    var amountCents: Int
    /// Day of month the bill is due (1...31), clamped to the month's real length
    /// wherever an actual date is derived.
    var dueDay: Int
    /// Raw `Recurrence` value.
    var recurrenceRaw: String
    /// Optional category link.
    var category: Category?
    /// The month (start-of-month date) this bill was last marked paid, if any.
    var lastPaidMonth: Date?
    var symbol: String
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        name: String,
        amountCents: Int,
        dueDay: Int = 1,
        recurrence: Recurrence = .monthly,
        category: Category? = nil,
        lastPaidMonth: Date? = nil,
        symbol: String = "doc.text.fill",
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.amountCents = abs(amountCents)
        self.dueDay = min(max(dueDay, 1), 31)
        self.recurrenceRaw = recurrence.rawValue
        self.category = category
        self.lastPaidMonth = lastPaidMonth
        self.symbol = symbol
        self.sortIndex = sortIndex
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .monthly }
        set { recurrenceRaw = newValue.rawValue }
    }

    enum Recurrence: String, CaseIterable, Identifiable, Codable {
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

    /// True if this bill has already been marked paid for the month containing `date`.
    func isPaid(in date: Date = .now) -> Bool {
        guard let last = lastPaidMonth else { return false }
        return DateHelpers.sameMonth(last, date)
    }

    /// The next due date on or after `date`, using dueDay within the month.
    func nextDueDate(from date: Date = .now) -> Date {
        let cal = DateHelpers.calendar
        let range = cal.range(of: .day, in: .month, for: date) ?? (1..<29)
        let clamped = min(dueDay, range.upperBound - 1)
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = clamped
        let thisMonth = cal.date(from: comps) ?? date
        if thisMonth >= cal.startOfDay(for: date) { return thisMonth }
        // else next month
        let nextMonthRef = cal.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
        let r2 = cal.range(of: .day, in: .month, for: nextMonthRef) ?? (1..<29)
        var c2 = cal.dateComponents([.year, .month], from: nextMonthRef)
        c2.day = min(dueDay, r2.upperBound - 1)
        return cal.date(from: c2) ?? nextMonthRef
    }
}
