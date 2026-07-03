import SwiftUI
import SwiftData

/// Home dashboard — the hero screen. Matches the reference: greeting, a large
/// "Available to spend" card with a budget progress bar and Income/Spent tiles,
/// spending-by-category donut, upcoming bills, and recent activity.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \Bill.sortIndex) private var bills: [Bill]

    var onSeeAllActivity: (() -> Void)? = nil
    var onSeeBills: (() -> Void)? = nil
    var onSeeCategories: (() -> Void)? = nil

    private var month: Date { appState.selectedMonth }

    private var monthTx: [Transaction] {
        transactions.filter { DateHelpers.sameMonth($0.date, month) }
    }
    private var spentCents: Int {
        monthTx.filter { $0.isExpense }.reduce(0) { $0 + $1.amountCents }
    }
    private var incomeCents: Int {
        monthTx.filter { !$0.isExpense }.reduce(0) { $0 + $1.amountCents }
    }
    private var budgetCents: Int {
        categories.reduce(0) { $0 + $1.monthlyBudgetCents }
    }
    private var availableCents: Int { max(0, budgetCents - spentCents) }
    private var budgetProgress: Double {
        guard budgetCents > 0 else { return 0 }
        return Double(spentCents) / Double(budgetCents)
    }

    private var categorySpend: [(cat: Category, cents: Int, color: Color)] {
        var out: [(Category, Int, Color)] = []
        for (i, cat) in categories.enumerated() {
            let sum = monthTx.filter { $0.isExpense && $0.category?.id == cat.id }
                .reduce(0) { $0 + $1.amountCents }
            if sum > 0 {
                let color = cat.colorHex.isEmpty ? DS.categoryPalette[i % DS.categoryPalette.count] : cat.color
                out.append((cat, sum, color))
            }
        }
        return out.sorted { $0.1 > $1.1 }
    }

    private var upcomingBills: [Bill] {
        bills.filter { !$0.isPaid(in: .now) }
            .sorted { $0.nextDueDate() < $1.nextDueDate() }
            .prefix(3).map { $0 }
    }

    private var recentTx: [Transaction] {
        transactions.sorted { $0.date > $1.date }.prefix(4).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    greeting
                    availableCard
                    if !categorySpend.isEmpty { categoryCard }
                    if !upcomingBills.isEmpty { billsCard }
                    recentCard
                    Color.clear.frame(height: 72) // space for tab bar
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .auroraBackground()
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Greeting
    private var greeting: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateHelpers.monthYearLabel(month))
                    .font(.caption).foregroundStyle(DS.inkTertiary)
                Text(greetingText)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DS.inkPrimary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var greetingText: String {
        let h = DateHelpers.calendar.component(.hour, from: .now)
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    // MARK: Available-to-spend hero card
    private var availableCard: some View {
        AuroraCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Available to spend")
                    .font(.subheadline).foregroundStyle(DS.inkSecondary)
                MoneyText(cents: availableCents, size: 40, color: DS.inkPrimary)

                ProgressBar(value: budgetProgress,
                            tint: budgetProgress > 1 ? DS.moneyOut : DS.accent)

                HStack {
                    Text("\(Money.string(spentCents)) spent")
                        .font(.caption).foregroundStyle(DS.inkTertiary)
                    Spacer()
                    Text("\(Money.string(budgetCents)) budget")
                        .font(.caption).foregroundStyle(DS.inkTertiary)
                }

                HStack(spacing: 12) {
                    miniTile("Income", incomeCents, DS.moneyIn, "arrow.down.left")
                    miniTile("Spent", spentCents, DS.moneyOut, "arrow.up.right")
                }
            }
        }
    }

    private func miniTile(_ label: String, _ cents: Int, _ tint: Color, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            IconChip(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundStyle(DS.inkTertiary)
                Text(Money.string(cents))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(DS.inkPrimary)
            }
            Spacer()
        }
        .padding(10)
        .background(DS.bgCardHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Category card
    private var categoryCard: some View {
        AuroraCard {
            VStack(spacing: 14) {
                SectionHeader(title: "Spending by category",
                              actionLabel: "See all", action: onSeeCategories)
                HStack(spacing: 16) {
                    CategoryDonut(
                        slices: categorySpend.map { ($0.color, $0.cents) },
                        lineWidth: 16,
                        centerTop: "Spent",
                        centerBottom: Money.string(spentCents)
                    )
                    .frame(width: 120, height: 120)

                    VStack(spacing: 10) {
                        ForEach(categorySpend.prefix(4), id: \.cat.id) { item in
                            HStack(spacing: 8) {
                                Circle().fill(item.color).frame(width: 8, height: 8)
                                Text(item.cat.name)
                                    .font(.caption).foregroundStyle(DS.inkSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(Money.string(item.cents))
                                    .font(.caption.weight(.medium)).monospacedDigit()
                                    .foregroundStyle(DS.inkPrimary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Bills card
    private var billsCard: some View {
        AuroraCard {
            VStack(spacing: 12) {
                SectionHeader(title: "Upcoming bills",
                              actionLabel: "See all", action: onSeeBills)
                ForEach(upcomingBills) { bill in
                    HStack(spacing: 12) {
                        IconChip(symbol: bill.symbol, tint: DS.accent, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.name).font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.inkPrimary)
                            Text("Due \(DateHelpers.mediumDate(bill.nextDueDate()))")
                                .font(.caption).foregroundStyle(DS.inkTertiary)
                        }
                        Spacer()
                        Text(Money.string(bill.amountCents))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(DS.inkPrimary)
                    }
                }
            }
        }
    }

    // MARK: Recent activity card
    private var recentCard: some View {
        AuroraCard {
            VStack(spacing: 12) {
                SectionHeader(title: "Recent activity",
                              actionLabel: "See all", action: onSeeAllActivity)
                if recentTx.isEmpty {
                    Text("No transactions yet. Tap + to add one.")
                        .font(.caption).foregroundStyle(DS.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(recentTx) { tx in
                        TransactionRowMini(tx: tx)
                    }
                }
            }
        }
    }
}

/// Compact transaction row used on the dashboard.
struct TransactionRowMini: View {
    let tx: Transaction
    var body: some View {
        HStack(spacing: 12) {
            IconChip(symbol: tx.category?.symbol ?? "circle.grid.2x2",
                     tint: tx.category?.color ?? DS.inkTertiary, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.note.isEmpty ? (tx.category?.name ?? "Transaction") : tx.note)
                    .font(.subheadline.weight(.medium)).foregroundStyle(DS.inkPrimary)
                    .lineLimit(1)
                Text(DateHelpers.mediumDate(tx.date))
                    .font(.caption).foregroundStyle(DS.inkTertiary)
            }
            Spacer()
            Text(Money.signedString(tx.amountCents, isExpense: tx.isExpense))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(tx.isExpense ? DS.inkPrimary : DS.moneyIn)
        }
    }
}
