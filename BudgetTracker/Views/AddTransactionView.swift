import SwiftUI
import SwiftData

/// Add or edit a transaction. Big amount entry at top, then details.
struct AddTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \CreditCardAccount.sortIndex) private var cards: [CreditCardAccount]

    var existing: Transaction? = nil

    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var categoryID: UUID?
    @State private var method: PaymentMethod = .cash
    @State private var cardID: UUID?

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(Money.symbol).foregroundStyle(DS.inkTertiary)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        TextField("0.00", text: $amountText)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .keyboardType(.decimalPad)
                    }
                } header: { Text("Amount") }

                Section {
                    TextField("Description", text: $note)
                    Picker("Category", selection: $categoryID) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories) { c in
                            Text(c.name).tag(UUID?.some(c.id))
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: { Text("Details") }

                Section {
                    Picker("Payment", selection: $method) {
                        ForEach(PaymentMethod.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    if method == .credit, !cards.isEmpty {
                        Picker("Card", selection: $cardID) {
                            Text("None").tag(UUID?.none)
                            ForEach(cards) { card in
                                Text(card.displayName).tag(UUID?.some(card.id))
                            }
                        }
                    }
                } header: { Text("Payment") }

                if isEditing {
                    Section {
                        Button(role: .destructive) { deleteTx() } label: {
                            Label("Delete transaction", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bgBase.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit" : "Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(Money.cents(from: amountText) == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let tx = existing else { return }
        amountText = String(format: "%.2f", Double(tx.amountCents) / 100)
        note = tx.note
        date = tx.date
        categoryID = tx.category?.id
        method = tx.paymentMethod
        cardID = tx.cardID
    }

    private func save() {
        guard let cents = Money.cents(from: amountText) else { return }
        let cat = categoryID.flatMap { id in categories.first { $0.id == id } }
        if let tx = existing {
            tx.amountCents = abs(cents)
            tx.note = note
            tx.isExpense = true
            tx.date = date
            tx.category = cat
            tx.paymentMethod = method
            tx.cardID = method == .credit ? cardID : nil
            tx.updatedAt = .now
        } else {
            let tx = Transaction(
                amountCents: abs(cents), isExpense: true, note: note, date: date,
                category: cat, paymentMethod: method,
                cardID: method == .credit ? cardID : nil)
            context.insert(tx)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }

    private func deleteTx() {
        if let tx = existing { context.delete(tx); try? context.save() }
        dismiss()
    }
}
