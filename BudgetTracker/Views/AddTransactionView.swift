import SwiftUI
import SwiftData
import UIKit

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
    /// Manual entry was expense-only, so received money could not be logged at all.
    @State private var isExpense = true
    @State private var smsNotice: String?

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        Button {
                            pasteFromSMS()
                        } label: {
                            Label("Paste bank SMS", systemImage: "doc.on.clipboard")
                        }
                    } footer: {
                        // Set expectations honestly: iOS gives apps no way to read
                        // the inbox, so the text has to be handed over deliberately.
                        Text("Copy a PayNow or card alert in Messages, then tap this to fill in the amount, merchant and date. iOS doesn't let apps read your messages, so nothing is read automatically.")
                    }
                }

                Section {
                    Picker("", selection: $isExpense) {
                        Text("Spent").tag(true)
                        Text("Received").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
            .alert("Paste bank SMS", isPresented: Binding(
                get: { smsNotice != nil },
                set: { if !$0 { smsNotice = nil } })) {
                Button("OK", role: .cancel) { smsNotice = nil }
            } message: { Text(smsNotice ?? "") }
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
        isExpense = tx.isExpense
    }

    /// Pre-fill from a bank alert the user has copied.
    ///
    /// Deliberately fills the form rather than saving: SMS is an untrusted channel,
    /// and a convincing fake alert must never be able to write to the ledger on its
    /// own. The user still sees and confirms every field.
    private func pasteFromSMS() {
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            smsNotice = "Your clipboard is empty. Copy the alert in Messages first."
            return
        }
        guard let r = SMSTransactionParser.parse(text) else {
            smsNotice = "That doesn't look like a bank alert — no amount and payment wording found. You can still type it in."
            return
        }
        amountText = String(format: "%.2f", Double(r.amountCents) / 100)
        note = r.suggestedNote
        if let d = r.date { date = d }
        isExpense = !r.isIncoming
        if categoryID == nil, let party = r.counterparty {
            categoryID = AutoCategorizer.category(for: party, from: categories)?.id
        }
        Haptics.success()
    }

    private func save() {
        guard let cents = Money.cents(from: amountText) else { return }
        let cat = categoryID.flatMap { id in categories.first { $0.id == id } }
        if let tx = existing {
            tx.amountCents = abs(cents)
            tx.note = note
            tx.isExpense = isExpense
            tx.date = date
            tx.category = cat
            tx.paymentMethod = method
            tx.cardID = method == .credit ? cardID : nil
            tx.updatedAt = .now
        } else {
            let tx = Transaction(
                amountCents: abs(cents), isExpense: isExpense, note: note, date: date,
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
