import SwiftUI
import SwiftData

/// Reconcile an imported statement against the user's logged CREDIT transactions.
///
/// Philosophy (matches "reconcile, don't guess"): we auto-SUGGEST matches by
/// amount + nearby date, but the user confirms each one. We surface three buckets:
///   1. Matched lines
///   2. Statement lines with no logged transaction  → "on statement, not logged"
///   3. Logged credit transactions not on the statement → "logged, not on statement"
/// The header tallies statement total vs logged total and flags the difference.
struct ReconciliationView: View {
    @Environment(\.modelContext) private var context
    @Bindable var statement: StatementImport

    @Query private var allTransactions: [Transaction]

    /// Logged credit-card expenses (candidates for matching).
    private var creditTransactions: [Transaction] {
        allTransactions.filter { $0.isExpense && $0.paymentMethod == .credit }
    }

    private var lines: [StatementLine] {
        (statement.lines ?? []).sorted { $0.date < $1.date }
    }

    private var charges: [StatementLine] { lines.filter { $0.isCharge } }

    // Totals (cents)
    private var statementChargeTotalCents: Int { charges.reduce(0) { $0 + $1.amountCents } }
    private var matchedTotalCents: Int {
        charges.filter { $0.isMatched }.reduce(0) { $0 + $1.amountCents }
    }
    private var differenceCents: Int { statementChargeTotalCents - matchedTotalCents }

    /// Logged credit transactions that aren't linked to any line on this statement.
    private var unmatchedTransactions: [Transaction] {
        let matchedIDs = Set(lines.compactMap { $0.matchedTransactionID })
        return creditTransactions.filter { !matchedIDs.contains($0.id) }
    }

    var body: some View {
        List {
            summarySection

            Section {
                ForEach(charges) { line in
                    lineRow(line)
                }
            } header: {
                Text("Statement charges (\(charges.count))")
            } footer: {
                Text("Tap a row to match it to a logged credit transaction, or mark it as logged. Matching helps confirm every charge is accounted for.")
            }

            if !unmatchedTransactions.isEmpty {
                Section("Logged credit — not yet on this statement") {
                    ForEach(unmatchedTransactions) { tx in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tx.note.isEmpty ? (tx.category?.name ?? "Transaction") : tx.note)
                                Text(DateHelpers.mediumDate(tx.date))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.string(tx.amountCents))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reconcile")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header summary

    private var summarySection: some View {
        Section {
            LabeledContent("Statement charges", value: Money.string(statementChargeTotalCents))
            LabeledContent("Matched to logged", value: Money.string(matchedTotalCents))
            HStack {
                Text("Difference")
                    .fontWeight(.semibold)
                Spacer()
                Text(Money.string(differenceCents))
                    .fontWeight(.semibold)
                    .foregroundStyle(differenceCents == 0 ? .green : .orange)
            }
            if differenceCents == 0 && !charges.isEmpty {
                Label("Fully reconciled 🎉", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if !charges.isEmpty {
                Label("\(charges.filter { !$0.isMatched }.count) charge(s) still unmatched",
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        } header: {
            Text(statement.label.isEmpty ? statement.fileName : statement.label)
        }
    }

    // MARK: Per-line row with match menu

    private func lineRow(_ line: StatementLine) -> some View {
        let matchedTx = creditTransactions.first { $0.id == line.matchedTransactionID }
        // Suggestions: same amount (to the cent). Within-window first, then others,
        // each sorted by date proximity to the statement line.
        let sameAmount = creditTransactions.filter {
            TransactionMatcher.sameAmount($0.amountCents, line.amountCents)
        }
        let inWindow = sameAmount
            .filter { TransactionMatcher.withinWindow($0.date, line.date, days: TransactionMatcher.windowDays) }
            .sorted { abs($0.date.timeIntervalSince(line.date)) < abs($1.date.timeIntervalSince(line.date)) }
        let outWindow = sameAmount
            .filter { !TransactionMatcher.withinWindow($0.date, line.date, days: TransactionMatcher.windowDays) }
            .sorted { abs($0.date.timeIntervalSince(line.date)) < abs($1.date.timeIntervalSince(line.date)) }
        let suggestions = inWindow + outWindow

        return Menu {
            if let matchedTx {
                Button(role: .destructive) {
                    unmatch(line, tx: matchedTx)
                } label: {
                    Label("Unmatch", systemImage: "xmark.circle")
                }
            }
            if suggestions.isEmpty {
                Text("No logged credit transaction with this amount")
            } else {
                ForEach(suggestions) { tx in
                    Button {
                        match(line, to: tx)
                    } label: {
                        Text("\(DateHelpers.mediumDate(tx.date)) · \(tx.note.isEmpty ? (tx.category?.name ?? "Transaction") : tx.note)")
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: line.isMatched ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(line.isMatched ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.desc).foregroundStyle(.primary).lineLimit(1)
                    Text(DateHelpers.mediumDate(line.date))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.string(line.amountCents))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: Match actions

    private func match(_ line: StatementLine, to tx: Transaction) {
        line.matchedTransactionID = tx.id
        tx.isReconciled = true
        try? context.save()
    }

    private func unmatch(_ line: StatementLine, tx: Transaction) {
        line.matchedTransactionID = nil
        tx.isReconciled = false
        try? context.save()
    }
}
