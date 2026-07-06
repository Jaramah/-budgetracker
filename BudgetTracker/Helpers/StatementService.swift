import Foundation
import SwiftData

/// Statement-level operations that mutate the store. Extracted from the views so
/// the delete invariant (which transactions survive a statement deletion) can be
/// unit-tested and can't silently regress.
enum StatementService {

    /// Delete a statement and reconcile the transactions it touched:
    ///   • A transaction this statement **created** (`createdFromStatement`) is
    ///     deleted along with the statement — it only existed because of the import.
    ///   • A transaction the statement merely **matched** (the user had already
    ///     logged it) is **kept**, but un-reconciled, since the statement that
    ///     reconciled it is gone.
    /// The statement's own `StatementLine`s are removed by the `.cascade` relationship.
    ///
    /// - Returns: the number of transactions deleted (for feedback/telemetry).
    @discardableResult
    static func delete(_ statement: StatementImport,
                       transactions: [Transaction],
                       context: ModelContext) -> Int {
        let matchedIDs = Set((statement.lines ?? []).compactMap { $0.matchedTransactionID })
        var deleted = 0
        for tx in transactions where matchedIDs.contains(tx.id) {
            if tx.createdFromStatement {
                context.delete(tx)
                deleted += 1
            } else {
                tx.isReconciled = false
            }
        }
        context.delete(statement)   // cascades to the statement's StatementLines
        try? context.save()
        return deleted
    }
}
