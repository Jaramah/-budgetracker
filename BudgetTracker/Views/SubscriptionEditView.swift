import SwiftUI
import SwiftData

/// Add or edit a subscription (Pro). Manual adds are created `.active`.
struct SubscriptionEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \CreditCardAccount.sortIndex) private var cards: [CreditCardAccount]
    @Query private var subs: [Subscription]

    var subscription: Subscription?

    @State private var name = ""
    @State private var amountText = ""
    @State private var cycle: Subscription.Cycle = .monthly
    @State private var renewalDate: Date = .now
    @State private var categoryID: UUID?
    @State private var cardID: UUID?
    @State private var reminderEnabled = true
    @State private var leadDays = 3

    private var isEditing: Bool { subscription != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscription") {
                    TextField("Name (e.g. Netflix)", text: $name)
                    TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    Picker("Billing cycle", selection: $cycle) {
                        ForEach(Subscription.Cycle.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Next renewal", selection: $renewalDate, displayedComponents: .date)
                }

                Section("Reminder") {
                    Toggle("Remind me before it renews", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Picker("Remind me", selection: $leadDays) {
                            Text("On the day").tag(0)
                            Text("1 day before").tag(1)
                            Text("2 days before").tag(2)
                            Text("3 days before").tag(3)
                            Text("5 days before").tag(5)
                            Text("7 days before").tag(7)
                        }
                    }
                }

                Section("Details (optional)") {
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Card", selection: $cardID) {
                        Text("None").tag(UUID?.none)
                        ForEach(cards) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                }

                if isEditing {
                    Section {
                        if subscription?.status == .active {
                            Button { markCancelled() } label: {
                                Label("Mark as cancelled", systemImage: "xmark.circle")
                            }
                        }
                        Button(role: .destructive) { deleteSub() } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bgBase.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Subscription" : "New Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || Money.cents(from: amountText) == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let s = subscription else { return }
        name = s.name
        amountText = String(format: "%.2f", Double(s.amountCents) / 100)
        cycle = s.cycle
        renewalDate = s.nextRenewal()
        categoryID = s.category?.id
        cardID = s.cardID
        reminderEnabled = s.reminderEnabled
        leadDays = s.reminderLeadDays
    }

    private func save() {
        guard let cents = Money.cents(from: amountText) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let cat = categories.first { $0.id == categoryID }

        if let s = subscription {
            s.name = trimmed
            s.amountCents = max(0, cents)
            s.cycle = cycle
            s.anchorDate = renewalDate
            s.category = cat
            s.cardID = cardID
            s.reminderEnabled = reminderEnabled
            s.reminderLeadDays = leadDays
            if s.status == .cancelled { s.status = .active }   // re-activating via edit
            s.updatedAt = .now
        } else {
            let s = Subscription(
                name: trimmed,
                matchKey: SubscriptionDetector.matchKey(for: trimmed) ?? trimmed.lowercased(),
                amountCents: max(0, cents),
                cycle: cycle,
                anchorDate: renewalDate,
                cardID: cardID,
                category: cat,
                reminderEnabled: reminderEnabled,
                reminderLeadDays: leadDays,
                status: .active,
                createdManually: true
            )
            context.insert(s)
        }
        try? context.save()
        applyReminders()
        Haptics.success()
        dismiss()
    }

    private func markCancelled() {
        guard let s = subscription else { return }
        s.status = .cancelled
        s.reminderEnabled = false
        try? context.save()
        SubscriptionReminderScheduler.cancel(subID: s.id)
        applyReminders()
        Haptics.tap()
        dismiss()
    }

    private func deleteSub() {
        guard let s = subscription else { return }
        let id = s.id
        context.delete(s)
        try? context.save()
        SubscriptionReminderScheduler.cancel(subID: id)
        applyReminders()
        dismiss()
    }

    /// Ensure permission (if any reminder is on) then rebuild the schedule.
    private func applyReminders() {
        let wantsReminders = subs.contains { $0.status == .active && $0.reminderEnabled }
        Task {
            if wantsReminders { _ = await SubscriptionReminderScheduler.requestAuthorization() }
            SubscriptionReminderScheduler.reschedule(subscriptions: subs)
        }
    }
}
