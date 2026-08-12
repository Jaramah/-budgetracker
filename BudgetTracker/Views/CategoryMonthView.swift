import SwiftUI
import SwiftData

/// The transactions behind one category's monthly total.
///
/// The Budget screen showed a category's spend as a single figure with no way to
/// open it, so "Food & Dining $412.60" could not be checked against the charges
/// that produced it. This is the missing leaf: every transaction in that category
/// for that month, in date order, each one tappable to edit.
///
/// `category` is optional so the same screen can show uncategorised spend, which
/// belongs to no card on the Budget screen and was otherwise unreachable.
struct CategoryMonthView: View {
    let category: Category?
    let month: Date

    @Query private var allTransactions: [Transaction]
    @State private var editing: Transaction?

    private var transactions: [Transaction] {
        allTransactions
            .filter { $0.isExpense && DateHelpers.sameMonth($0.date, month) }
            .filter { tx in
                if let category { return tx.category?.id == category.id }
                return tx.category == nil
            }
            .sorted { $0.date > $1.date }
    }

    private var totalCents: Int { transactions.reduce(0) { $0 + $1.amountCents } }
    private var title: String { category?.name ?? "Uncategorized" }

    /// The largest single charge — usually the first thing you're looking for when
    /// a category's total is higher than expected.
    private var largest: Transaction? {
        transactions.max { $0.amountCents < $1.amountCents }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                if transactions.isEmpty {
                    emptyState
                } else {
                    AuroraCard {
                        VStack(spacing: 0) {
                            ForEach(transactions) { tx in
                                Button { editing = tx } label: {
                                    TransactionRowMini(tx: tx).padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                if tx.id != transactions.last?.id {
                                    Divider().overlay(DS.hairline)
                                }
                            }
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
        }
        .auroraBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { tx in AddTransactionView(existing: tx) }
    }

    private var summaryCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(DateHelpers.monthYearLabel(month))
                    .font(.subheadline).foregroundStyle(DS.inkSecondary)
                MoneyText(cents: totalCents, size: 28)
                HStack(spacing: 12) {
                    Label("\(transactions.count) transaction\(transactions.count == 1 ? "" : "s")",
                          systemImage: "list.bullet")
                    if let largest, transactions.count > 1 {
                        Text("·")
                        Text("largest \(Money.string(largest.amountCents))")
                    }
                }
                .font(.caption).foregroundStyle(DS.inkTertiary)

                if let category, category.monthlyBudgetCents > 0 {
                    let pct = Double(totalCents) / Double(category.monthlyBudgetCents)
                    ProgressBar(value: pct, tint: pct > 1 ? DS.moneyOut : category.color)
                    Text("\(Money.string(category.monthlyBudgetCents)) budget")
                        .font(.caption).foregroundStyle(DS.inkTertiary)
                }
            }
        }
    }

    private var emptyState: some View {
        AuroraCard {
            HStack(spacing: 12) {
                IconChip(symbol: category?.symbol ?? "tag", tint: DS.inkTertiary, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing in \(title) this month")
                        .font(.subheadline.weight(.medium)).foregroundStyle(DS.inkPrimary)
                    Text("Charges filed here in \(DateHelpers.monthYearLabel(month)) will appear in this list.")
                        .font(.caption).foregroundStyle(DS.inkTertiary)
                }
                Spacer()
            }
        }
    }
}
