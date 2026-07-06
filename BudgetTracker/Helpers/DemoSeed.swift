import Foundation
import SwiftData

/// Populates the store with realistic demo content **only** for App Store
/// screenshots / previews. Gated behind the `DEMO_SEED=1` launch environment
/// variable, so it can never run in a shipped build or normal launch.
///
/// Generate marketing assets with, e.g.:
///   xcrun simctl launch --console <udid> com.github.jaramah.BudgetTracker DEMO_SEED=1
enum DemoSeed {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DEMO_SEED"] == "1"
    }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard isEnabled else { return }
        // Idempotent: only seed an otherwise-empty ledger.
        let existing = (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0
        guard existing == 0 else { return }

        let cats = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        func category(_ name: String) -> Category? { cats.first { $0.name == name } }

        let cal = DateHelpers.calendar
        let monthStart = DateHelpers.startOfMonth(.now)
        func day(_ d: Int) -> Date { cal.date(byAdding: .day, value: d - 1, to: monthStart) ?? monthStart }

        // A few cards so the Cards tab looks lived-in.
        let cardSpecs: [(Bank, String, String, Int)] = [
            (.standardChartered, "Journey", "0697", 2_520_000),
            (.dbs, "Altitude", "1234", 800_000),
            (.ocbc, "365", "4030", 960_000)
        ]
        var cardIDs: [UUID] = []
        for (i, c) in cardSpecs.enumerated() {
            let card = CreditCardAccount(bank: c.0, nickname: c.1, last4: c.2,
                                         statementDay: 25, paymentDueDay: 17,
                                         creditLimitCents: c.3, sortIndex: i)
            cardIDs.append(card.id)
            context.insert(card)
        }

        // Current-month spending with a rich category mix (merchant, category, $, day).
        let rows: [(String, String, Double, Int)] = [
            ("Grab", "Transport", 12.40, 1),
            ("Cold Storage", "Groceries", 62.10, 1),
            ("Starbucks", "Food & Dining", 8.50, 1),
            ("Spotify Premium", "Entertainment", 21.19, 2),
            ("BUS/MRT", "Transport", 5.53, 2),
            ("Din Tai Fung", "Food & Dining", 43.04, 2),
            ("Uniqlo", "Shopping", 79.90, 3),
            ("GOMO by Singtel", "Utilities", 20.99, 3),
            ("FairPrice", "Groceries", 45.57, 3),
            ("Guardian Pharmacy", "Health", 18.90, 3),
            ("Grab", "Transport", 9.00, 4),
            ("Netflix", "Entertainment", 19.98, 4),
            ("McDonald's", "Food & Dining", 11.75, 4),
            ("Apple Store", "Shopping", 199.00, 5),
            ("Sheng Siong", "Groceries", 33.20, 5),
            ("Kopitiam", "Food & Dining", 5.80, 5),
            ("IKEA", "Shopping", 88.00, 5)
        ]
        for (i, r) in rows.enumerated() {
            let tx = Transaction(
                amountCents: Money.centsFromDouble(r.2),
                isExpense: true,
                note: r.0,
                date: day(r.3),
                category: category(r.1),
                paymentMethod: .credit,
                createdFromStatement: true,
                cardID: cardIDs[i % cardIDs.count])
            context.insert(tx)
        }
        try? context.save()
    }
}
