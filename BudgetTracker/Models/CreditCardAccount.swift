import Foundation
import SwiftData
import SwiftUI

/// A specific credit card the user owns, e.g. "DBS Altitude •••• 1234".
///
/// Uploaded statements are routed to the matching account by detected `Bank`
/// (the user confirms on the Review screen). Each account tracks its statement
/// cut day and payment-due day so we can schedule due-date reminders.
///
/// Money in integer cents (see `Money`).
@Model
final class CreditCardAccount {
    var id: UUID
    /// Raw value of `Bank` so SwiftData persists it as a plain string.
    var bankRaw: String
    /// User's nickname for the card, e.g. "Altitude" or "PayLah backup".
    var nickname: String
    /// Last 4 digits (optional, for disambiguating two cards from the same bank).
    var last4: String
    /// Day of month the statement is generated (1...31). 0 = not set.
    /// Days beyond a given month's length are clamped when a real date is built,
    /// so a 31st cycle lands on the 28th/29th in February rather than vanishing.
    var statementDay: Int
    /// Day of month payment is due (1...31). 0 = not set. Clamped per month, as above.
    var paymentDueDay: Int
    /// Optional credit limit in cents. 0 = not set.
    var creditLimitCents: Int
    /// Optional custom colour hex; falls back to the bank tint.
    var colorHex: String
    /// Sort order in the Cards list.
    var sortIndex: Int
    /// Per-card toggle for the payment-due reminder.
    var reminderEnabled: Bool

    init(
        id: UUID = UUID(),
        bank: Bank = .unknown,
        nickname: String = "",
        last4: String = "",
        statementDay: Int = 0,
        paymentDueDay: Int = 0,
        creditLimitCents: Int = 0,
        colorHex: String = "",
        sortIndex: Int = 0,
        reminderEnabled: Bool = true
    ) {
        self.id = id
        self.bankRaw = bank.rawValue
        self.nickname = nickname
        self.last4 = last4
        self.statementDay = statementDay
        self.paymentDueDay = paymentDueDay
        self.creditLimitCents = creditLimitCents
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        self.reminderEnabled = reminderEnabled
    }

    /// Bridge the raw string to the enum.
    var bank: Bank {
        get { Bank(rawValue: bankRaw) ?? .unknown }
        set { bankRaw = newValue.rawValue }
    }

    /// "DBS Altitude" or "DBS •••• 1234" — a stable display name.
    var displayName: String {
        let base = nickname.isEmpty ? bank.label : "\(bank.label) \(nickname)"
        if !last4.isEmpty { return "\(base) •••• \(last4)" }
        return base
    }

    var color: Color {
        Color(hex: colorHex.isEmpty ? bank.tintHex : colorHex)
    }

    var hasDueDay: Bool { (1...31).contains(paymentDueDay) }
    var hasStatementDay: Bool { (1...31).contains(statementDay) }

    // MARK: - Due dates
    //
    // `paymentDueDay` is a day-of-month, which is ambiguous on its own — the app
    // previously showed it as a bare number ("Due day: 7") and scheduled a
    // reminder on the 7th of every month, with no link to the statement cycle.
    //
    // A statement issued 19 Jul with a due day of 7 is due 7 **August**, not
    // 7 July: the due date lands in the month *after* the statement whenever the
    // due day is on or before the statement day. Resolving the due date as "the
    // first occurrence of the due day strictly after the statement date" gets
    // that right, and also handles the other shape correctly — a statement on
    // the 5th with a due day of the 25th is due later the *same* month.

    /// The payment due date for a statement issued on `statementDate`.
    ///
    /// Never returns a date on or before `statementDate`, so a due day that has
    /// already passed in the statement month rolls into the next one. Returns
    /// `nil` if this card has no due day configured.
    func dueDate(forStatementDate statementDate: Date) -> Date? {
        guard hasDueDay else { return nil }
        let cal = DateHelpers.calendar
        let cutoff = cal.startOfDay(for: statementDate)
        // Two candidates are always enough: the statement's own month, then the
        // next one. The due day can never be more than one month away.
        for offset in 0...1 {
            guard let base = cal.date(byAdding: .month, value: offset, to: statementDate),
                  let candidate = dueDate(inMonthOf: base, cal: cal),
                  cal.startOfDay(for: candidate) > cutoff
            else { continue }
            return candidate
        }
        return nil
    }

    /// The next payment due date at or after `date` — what the card list and
    /// reminders should show when there's no specific statement in hand.
    func nextDueDate(asOf date: Date = .now) -> Date? {
        guard hasDueDay else { return nil }
        let cal = DateHelpers.calendar
        let today = cal.startOfDay(for: date)
        for offset in 0...1 {
            guard let base = cal.date(byAdding: .month, value: offset, to: date),
                  let candidate = dueDate(inMonthOf: base, cal: cal),
                  cal.startOfDay(for: candidate) >= today
            else { continue }
            return candidate
        }
        return nil
    }

    /// Days remaining until the next due date; negative is impossible since
    /// `nextDueDate` never looks backwards. `nil` when no due day is set.
    func daysUntilDue(asOf date: Date = .now) -> Int? {
        let cal = DateHelpers.calendar
        guard let due = nextDueDate(asOf: date) else { return nil }
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: due)).day
    }

    /// The due day pinned into the month containing `date`, clamped to that
    /// month's length so a due day of 31 doesn't vanish in February. Set to 09:00
    /// to match the reminder fire time.
    private func dueDate(inMonthOf date: Date, cal: Calendar) -> Date? {
        var comps = cal.dateComponents([.year, .month], from: date)
        let daysInMonth = cal.range(of: .day, in: .month, for: date)?.count ?? 28
        comps.day = min(paymentDueDay, daysInMonth)
        comps.hour = 9
        return cal.date(from: comps)
    }
}
