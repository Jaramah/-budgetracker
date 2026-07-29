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

    /// The date printed on the statement itself, when the PDF exposed it.
    /// `importedAt` is when the file was opened, which is often weeks later and is
    /// no basis for working out which cycle a statement belongs to.
    var statementDate: Date? = nil

    /// The payment due date the bank printed. Preferred over anything computed
    /// from the card's due day: it is the issuer's own figure, already accounting
    /// for weekends and the cycle rolling into the following month.
    var dueDate: Date? = nil

    /// The total the statement footed its column with, if any.
    var declaredTotalCents: Int? = nil

    /// Whether the imported charges matched that total. `nil` means the statement
    /// printed no total to check against — not the same as balancing.
    var reconciled: Bool? = nil

    @Relationship(deleteRule: .cascade, inverse: \StatementLine.statement)
    var lines: [StatementLine]? = []

    /// How the import balanced, for display.
    enum Reconciliation { case balanced, mismatch(Int), unchecked }

    var reconciliation: Reconciliation {
        guard let reconciled, let declaredTotalCents else { return .unchecked }
        if reconciled { return .balanced }
        let imported = (lines ?? []).filter { $0.isCharge }.reduce(0) { $0 + $1.amountCents }
        return .mismatch(imported - declaredTotalCents)
    }

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

    /// ISO code of the currency the merchant actually billed, for a foreign
    /// transaction. `amountCents` stays in the card's currency — this is the
    /// pre-conversion figure, which the parsers used to fold into the description.
    var foreignCurrency: String? = nil
    /// Original amount in minor units of `foreignCurrency`.
    var foreignAmountCents: Int? = nil

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
