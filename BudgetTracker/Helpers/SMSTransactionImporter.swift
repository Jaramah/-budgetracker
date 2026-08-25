import Foundation
import SwiftData

/// Turns a bank alert SMS into a saved transaction.
///
/// Split out of the App Intent so the decision-making is testable on its own —
/// intents are awkward to exercise from XCTest, and the parts worth pinning here
/// are the duplicate guard and the refusal to save unrecognised text.
enum SMSTransactionImporter {

    enum Outcome: Equatable {
        /// Saved. Carries a short line the Shortcut can speak or show.
        case added(summary: String)
        /// A matching transaction already exists, so nothing was written.
        case duplicate(summary: String)
        /// The text isn't a bank alert. Nothing written.
        case notRecognised
    }

    /// How close two rows must be to count as the same alert arriving twice.
    ///
    /// An automation can fire more than once for a single message — a retry, or
    /// the user re-running it — and unattended double-entry is worse than a missed
    /// one, because nothing prompts anyone to look.
    static let duplicateWindow: TimeInterval = 60 * 60 * 6

    @discardableResult
    static func importAlert(_ text: String,
                            context: ModelContext,
                            now: Date = .now) -> Outcome {
        guard let parsed = SMSTransactionParser.parse(text) else { return .notRecognised }

        let date = parsed.date ?? now
        let existing = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []

        if let dupe = existing.first(where: { isSameAlert($0, parsed: parsed, date: date) }) {
            return .duplicate(summary: summary(for: dupe.amountCents,
                                               isExpense: dupe.isExpense,
                                               note: dupe.note,
                                               prefix: "Already logged"))
        }

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let category = AutoCategorizer.category(for: parsed.counterparty ?? parsed.suggestedNote,
                                                from: categories)

        let tx = Transaction(
            amountCents: parsed.amountCents,
            isExpense: !parsed.isIncoming,
            note: parsed.suggestedNote,
            date: date,
            category: category,
            // PayNow leaves a bank account rather than a card, so it is not
            // credit — mislabelling it would corrupt card reconciliation.
            paymentMethod: .cash
        )
        tx.createdFromSMS = true
        context.insert(tx)
        try? context.save()

        return .added(summary: summary(for: tx.amountCents,
                                       isExpense: tx.isExpense,
                                       note: tx.note,
                                       prefix: parsed.isIncoming ? "Logged received" : "Logged"))
    }

    /// Same amount, same direction, same payee, close in time.
    static func isSameAlert(_ tx: Transaction,
                            parsed: SMSTransactionParser.Result,
                            date: Date) -> Bool {
        tx.amountCents == parsed.amountCents
            && tx.isExpense == !parsed.isIncoming
            && tx.note.caseInsensitiveCompare(parsed.suggestedNote) == .orderedSame
            && abs(tx.date.timeIntervalSince(date)) <= duplicateWindow
    }

    private static func summary(for cents: Int, isExpense: Bool, note: String, prefix: String) -> String {
        "\(prefix) \(Money.string(cents)) — \(note)"
    }
}
