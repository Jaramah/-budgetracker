import Foundation
import SwiftData

/// Generates concrete `Transaction` rows from active `RecurringRule`s whose
/// `nextRunDate` has arrived. Idempotent: it advances each rule's `nextRunDate`
/// past every posted occurrence, and guards against double-posting by checking
/// for an existing recurring transaction with the same rule/date/amount.
///
/// Call once on app launch (see BudgetTrackerApp).
enum RecurringMaterializer {

    /// Post all due occurrences up to and including `now`. Returns the count posted.
    @discardableResult
    static func run(context: ModelContext, now: Date = .now) -> Int {
        let cal = DateHelpers.calendar
        let today = cal.startOfDay(for: now)

        let rules: [RecurringRule]
        do {
            rules = try context.fetch(FetchDescriptor<RecurringRule>())
        } catch {
            return 0
        }

        var posted = 0
        for rule in rules where rule.isActive {
            // Safety valve: never loop more than 60 catch-up occurrences per launch.
            var guardCount = 0
            while rule.nextRunDate <= today && guardCount < 60 {
                if let end = rule.endDate, rule.nextRunDate > end {
                    rule.isActive = false
                    break
                }
                let occurrence = rule.nextRunDate
                if !alreadyPosted(ruleID: rule.id, on: occurrence, in: context) {
                    let tx = Transaction(
                        amountCents: rule.amountCents,
                        isExpense: rule.isExpense,
                        note: rule.note.isEmpty ? "Recurring" : rule.note,
                        date: occurrence,
                        category: rule.category,
                        paymentMethod: rule.paymentMethod,
                        isReconciled: false,
                        createdFromStatement: false,
                        cardID: rule.cardID,
                        isRecurring: true,
                        ruleID: rule.id
                    )
                    context.insert(tx)
                    posted += 1
                }
                rule.advance()
                guardCount += 1
            }
        }
        // Always save, not just when `posted > 0` — `rule.advance()` and the
        // `isActive = false` expiry branch above both mutate model state even
        // on iterations where nothing was inserted (e.g. every due occurrence
        // was already posted, or a rule just crossed its endDate), and that
        // state should never depend on incidental autosave.
        try? context.save()
        return posted
    }

    /// True if a recurring transaction for this rule already exists on the same
    /// calendar day — prevents duplicates across launches. Keyed by `ruleID`
    /// rather than amount+note: two rules can share both (e.g. two "Recurring"-
    /// labeled rules for the same amount), and editing a rule's amount/note
    /// would otherwise stop matching its own already-posted occurrence.
    private static func alreadyPosted(ruleID: UUID, on date: Date, in context: ModelContext) -> Bool {
        let cal = DateHelpers.calendar
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.ruleID == ruleID &&
                tx.date >= dayStart &&
                tx.date < dayEnd
            }
        )
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        return !existing.isEmpty
    }
}
