import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// A single card's page: card visual, billing info, its statements, and the
/// PDF-only "Upload Statement" button that routes the statement to THIS card.
struct AccountDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    let card: CreditCardAccount

    @Query private var allStatements: [StatementImport]
    @Query private var transactions: [Transaction]

    @State private var editing = false
    @State private var showImporter = false
    @State private var pendingLines: [StatementParser.ParsedLine] = []
    @State private var pendingFileName = ""
    @State private var pendingBank: Bank = .unknown
    @State private var pendingMeta = StatementParser.StatementMeta()
    @State private var pendingDeclaredTotal: Int?
    @State private var pendingReconciled: Bool?
    @State private var showReview = false
    @State private var errorMessage: String?

    private var statements: [StatementImport] {
        allStatements.filter { $0.cardID == card.id }.sorted { $0.importedAt > $1.importedAt }
    }
    private var balance: Int {
        transactions.filter { $0.cardID == card.id && $0.isExpense }.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(card.displayName).font(.headline).foregroundStyle(DS.inkPrimary)
                        HStack(spacing: 12) {
                            infoPill("Balance", Money.string(balance))
                            // Show the resolved date, not the bare day-of-month.
                            // "Due day 7" is ambiguous — a statement cut on the
                            // 19th is due the 7th of the *following* month, and
                            // the number alone hides that entirely.
                            if let due = card.nextDueDate() {
                                infoPill("Next due", DateHelpers.mediumDate(due))
                            }
                            if card.statementDay > 0 { infoPill("Stmt day", "\(card.statementDay)") }
                        }
                        if let days = card.daysUntilDue() {
                            Text(days == 0 ? "Due today"
                                 : days == 1 ? "Due tomorrow"
                                 : "Due in \(days) days")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(days <= 3 ? DS.warning : DS.inkTertiary)
                        }
                    }
                }

                Button { showImporter = true } label: {
                    Label("Upload Statement (PDF)", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(DS.accent, in: RoundedRectangle(cornerRadius: DS.corner))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                AuroraCard {
                    VStack(spacing: 12) {
                        SectionHeader(title: "Statements")
                        if statements.isEmpty {
                            Text("No statements uploaded for this card yet.")
                                .font(.caption).foregroundStyle(DS.inkTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(statements) { st in
                                NavigationLink { ReconciliationView(statement: st) } label: {
                                    statementRow(st)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteStatement(st)
                                    } label: {
                                        Label("Delete Statement", systemImage: "trash")
                                    }
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
        .navigationTitle(card.bank.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) { CardEditView(card: card) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showReview) {
            StatementReviewView(fileName: pendingFileName, lines: pendingLines,
                                detectedBank: pendingBank,
                                meta: pendingMeta,
                                declaredTotalCents: pendingDeclaredTotal,
                                reconciled: pendingReconciled,
                                preselectedCardID: card.id)
                .environmentObject(appState)
        }
        .alert("Import problem", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func infoPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(DS.inkPrimary)
            Text(label).font(.caption2).foregroundStyle(DS.inkTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(DS.bgCardHi, in: RoundedRectangle(cornerRadius: 10))
    }

    private func statementRow(_ st: StatementImport) -> some View {
        let total = st.lines?.count ?? 0
        let matched = st.lines?.filter { $0.isMatched }.count ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Text(st.label.isEmpty ? st.fileName : st.label)
                .font(.subheadline.weight(.medium)).foregroundStyle(DS.inkPrimary)
            HStack(spacing: 8) {
                Text(DateHelpers.mediumDate(st.importedAt))
                Text("•"); Text("\(matched)/\(total) matched")
            }
            .font(.caption).foregroundStyle(DS.inkTertiary)
            Text("Statement total: \(Money.string(st.statementTotalCents))")
                .font(.caption.monospacedDigit()).foregroundStyle(DS.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err): errorMessage = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let stop = url.startAccessingSecurityScopedResource()
            defer { if stop { url.stopAccessingSecurityScopedResource() } }
            let fileName = url.lastPathComponent
            if allStatements.contains(where: { $0.fileName.caseInsensitiveCompare(fileName) == .orderedSame }) {
                errorMessage = "\(fileName) has already been uploaded. Delete the existing statement first before re-uploading it."
                return
            }
            do {
                let parsed = try StatementParser.parseDetailed(url: url)
                let lines = parsed.lines
                let total = lines.filter { $0.amountCents > 0 }.reduce(0) { $0 + $1.amountCents }
                if total > 0, allStatements.contains(where: { $0.statementTotalCents == total }) {
                    errorMessage = "A statement with the same total (\(Money.string(total))) already exists. Rename the file or delete the existing one first."
                    return
                }
                pendingLines = lines; pendingFileName = fileName
                pendingMeta = parsed.meta
                pendingDeclaredTotal = parsed.declaredTotalCents
                pendingReconciled = parsed.reconciled
                pendingBank = BankDetector.detect(url: url); showReview = true
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func deleteStatement(_ st: StatementImport) {
        // Delete the statement and reconcile the transactions it touched. See
        // `StatementService.delete` for the invariant (created rows deleted, matched
        // rows kept but un-reconciled). Kept in a service so it stays unit-tested.
        StatementService.delete(st, transactions: transactions, context: context)
        Haptics.warning()
    }
}
