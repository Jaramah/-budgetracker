import SwiftUI
import SwiftData

/// Budget section with two sub-tabs: Categories (budget-vs-actual per category)
/// and Analytics (by-category breakdown + by-week bars + summary stats).
///
/// Embedded inside the Cards tab (see `AccountsView`), so it provides only its
/// content — the host screen owns the NavigationStack, ScrollView and title.
struct BudgetView: View {
    @EnvironmentObject private var appState: AppState
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @State private var tab = 0

    init() {
        // Marketing capture: open straight to the Analytics sub-tab when asked.
        _tab = State(initialValue: ProcessInfo.processInfo.environment["UI_SCREEN"] == "analytics" ? 1 : 0)
    }

    private var month: Date { appState.selectedMonth }
    private var monthTx: [Transaction] {
        transactions.filter { DateHelpers.sameMonth($0.date, month) && $0.isExpense }
    }
    private var spentCents: Int { monthTx.reduce(0) { $0 + $1.amountCents } }
    private var budgetCents: Int { categories.reduce(0) { $0 + $1.monthlyBudgetCents } }

    var body: some View {
        VStack(spacing: 16) {
            SegmentPills(options: ["Categories", "Analytics"], selection: $tab)
            if tab == 0 { categoriesTab } else { analyticsTab }
        }
    }

    private func spent(for cat: Category) -> Int {
        monthTx.filter { $0.category?.id == cat.id }.reduce(0) { $0 + $1.amountCents }
    }

    // MARK: Categories tab
    private var categoriesTab: some View {
        VStack(spacing: 14) {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Total budget").font(.subheadline).foregroundStyle(DS.inkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        MoneyText(cents: spentCents, size: 28)
                        Text("/ \(Money.string(budgetCents))")
                            .font(.subheadline).foregroundStyle(DS.inkTertiary)
                    }
                    ProgressBar(value: budgetCents > 0 ? Double(spentCents)/Double(budgetCents) : 0)
                }
            }
            ForEach(categories) { cat in
                let s = spent(for: cat)
                let b = cat.monthlyBudgetCents
                let pct = b > 0 ? Double(s)/Double(b) : 0
                AuroraCard {
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            IconChip(symbol: cat.symbol, tint: cat.color, size: 36)
                            Text(cat.name).font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.inkPrimary)
                            Spacer()
                            Text(b > 0 ? "\(Int(pct*100))%" : "—")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(pct > 1 ? DS.moneyOut : DS.inkSecondary)
                        }
                        ProgressBar(value: pct, tint: pct > 1 ? DS.moneyOut : cat.color)
                        HStack {
                            Text("\(Money.string(s)) spent")
                                .font(.caption).foregroundStyle(DS.inkTertiary)
                            Spacer()
                            Text(b > 0 ? "\(Money.string(b)) budget" : "no budget")
                                .font(.caption).foregroundStyle(DS.inkTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Analytics tab
    private var byCategory: [(cat: Category, cents: Int, color: Color)] {
        var out: [(Category, Int, Color)] = []
        for (i, cat) in categories.enumerated() {
            let s = spent(for: cat)
            if s > 0 {
                let color = cat.colorHex.isEmpty ? DS.categoryPalette[i % DS.categoryPalette.count] : cat.color
                out.append((cat, s, color))
            }
        }
        return out.sorted { $0.1 > $1.1 }
    }

    /// Spend not tagged to any category, so the donut represents the full total.
    private var uncategorizedCents: Int {
        max(0, spentCents - byCategory.reduce(0) { $0 + $1.cents })
    }
    private var donutSlices: [(color: Color, value: Int)] {
        var slices: [(color: Color, value: Int)] = byCategory.map { ($0.color, $0.cents) }
        if uncategorizedCents > 0 { slices.append((DS.inkTertiary.opacity(0.5), uncategorizedCents)) }
        return slices
    }

    private var byWeek: [(label: String, cents: Int)] {
        let cal = DateHelpers.calendar
        var buckets = [Int: Int]()
        for tx in monthTx {
            let wk = cal.component(.weekOfMonth, from: tx.date)
            buckets[wk, default: 0] += tx.amountCents
        }
        return (1...5).compactMap { wk in
            buckets[wk].map { ("W\(wk)", $0) }
        }
    }

    private var analyticsTab: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                statTile("Top category", byCategory.first?.cat.name ?? "—")
                statTile("Avg / purchase",
                         monthTx.isEmpty ? "—" : Money.string(spentCents / max(1, monthTx.count)))
            }
            AuroraCard {
                VStack(spacing: 14) {
                    SectionHeader(title: "By category")
                    HStack(spacing: 16) {
                        CategoryDonut(slices: donutSlices,
                                      lineWidth: 16, centerTop: "Total",
                                      centerBottom: Money.string(spentCents))
                            .frame(width: 120, height: 120)
                        VStack(spacing: 8) {
                            ForEach(byCategory.prefix(5), id: \.cat.id) { it in
                                legendRow(color: it.color, name: it.cat.name, cents: it.cents)
                            }
                            if uncategorizedCents > 0 {
                                legendRow(color: DS.inkTertiary.opacity(0.5),
                                          name: "Uncategorized", cents: uncategorizedCents)
                            }
                        }
                    }
                }
            }
            if !byWeek.isEmpty {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "By week")
                        weekBars
                    }
                }
            }
        }
    }

    private func legendRow(color: Color, name: String, cents: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption).foregroundStyle(DS.inkSecondary).lineLimit(1)
            Spacer()
            Text("\(Int(Double(cents)/Double(max(1, spentCents))*100))%")
                .font(.caption.weight(.medium)).foregroundStyle(DS.inkPrimary)
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(DS.inkTertiary)
                Text(value).font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.inkPrimary).lineLimit(1)
            }
        }
    }

    private var weekBars: some View {
        let maxV = max(1, byWeek.map { $0.cents }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 12) {
            ForEach(byWeek, id: \.label) { wk in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.accent)
                        .frame(height: max(6, CGFloat(wk.cents)/CGFloat(maxV) * 120))
                    Text(wk.label).font(.caption2).foregroundStyle(DS.inkTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 150)
    }
}
