import SwiftUI
import SwiftData

/// Add or edit a credit card account.
struct CardEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreditCardAccount.sortIndex) private var cards: [CreditCardAccount]

    var card: CreditCardAccount?

    @State private var bank: Bank = .dbs
    @State private var nickname = ""
    @State private var last4 = ""
    @State private var statementDay = 1
    @State private var paymentDueDay = 1
    @State private var creditLimitText = ""
    @State private var reminderEnabled = true

    private var isEditing: Bool { card != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card") {
                    Picker("Bank", selection: $bank) {
                        ForEach(Bank.allCases) { b in Text(b.label).tag(b) }
                    }
                    TextField("Nickname (e.g. Altitude)", text: $nickname)
                    TextField("Last 4 digits", text: $last4)
                        .keyboardType(.numberPad)
                        .onChange(of: last4) { _, v in last4 = String(v.filter(\.isNumber).prefix(4)) }
                }
                Section {
                    Picker("Statement day", selection: $statementDay) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Payment due day", selection: $paymentDueDay) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                } header: { Text("Billing cycle") } footer: {
                    Text("Day of the month the statement is cut and payment is due. Used to route statements and remind you before the due date. Days 29–31 fall back to the last day of any shorter month.")
                }
                Section("Optional") {
                    TextField("Credit limit", text: $creditLimitText).keyboardType(.decimalPad)
                    Toggle("Payment due reminder", isOn: $reminderEnabled)
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) { deleteCard() } label: {
                            Label("Delete card", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bgBase.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Card" : "Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let c = card else { return }
        bank = c.bank; nickname = c.nickname; last4 = c.last4
        statementDay = max(1, c.statementDay); paymentDueDay = max(1, c.paymentDueDay)
        creditLimitText = c.creditLimitCents > 0 ? String(format: "%.2f", Double(c.creditLimitCents)/100) : ""
        reminderEnabled = c.reminderEnabled
    }

    private func save() {
        let limit = Money.cents(from: creditLimitText) ?? 0
        if let c = card {
            c.bank = bank; c.nickname = nickname; c.last4 = last4
            c.statementDay = statementDay; c.paymentDueDay = paymentDueDay
            c.creditLimitCents = max(0, limit); c.reminderEnabled = reminderEnabled
        } else {
            let c = CreditCardAccount(bank: bank, nickname: nickname, last4: last4,
                                      statementDay: statementDay, paymentDueDay: paymentDueDay,
                                      creditLimitCents: max(0, limit),
                                      sortIndex: cards.count, reminderEnabled: reminderEnabled)
            context.insert(c)
        }
        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<CreditCardAccount>())) ?? []
        PaymentReminderScheduler.reschedule(cards: all)
        dismiss()
    }

    private func deleteCard() {
        if let c = card {
            PaymentReminderScheduler.cancel(cardID: c.id)
            context.delete(c); try? context.save()
        }
        dismiss()
    }
}
