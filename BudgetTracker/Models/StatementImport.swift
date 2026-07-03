import Foundation
import SwiftData

/// Represents one uploaded credit-card statement (CSV or PDF the user imported).
/// Amounts in cents (see `Money`).
@Model
final class StatementImport {
    var id: UUID
    var fileName: String
    var importedAt: Date
    var label: String
    /// Sum of all charge lines in cents, computed at import time.
    var statementTotalCents: Int

    /// The `CreditCardAccount.id` this statement belongs to (nil = unassigned).
    /// Stored as an ID rather than a relationship to keep the schema migration
    /// simple and avoid cascade surprises when a card is deleted.
    var cardID: UUID? = nil

    /// Raw `Bank` value detected at import time (for display even if unassigned).
    var detectedBankRaw: String = Bank.unknown.rawValue

    @Relationship(deleteRule: .cascade, inverse: \StatementLine.statement)
    var lines: [StatementLine]? = []

    init(
        id: UUID = UUID(),
        fileName: String,
        importedAt: Date = .now,
        label: String = "",
        statementTotalCents: Int = 0,
        cardID: UUID? = nil,
        detectedBank: Bank = .unknown
    ) {
        self.id = id
        self.fileName = fileName
        self.importedAt = importedAt
        self.label = label
        self.statementTotalCents = statementTotalCents
        self.cardID = cardID
        self.detectedBankRaw = detectedBank.rawValue
    }

    var detectedBank: Bank {
        get { Bank(rawValue: detectedBankRaw) ?? .unknown }
        set { detectedBankRaw = newValue.rawValue }
    }
}

/// One line item parsed from a statement.
@Model
final class StatementLine {
    var id: UUID
    var date: Date
    var desc: String
    /// Positive = a charge (expense). Negative = a payment/credit/refund. In cents.
    var amountCents: Int
    /// Set when the line is linked to a logged Transaction.
    var matchedTransactionID: UUID?
    var statement: StatementImport?

    init(
        id: UUID = UUID(),
        date: Date,
        desc: String,
        amountCents: Int,
        matchedTransactionID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.desc = desc
        self.amountCents = amountCents
        self.matchedTransactionID = matchedTransactionID
    }

    var isMatched: Bool { matchedTransactionID != nil }
    var isCharge: Bool { amountCents > 0 }
}
