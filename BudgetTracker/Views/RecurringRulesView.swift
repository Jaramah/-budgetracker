import SwiftUI
import SwiftData

/// Manage recurring rules that auto-post transactions (rent, salary, Netflix…).
/// Reached from Settings ▸ Manage ▸ Recurring rules. `RecurringMaterializer`
/// posts due occurrences on launch; this screen creates/edits/deletes the rules.
struct RecurringRulesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecurringRule.nextRunDate) private var rules: [RecurringRule]

    @State private var editing: RecurringRule?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if rules.isEmpty {
                        emptyState
                    }
                    ForEach(rules) { rule in
                        Button { editing = rule } label: { ruleRow(rule) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .navigationTitle("Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.tint(DS.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }.tint(DS.accent)
                }
            }
        }
        .sheet(item: $editing) { RecurringEditView(rule: $0) }
        .sheet(isPresented: $showAdd) { RecurringEditView(rule: nil) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40)).foregroundStyle(DS.inkTertiary)
            Text("No recurring rules yet")
                .foregroundStyle(DS.inkSecondary)
            Text("Add rent, salary or subscriptions to auto-post them each cycle.")
                .font(.caption).multilineTextAlignment(.center)
                .foregroundStyle(DS.inkTertiary)
        }
        .padding(.vertical, 40)
    }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        HStack(spacing: 12) {
            IconChip(symbol: rule.category?.symbol ?? "arrow.triangle.2.circlepath",
                     tint: rule.category?.color ?? DS.accent, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.note.isEmpty ? (rule.category?.name ?? "Recurring") : rule.note)
                    .foregroundStyle(DS.inkPrimary)
                Text("\(rule.cadence.label) • next \(rule.nextRunDate.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption).foregroundStyle(DS.inkTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.signedString(rule.amountCents, isExpense: rule.isExpense))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(rule.isExpense ? DS.inkPrimary : DS.moneyIn)
                if !rule.isActive {
                    Text("Paused").font(.caption2).foregroundStyle(DS.warning)
                }
            }
        }
        .padding(DS.cardPadding)
        .background(DS.bgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.hairline, lineWidth: 1))
    }
}

/// Add or edit a recurring rule.
struct RecurringEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    let rule: RecurringRule?

    @State private var amountText: String
    @State private var isExpense: Bool
    @State private var note: String
    @State private var categoryID: UUID?
    @State private var method: PaymentMethod
    @State private var cadence: RecurringRule.Cadence
    @State private var anchorDay: Int
    @State private var isActive: Bool

    init(rule: RecurringRule?) {
        self.rule = rule
        _amountText = State(initialValue: rule.map { Money.plainString($0.amountCents) } ?? "")
        _isExpense = State(initialValue: rule?.isExpense ?? true)
        _note = State(initialValue: rule?.note ?? "")
        _categoryID = State(initialValue: rule?.category?.id)
        _method = State(initialValue: rule?.paymentMethod ?? .cash)
        _cadence = State(initialValue: rule?.cadence ?? .monthly)
        _anchorDay = State(initialValue: rule?.anchorDay ?? 1)
        _isActive = State(initialValue: rule?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Amount + direction
                    fieldCard(title: "Amount") {
                        VStack(spacing: 12) {
                            HStack {
                                Text(Money.symbol).foregroundStyle(DS.inkTertiary)
                                TextField("0.00", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(DS.inkPrimary)
                            }
                            SegmentPills(options: ["Expense", "Income"],
                                         selection: Binding(get: { isExpense ? 0 : 1 },
                                                            set: { isExpense = $0 == 0 }))
                        }
                    }

                    fieldCard(title: "Description") {
                        TextField("e.g. Rent, Salary, Netflix", text: $note)
                            .foregroundStyle(DS.inkPrimary)
                    }

                    // Category
                    fieldCard(title: "Category") {
                        Menu {
                            Button("None") { categoryID = nil }
                            ForEach(categories) { c in
                                Button(c.name) { categoryID = c.id }
                            }
                        } label: {
                            HStack {
                                Text(selectedCategoryName).foregroundStyle(DS.inkPrimary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption).foregroundStyle(DS.inkTertiary)
                            }
                        }
                    }

                    // Payment method
                    fieldCard(title: "Payment method") {
                        SegmentPills(options: ["Cash", "Credit"],
                                     selection: Binding(get: { method == .cash ? 0 : 1 },
                                                        set: { method = $0 == 0 ? .cash : .credit }))
                    }

                    // Cadence
                    fieldCard(title: "Repeats") {
                        SegmentPills(options: ["Weekly", "Monthly", "Yearly"],
                                     selection: Binding(
                                        get: { [.weekly, .monthly, .yearly].firstIndex(of: cadence) ?? 1 },
                                        set: { cadence = [.weekly, .monthly, .yearly][$0] }))
                    }

                    // Anchor day
                    fieldCard(title: cadence == .weekly ? "Day of week" : "Day of month") {
                        Stepper(value: $anchorDay, in: cadence == .weekly ? 1...7 : 1...28) {
                            Text(anchorLabel).foregroundStyle(DS.inkPrimary)
                        }
                    }

                    if rule != nil {
                        fieldCard(title: "Status") {
                            Toggle(isOn: $isActive) {
                                Text("Active").foregroundStyle(DS.inkPrimary)
                            }.tint(DS.accent)
                        }
                        Button(role: .destructive) { deleteRule() } label: {
                            Text("Delete rule").frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(DS.moneyOut.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(DS.moneyOut)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(DS.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.tint(DS.accent)
                        .disabled((Money.cents(from: amountText) ?? 0) <= 0)
                }
            }
        }
    }

    private var selectedCategoryName: String {
        categories.first { $0.id == categoryID }?.name ?? "None"
    }

    private var anchorLabel: String {
        if cadence == .weekly {
            let days = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            return days[min(max(anchorDay, 1), 7)]
        }
        return "Day \(anchorDay)"
    }

    private func save() {
        guard let cents = Money.cents(from: amountText), cents > 0 else { return }
        let cat = categories.first { $0.id == categoryID }
        if let rule {
            rule.amountCents = cents
            rule.isExpense = isExpense
            rule.note = note
            rule.category = cat
            rule.paymentMethod = method
            rule.cadence = cadence
            rule.anchorDay = anchorDay
            rule.isActive = isActive
        } else {
            let r = RecurringRule(amountCents: cents, isExpense: isExpense, note: note,
                                  category: cat, paymentMethod: method,
                                  cadence: cadence, anchorDay: anchorDay,
                                  startDate: .now, isActive: isActive)
            context.insert(r)
        }
        try? context.save()
        RecurringMaterializer.run(context: context)
        Haptics.success()
        dismiss()
    }

    private func deleteRule() {
        if let rule { context.delete(rule); try? context.save(); Haptics.warning() }
        dismiss()
    }

    private func fieldCard<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold))
                .foregroundStyle(DS.inkTertiary)
            content()
                .padding(DS.cardPadding)
                .background(DS.bgCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.hairline, lineWidth: 1))
        }
    }
}
