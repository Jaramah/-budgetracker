import SwiftUI
import SwiftData

/// Shown right after parsing a file, BEFORE anything is saved. The user reviews
/// parsed rows (low-confidence flagged), sees AUTO-ASSIGNED categories (overridable),
/// then commits. On save with auto-add, charges reconcile against logged credit
/// transactions via amount(cents) + date window + description tiebreaker.
struct StatementReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let fileName: String
    @State var lines: [StatementParser.ParsedLine]
    var detectedBank: Bank = .unknown
    /// Dates and totals the statement printed about itself. Empty for CSV imports,
    /// which carry transactions only.
    var meta: StatementParser.StatementMeta = .init()
    var declaredTotalCents: Int? = nil
    /// nil = the statement printed no total to check against.
    var reconciled: Bool? = nil
    /// When a statement is uploaded from within an account, the card is already
    /// known — pass it here so the picker is pre-set (and shown as confirmed).
    var preselectedCardID: UUID? = nil
    @State private var label: String = ""
    @State private var autoAdd: Bool = true
    @State private var selectedCardID: UUID?
    @State private var didPreselect = false

    @AppStorage("matchWindowDays") private var matchWindowDays: Int = 4

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query private var allTransactions: [Transaction]
    @Query(sort: \CreditCardAccount.sortIndex) private var cards: [CreditCardAccount]

    private var creditTransactions: [Transaction] {
        allTransactions.filter { $0.isExpense && $0.paymentMethod == .credit }
    }

    private var chargeTotalCents: Int {
        lines.filter { $0.amountCents > 0 }.reduce(0) { $0 + $1.amountCents }
    }
    private var creditTotalCents: Int {
        lines.filter { $0.amountCents < 0 }.reduce(0) { $0 + abs($1.amountCents) }
    }
    private var lowConfidenceCount: Int { lines.filter { $0.lowConfidence }.count }

    /// Whether the parsed charges add up to the total the bank printed.
    ///
    /// This is the check that would have caught the UOB mispairing before it
    /// reached anyone's data — the rows looked entirely plausible individually.
    /// Surfacing it here means a bad import is visible *before* it is saved,
    /// rather than only steering which parser wins behind the scenes.
    @ViewBuilder
    private var reconciliationRow: some View {
        if let declaredTotalCents {
            let diff = chargeTotalCents - declaredTotalCents
            if reconciled == true {
                Label("Balances with the statement total (\(Money.string(declaredTotalCents)))",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(DS.moneyIn).font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Doesn't match the statement total",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.moneyOut).font(.callout)
                    Text("Statement says \(Money.string(declaredTotalCents)), these rows add up to \(Money.string(chargeTotalCents)) — \(diff > 0 ? "over" : "under") by \(Money.string(abs(diff))). Check the rows below before saving.")
                        .font(.caption).foregroundStyle(DS.inkTertiary)
                }
            }
        }
    }

    private var matchPreview: (linked: Int, new: Int) {
        var usedIDs = Set<UUID>()
        var linked = 0, new = 0
        for line in lines where line.amountCents > 0 {
            if let m = TransactionMatcher.bestMatch(
                amountCents: line.amountCents, date: line.date, desc: line.desc,
                in: creditTransactions, excludingIDs: usedIDs, days: matchWindowDays) {
                usedIDs.insert(m.id); linked += 1
            } else { new += 1 }
        }
        return (linked, new)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Statement name (e.g. DBS Altitude — June)", text: $label)
                } header: {
                    Text("From \(fileName)")
                }

                Section {
                    if cards.isEmpty {
                        Text("No cards added yet. Add cards in the Cards tab to route statements automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Card", selection: $selectedCardID) {
                            Text("Unassigned").tag(UUID?.none)
                            ForEach(cards) { card in
                                Text(card.displayName).tag(UUID?.some(card.id))
                            }
                        }
                    }
                } header: {
                    Text("Assign to card")
                } footer: {
                    if detectedBank != .unknown {
                        Text("Detected \(detectedBank.label) from this statement. Confirm the card so its transactions and balance track correctly.")
                    } else {
                        Text("Pick which card this statement belongs to so its balance and totals stay accurate.")
                    }
                }

                if meta.statementDate != nil || meta.dueDate != nil {
                    Section {
                        if let d = meta.statementDate {
                            LabeledContent("Statement date", value: DateHelpers.mediumDate(d))
                        }
                        if let d = meta.dueDate {
                            LabeledContent("Payment due", value: DateHelpers.mediumDate(d))
                        }
                    } header: {
                        Text("From the statement")
                    } footer: {
                        Text("Read from the statement itself, so the due date is the bank's own — not a guess from the card's due day.")
                    }
                }

                Section {
                    LabeledContent("Rows parsed", value: "\(lines.count)")
                    LabeledContent("Charges", value: Money.string(chargeTotalCents))
                    LabeledContent("Payments / credits", value: Money.string(creditTotalCents))
                    reconciliationRow
                    if lowConfidenceCount > 0 {
                        Label("\(lowConfidenceCount) row(s) need a quick check",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout)
                    }
                } header: {
                    Text("Summary")
                }

                Section {
                    Toggle("Add to my transactions", isOn: $autoAdd)
                    if autoAdd {
                        let p = matchPreview
                        Label("\(p.linked) will link to existing · \(p.new) new will be created",
                              systemImage: "arrow.triangle.merge")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Auto-add & categorize")
                } footer: {
                    Text("Charges match logged credit transactions by exact amount within ±\(matchWindowDays) days (Settings), with description as a tiebreaker — so a purchase you keyed days before it posted links instead of duplicating. Genuinely different same-amount purchases are kept separate.")
                }

                Section("Parsed transactions") {
                    ForEach($lines) { $line in
                        rowEditor($line)
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(lines.isEmpty)
                }
            }
            .onAppear {
                autoCategorize()
                preselectCard()
            }
        }
    }

    @ViewBuilder
    private func rowEditor(_ line: Binding<StatementParser.ParsedLine>) -> some View {
        let l = line.wrappedValue
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Description", text: line.desc).font(.body)
                Spacer()
                Text(Money.signedString(abs(l.amountCents), isExpense: l.amountCents > 0))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(l.amountCents > 0 ? .primary : Color.green)
            }
            // Foreign charges: show what the merchant actually billed. This used to
            // be glued onto the end of the description ("… Seoul KRW 775,200.00").
            if let code = l.foreignCurrency, let amt = l.foreignAmountCents {
                Text("\(code) \(Money.plainString(amt))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DS.inkTertiary)
            }
            HStack {
                DatePicker("", selection: line.date, displayedComponents: .date)
                    .labelsHidden()
                if l.lowConfidence {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                }
                Spacer()
                if l.amountCents > 0 {
                    Picker("", selection: line.categoryID) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(UUID?.some(cat.id))
                        }
                    }
                    .labelsHidden()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func autoCategorize() {
        for i in lines.indices where lines[i].amountCents > 0 && lines[i].categoryID == nil {
            if let cat = AutoCategorizer.category(for: lines[i].desc, from: categories) {
                lines[i].categoryID = cat.id
            }
        }
    }

    /// Preselect the card whose bank matches the detected issuer. If exactly one
    /// card matches, choose it; if several match (e.g. two DBS cards), leave
    /// unselected so the user picks — never guess silently.
    private func preselectCard() {
        guard !didPreselect else { return }
        didPreselect = true
        // If uploaded from an account, that card wins.
        if let pre = preselectedCardID {
            selectedCardID = pre
            return
        }
        guard detectedBank != .unknown else { return }
        let matches = cards.filter { $0.bank == detectedBank }
        if matches.count == 1 {
            selectedCardID = matches[0].id
        }
    }

    private func save() {
        let statement = StatementImport(
            fileName: fileName,
            label: label.trimmingCharacters(in: .whitespaces),
            statementTotalCents: chargeTotalCents,
            cardID: selectedCardID,
            detectedBank: detectedBank
        )
        statement.statementDate = meta.statementDate
        // Prefer the date the bank printed; fall back to deriving it from the
        // card's due day only when the statement didn't say.
        statement.dueDate = meta.dueDate ?? meta.statementDate.flatMap { d in
            cards.first { $0.id == selectedCardID }?.dueDate(forStatementDate: d)
        }
        statement.declaredTotalCents = declaredTotalCents
        statement.reconciled = reconciled
        context.insert(statement)

        var usedIDs = Set<UUID>()

        for line in lines {
            let sl = StatementLine(date: line.date, desc: line.desc, amountCents: line.amountCents)
            sl.foreignCurrency = line.foreignCurrency
            sl.foreignAmountCents = line.foreignAmountCents
            sl.statement = statement
            context.insert(sl)

            guard autoAdd, line.amountCents > 0 else { continue }

            if let match = TransactionMatcher.bestMatch(
                amountCents: line.amountCents, date: line.date, desc: line.desc,
                in: creditTransactions, excludingIDs: usedIDs, days: matchWindowDays) {
                usedIDs.insert(match.id)
                sl.matchedTransactionID = match.id
                match.isReconciled = true
                // Attach the matched transaction to the selected card too.
                if let cid = selectedCardID { match.cardID = cid }
                if match.category == nil, let cid = line.categoryID {
                    match.category = categories.first { $0.id == cid }
                }
            } else {
                let cat = line.categoryID.flatMap { cid in categories.first { $0.id == cid } }
                let tx = Transaction(
                    amountCents: line.amountCents,
                    isExpense: true,
                    note: line.desc,
                    date: line.date,
                    category: cat,
                    paymentMethod: .credit,
                    isReconciled: true,
                    createdFromStatement: true,
                    cardID: selectedCardID
                )
                context.insert(tx)
                sl.matchedTransactionID = tx.id
            }
        }
        try? context.save()
        // Jump all tabs to the statement's month so the imported transactions are
        // visible immediately (they're often in a prior month, e.g. Apr/May charges).
        if let earliest = lines.map({ $0.date }).min() {
            appState.goToMonth(of: earliest)
        }
        // A successful import is a genuine "happy moment" — a good time to ask for
        // a rating (throttled; won't fire on the very first import).
        AppReview.recordPositiveAction()
        dismiss()
    }
}
