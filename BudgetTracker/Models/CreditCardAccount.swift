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
    /// Day of month the statement is generated (1...28). 0 = not set.
    var statementDay: Int
    /// Day of month payment is due (1...28). 0 = not set.
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

    var hasDueDay: Bool { (1...28).contains(paymentDueDay) }
}
