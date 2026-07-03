import SwiftUI
import SwiftData

/// Activity screen — all transactions, filterable, grouped by date. Matches the
/// reference's "Transactions" list with a filter row and date group headers.
struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var search = ""
    @State private var filterCategoryID: UUID? = nil
    @State private var editing: Transaction?

    private var filtered: [Transaction] {
        transactions
            .filter { tx in
                filterCategoryID == nil || tx.category?.id == filterCategoryID
            }
            .filter { tx in
                search.isEmpty ||
                tx.note.localizedCaseInsensitiveContains(search) ||
                (tx.category?.name.localizedCaseInsensitiveContains(search) ?? false)
            }
            .sorted { $0.date > $1.date }
    }

    /// Group by day label.
    private var groups: [(label: String, items: [Transaction])] {
        let cal = DateHelpers.calendar
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            (DateHelpers.mediumDate(day), grouped[day]!.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    filterChips
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups, id: \.label) { grp in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(grp.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DS.inkTertiary)
                                AuroraCard(padding: 8) {
                                    VStack(spacing: 0) {
                                        ForEach(grp.items) { tx in
                                            Button { editing = tx } label: {
                                                TransactionRowMini(tx: tx).padding(8)
                                            }
                                            .buttonStyle(.plain)
                                            if tx.id != grp.items.last?.id {
                                                Divider().overlay(DS.hairline)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Color.clear.frame(height: 72)
                }
                .padding(.horizontal, 16)
            }
            .auroraBackground()
            .navigationTitle("Activity")
            .searchable(text: $search, prompt: "Search transactions")
            .sheet(item: $editing) { tx in
                AddTransactionView(existing: tx)
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: filterCategoryID == nil) { filterCategoryID = nil }
                ForEach(categories) { cat in
                    chip(cat.name, active: filterCategoryID == cat.id) {
                        filterCategoryID = (filterCategoryID == cat.id) ? nil : cat.id
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(active ? DS.inkPrimary : DS.inkSecondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(active ? DS.accent : DS.bgCard,
                            in: Capsule())
                .overlay(Capsule().strokeBorder(active ? Color.clear : DS.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(DS.inkTertiary)
            Text("No transactions in this filter yet.")
                .font(.subheadline).foregroundStyle(DS.inkTertiary)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}
