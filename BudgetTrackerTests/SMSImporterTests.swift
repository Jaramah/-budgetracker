import XCTest
import SwiftData
@testable import BudgetTracker

/// Saving a bank alert unattended.
///
/// This runs from a Shortcuts automation with nobody watching, which changes what
/// matters: a double entry is worse than a missed one, because nothing prompts
/// anyone to look. Most of these pin what must NOT be written.
@MainActor
final class SMSImporterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([BudgetTracker.Category.self, Transaction.self, Subscription.self,
                             CreditCardAccount.self, StatementImport.self, StatementLine.self,
                             RecurringRule.self, Goal.self, Bill.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func all(_ ctx: ModelContext) -> [Transaction] {
        (try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []
    }

    private let outgoing = "You have made a PayNow transfer of SGD25.00 to JOHN TAN on 25 Aug 2026."
    private let incoming = "You have received SGD30.00 via PayNow from MARY LIM on 25 Aug 2026."

    // MARK: Saving

    func testLogsAnOutgoingTransferAsSpending() throws {
        let ctx = try makeContext()
        let outcome = SMSTransactionImporter.importAlert(outgoing, context: ctx)

        guard case .added = outcome else { return XCTFail("expected it to be added, got \(outcome)") }
        let txs = all(ctx)
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].amountCents, 2500)
        XCTAssertTrue(txs[0].isExpense)
        XCTAssertEqual(txs[0].note, "PayNow to JOHN TAN")
        XCTAssertTrue(txs[0].createdFromSMS, "rows that arrived unattended must be auditable")
    }

    func testLogsAReceivedTransferAsIncome() throws {
        let ctx = try makeContext()
        SMSTransactionImporter.importAlert(incoming, context: ctx)
        let txs = all(ctx)
        XCTAssertEqual(txs.count, 1)
        XCTAssertFalse(txs[0].isExpense, "money received is income, not spending")
        XCTAssertEqual(txs[0].amountCents, 3000)
    }

    /// PayNow leaves a bank account, not a card. Labelling it credit would put it
    /// into card reconciliation, where no statement line will ever match it.
    func testTransfersAreNotLabelledAsCardSpending() throws {
        let ctx = try makeContext()
        SMSTransactionImporter.importAlert(outgoing, context: ctx)
        XCTAssertEqual(all(ctx).first?.paymentMethod, .cash)
    }

    func testAppliesAutoCategory() throws {
        let ctx = try makeContext()
        let transport = BudgetTracker.Category(name: "Transport")
        ctx.insert(transport)
        SMSTransactionImporter.importAlert(
            "You have made a PayNow payment of S$12.00 to GRAB SINGAPORE.", context: ctx)
        XCTAssertEqual(all(ctx).first?.category?.name, "Transport")
    }

    // MARK: Must NOT be written

    /// An automation can fire twice for one message. The second must be a no-op.
    func testTheSameAlertTwiceLogsOnce() throws {
        let ctx = try makeContext()
        SMSTransactionImporter.importAlert(outgoing, context: ctx)
        let second = SMSTransactionImporter.importAlert(outgoing, context: ctx)

        guard case .duplicate = second else { return XCTFail("expected a duplicate, got \(second)") }
        XCTAssertEqual(all(ctx).count, 1, "unattended double-entry is worse than a missed entry")
    }

    /// A genuine second payment of the same amount, well outside the window, is
    /// not a duplicate — the guard must not swallow real transactions.
    func testAnIdenticalAlertOnAnotherDayIsNotADuplicate() throws {
        let ctx = try makeContext()
        SMSTransactionImporter.importAlert(
            "You have made a PayNow transfer of SGD25.00 to JOHN TAN on 25 Aug 2026.", context: ctx)
        SMSTransactionImporter.importAlert(
            "You have made a PayNow transfer of SGD25.00 to JOHN TAN on 28 Aug 2026.", context: ctx)
        XCTAssertEqual(all(ctx).count, 2, "a real repeat payment must still be logged")
    }

    func testUnrecognisedTextWritesNothing() throws {
        let ctx = try makeContext()
        for junk in ["Hi, are we still on for dinner?",
                     "Your OTP is 123456. Do not share it.",
                     "Your PayNow transfer failed.",
                     ""] {
            XCTAssertEqual(SMSTransactionImporter.importAlert(junk, context: ctx), .notRecognised,
                           "\(junk.prefix(24)) should not be logged")
        }
        XCTAssertTrue(all(ctx).isEmpty)
    }

    /// A different payee at the same amount and time is a different payment.
    func testDifferentPayeeIsNotADuplicate() throws {
        let ctx = try makeContext()
        SMSTransactionImporter.importAlert(outgoing, context: ctx)
        SMSTransactionImporter.importAlert(
            "You have made a PayNow transfer of SGD25.00 to MARY LIM on 25 Aug 2026.", context: ctx)
        XCTAssertEqual(all(ctx).count, 2)
    }
}
