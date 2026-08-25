import Foundation
import SwiftData

/// The app's single SwiftData container.
///
/// This used to be built inside `BudgetTrackerApp.init`, which made it reachable
/// only from the SwiftUI hierarchy. App Intents run outside that hierarchy — a
/// Shortcuts automation can invoke one with the app not on screen — so the
/// container has to live somewhere both can reach, or the intent would write to a
/// second store and its transactions would never appear in the app.
enum SharedModelContainer {

    static let schema = Schema([
        Category.self,
        Transaction.self,
        StatementImport.self,
        StatementLine.self,
        CreditCardAccount.self,
        RecurringRule.self,
        Goal.self,
        Bill.self,
        Subscription.self
    ])

    static let shared: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Self-heal: wipe an incompatible on-disk store rather than crashing.
            deleteStoreFiles()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }
    }()

    private static func deleteStoreFiles() {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
