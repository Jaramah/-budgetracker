import SwiftUI
import SwiftData

/// Bills & Recurring screen — upcoming (unpaid this month) and paid-this-month
/// sections, with "Mark paid". Matches the reference's Bills screen.
struct BillsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bill.sortIndex) private var bills: [Bill]
    @State private var showAdd = false
    @State private var editing: Bill?

    private var upcoming: [Bill] {
        bills.filter { !$0.isPaid() }.sorted { $0.nextDueDate() < $1.nextDueDate() }
    }
    private var paid: [Bill] {
        bills.filter { $0.isPaid() }.sorted { $0.dueDay < $1.dueDay }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if bills.isEmpty { emptyState }
                    if !upcoming.isEmpty {
                        AuroraCard {
                            VStack(spacing: 12) {
                                SectionHeader(title: "Upcoming")
                                ForEach(upcoming) { bill in billRow(bill, paid: false) }
                            }
                        }
                    }
                    if !paid.isEmpty {
                        AuroraCard {
                            VStack(spacing: 12) {
                                SectionHeader(title: "Paid this month")
                                ForEach(paid) { bill in billRow(bill, paid: true) }
                            }
                        }
                    }
                    Color.clear.frame(height: 72)
                }
                .padding(.horizontal, 16)
            }
            .auroraBackground()
            .navigationTitle("Bills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { BillEditView(bill: nil) }
            .sheet(item: $editing) { b in BillEditView(bill: b) }
        }
    }

    private func billRow(_ bill: Bill, paid: Bool) -> some View {
        HStack(spacing: 12) {
            IconChip(symbol: bill.symbol, tint: paid ? DS.moneyIn : DS.accent, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name).font(.subheadline.weight(.medium)).foregroundStyle(DS.inkPrimary)
                Text("\(paid ? "Paid" : "Due") \(DateHelpers.mediumDate(bill.nextDueDate())) · \(bill.recurrence.label)")
                    .font(.caption).foregroundStyle(DS.inkTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.string(bill.amountCents))
                    .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(DS.inkPrimary)
                if !paid {
                    Button {
                        bill.lastPaidMonth = DateHelpers.startOfMonth(.now)
                        try? context.save(); Haptics.success()
                    } label: {
                        Text("Mark paid").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(DS.accentDim, in: Capsule()).foregroundStyle(DS.accentSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = bill }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar").font(.largeTitle).foregroundStyle(DS.inkTertiary)
            Text("No bills yet. Tap + to add rent, telco, subscriptions…")
                .font(.subheadline).foregroundStyle(DS.inkTertiary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 60)
    }
}

/// Add or edit a bill.
struct BillEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bill.sortIndex) private var bills: [Bill]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    var bill: Bill?
    @State private var name = ""
    @State private var amountText = ""
    @State private var dueDay = 1
    @State private var recurrence: Bill.Recurrence = .monthly

    private var isEditing: Bool { bill != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Name (e.g. Rent, Netflix)", text: $name)
                    TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                }
                Section("Schedule") {
                    Picker("Due day", selection: $dueDay) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(Bill.Recurrence.allCases) { r in Text(r.label).tag(r) }
                    }
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) { deleteBill() } label: {
                            Label("Delete bill", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bgBase.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Bill" : "Add Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty || Money.cents(from: amountText) == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let b = bill else { return }
        name = b.name; amountText = String(format: "%.2f", Double(b.amountCents)/100)
        dueDay = b.dueDay; recurrence = b.recurrence
    }

    private func save() {
        guard let cents = Money.cents(from: amountText) else { return }
        if let b = bill {
            b.name = name; b.amountCents = abs(cents); b.dueDay = dueDay; b.recurrence = recurrence
        } else {
            context.insert(Bill(name: name, amountCents: abs(cents), dueDay: dueDay,
                                recurrence: recurrence, sortIndex: bills.count))
        }
        try? context.save(); dismiss()
    }

    private func deleteBill() {
        if let b = bill { context.delete(b); try? context.save() }
        dismiss()
    }
}
