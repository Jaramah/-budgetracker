import Foundation
import SwiftData

/// Seeds a useful set of default categories the first time the app launches.
/// Budgets are in cents (see `Money`).
enum SampleData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) async {
        let descriptor = FetchDescriptor<Category>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        // (name, symbol, hex, monthlyBudget in cents)
        let defaults: [(String, String, String, Int)] = [
            ("Food & Dining", "fork.knife",            "#FF9F0A", 60000),
            ("Groceries",     "cart.fill",             "#34C759", 40000),
            ("Transport",     "car.fill",              "#5AC8FA", 20000),
            ("Housing",       "house.fill",            "#AF52DE", 0),
            ("Utilities",     "bolt.fill",             "#FFD60A", 15000),
            ("Shopping",      "bag.fill",              "#FF375F", 30000),
            ("Entertainment", "film.fill",             "#BF5AF2", 15000),
            ("Health",        "cross.case.fill",       "#FF6B6B", 0),
            ("Income",        "dollarsign.circle.fill","#30D158", 0)
        ]

        for (i, item) in defaults.enumerated() {
            let c = Category(
                name: item.0,
                symbol: item.1,
                colorHex: item.2,
                monthlyBudgetCents: item.3,
                sortIndex: i
            )
            context.insert(c)
        }

        // A couple of sample bills so the Home dashboard's "Upcoming bills" and
        // the Bills tab aren't empty on first launch.
        let sampleBills: [(String, Int, Int, String)] = [
            ("Rent",    180000, 1,  "house.fill"),
            ("Telco",     4500, 12, "antenna.radiowaves.left.and.right"),
            ("Netflix",   1998, 18, "play.tv.fill")
        ]
        for (i, b) in sampleBills.enumerated() {
            context.insert(Bill(name: b.0, amountCents: b.1, dueDay: b.2,
                                recurrence: .monthly, symbol: b.3, sortIndex: i))
        }

        // A sample savings goal for the Accounts ▸ Goals tab.
        context.insert(Goal(name: "Emergency Fund", targetCents: 1000000,
                            savedCents: 350000, colorHex: "#34D399",
                            symbol: "shield.fill", sortIndex: 0))

        try? context.save()
    }
}
