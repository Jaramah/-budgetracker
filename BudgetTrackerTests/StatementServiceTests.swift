import XCTest
import SwiftData
@testable import BudgetTracker

/// Locks the "delete a statement → clean up its transactions" invariant against a
/// real in-memory SwiftData store, so it can't silently regress:
///   • rows the import CREATED are deleted,
///   • rows it merely MATCHED are kept but un-reconciled,
///   • the statement and its lines are gone.
@MainActor
final class StatementServiceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Transaction.self, BudgetTracker.Category.self, StatementImport.self,
                             StatementLine.self, CreditCardAccount.self, Bill.self, Goal.self,
                             RecurringRule.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    func testDelete_removesCreatedKeepsMatchedAndCascadesLines() throws {
        let ctx = try makeContext()

        // A transaction the user logged themselves (statement will MATCH it).
        let preexisting = Transaction(amountCents: 5780, isExpense: true, note: "KFC",
                                      date: .now, paymentMethod: .credit,
                                      isReconciled: false, createdFromStatement: false)
        // A transaction the import CREATED.
        let imported = Transaction(amountCents: 2099, isExpense: true, note: "GOMO",
                                   date: .now, paymentMethod: .credit,
                                   isReconciled: true, createdFromStatement: true)
        // An unrelated transaction that must be untouched.
        let unrelated = Transaction(amountCents: 1000, isExpense: true, note: "Cash lunch",
                                    date: .now)
        ctx.insert(preexisting); ctx.insert(imported); ctx.insert(unrelated)

        let statement = StatementImport(fileName: "dbs.pdf", statementTotalCents: 7879)
        ctx.insert(statement)
        let matchedLine = StatementLine(date: .now, desc: "KFC", amountCents: 5780,
                                        matchedTransactionID: preexisting.id)
        let createdLine = StatementLine(date: .now, desc: "GOMO", amountCents: 2099,
                                        matchedTransactionID: imported.id)
        matchedLine.statement = statement; createdLine.statement = statement
        ctx.insert(matchedLine); ctx.insert(createdLine)
        preexisting.isReconciled = true   // reconciled by this statement
        try ctx.save()

        let deleted = StatementService.delete(
            statement, transactions: [preexisting, imported, unrelated], context: ctx)
        XCTAssertEqual(deleted, 1, "only the import-created transaction is deleted")

        let txns = try ctx.fetch(FetchDescriptor<Transaction>())
        let notes = Set(txns.map(\.note))
        XCTAssertTrue(notes.contains("KFC"), "user-logged matched transaction is kept")
        XCTAssertFalse(notes.contains("GOMO"), "import-created transaction is deleted")
        XCTAssertTrue(notes.contains("Cash lunch"), "unrelated transaction untouched")
        XCTAssertEqual(txns.first { $0.note == "KFC" }?.isReconciled, false,
                       "kept transaction is un-reconciled")

        XCTAssertTrue(try ctx.fetch(FetchDescriptor<StatementImport>()).isEmpty,
                      "statement removed")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<StatementLine>()).isEmpty,
                      "statement lines cascade-deleted")
    }

    func testDelete_withNoTransactionsJustRemovesStatement() throws {
        let ctx = try makeContext()
        let statement = StatementImport(fileName: "empty.pdf")
        ctx.insert(statement)
        try ctx.save()

        let deleted = StatementService.delete(statement, transactions: [], context: ctx)
        XCTAssertEqual(deleted, 0)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<StatementImport>()).isEmpty)
    }
}
