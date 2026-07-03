import SwiftUI
import SwiftData

/// Manage spending categories — add, rename, recolor, set monthly budget, delete.
/// Reached from Settings ▸ Manage ▸ Categories.
struct CategoryManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var editing: Category?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(categories) { cat in
                        Button {
                            editing = cat
                        } label: {
                            HStack(spacing: 12) {
                                IconChip(symbol: cat.symbol, tint: cat.color, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.name).foregroundStyle(DS.inkPrimary)
                                    if cat.monthlyBudgetCents > 0 {
                                        Text("Budget \(Money.string(cat.monthlyBudgetCents))/mo")
                                            .font(.caption).foregroundStyle(DS.inkTertiary)
                                    } else {
                                        Text("No budget").font(.caption)
                                            .foregroundStyle(DS.inkTertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(DS.inkTertiary)
                            }
                            .padding(DS.cardPadding)
                            .background(DS.bgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.tint(DS.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .tint(DS.accent)
                }
            }
        }
        .sheet(item: $editing) { CategoryEditView(category: $0) }
        .sheet(isPresented: $showAdd) { CategoryEditView(category: nil) }
    }
}

/// Add or edit a single category.
struct CategoryEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = create a new category.
    let category: Category?

    @State private var name: String
    @State private var symbol: String
    @State private var colorHex: String
    @State private var budgetText: String

    private let symbols = ["fork.knife", "cart.fill", "car.fill", "house.fill",
                           "bolt.fill", "bag.fill", "film.fill", "cross.case.fill",
                           "dollarsign.circle.fill", "gift.fill", "airplane",
                           "cup.and.saucer.fill", "pawprint.fill", "gamecontroller.fill",
                           "book.fill", "heart.fill", "tag.fill", "creditcard.fill"]

    private let palette = ["#FF9F0A", "#34C759", "#5AC8FA", "#AF52DE", "#FFD60A",
                           "#FF375F", "#BF5AF2", "#FF6B6B", "#30D158", "#3B82F6",
                           "#8B5CF6", "#EC4899", "#06B6D4", "#F43F5E", "#A3E635"]

    init(category: Category?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _symbol = State(initialValue: category?.symbol ?? "tag.fill")
        _colorHex = State(initialValue: category?.colorHex ?? "#3B82F6")
        _budgetText = State(initialValue: (category?.monthlyBudgetCents ?? 0) > 0
                            ? Money.plainString(category!.monthlyBudgetCents) : "")
    }

    private var selectedColor: Color { Color(hex: colorHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Preview
                    IconChip(symbol: symbol, tint: selectedColor, size: 64)
                        .padding(.top, 8)

                    // Name
                    fieldCard(title: "Name") {
                        TextField("e.g. Groceries", text: $name)
                            .foregroundStyle(DS.inkPrimary)
                    }

                    // Monthly budget
                    fieldCard(title: "Monthly budget (optional)") {
                        HStack {
                            Text(Money.symbol).foregroundStyle(DS.inkTertiary)
                            TextField("0", text: $budgetText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(DS.inkPrimary)
                        }
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ICON").font(.caption.weight(.semibold))
                            .foregroundStyle(DS.inkTertiary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(symbols, id: \.self) { s in
                                Button { symbol = s; Haptics.tap() } label: {
                                    IconChip(symbol: s, tint: selectedColor, size: 44)
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(symbol == s ? DS.accent : .clear, lineWidth: 2))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COLOR").font(.caption.weight(.semibold))
                            .foregroundStyle(DS.inkTertiary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(palette, id: \.self) { hex in
                                Button { colorHex = hex; Haptics.tap() } label: {
                                    Circle().fill(Color(hex: hex)).frame(width: 38, height: 38)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 2 : 0))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    if category != nil {
                        Button(role: .destructive) { deleteCategory() } label: {
                            Text("Delete category")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(DS.moneyOut.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(DS.moneyOut)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .auroraBackground()
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(DS.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .tint(DS.accent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
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

    private func save() {
        let cents = Money.cents(from: budgetText) ?? 0
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let category {
            category.name = trimmed
            category.symbol = symbol
            category.colorHex = colorHex
            category.monthlyBudgetCents = cents
            category.updatedAt = .now
        } else {
            let maxIndex = (try? context.fetch(FetchDescriptor<Category>()))?
                .map(\.sortIndex).max() ?? -1
            let c = Category(name: trimmed, symbol: symbol, colorHex: colorHex,
                             monthlyBudgetCents: cents, sortIndex: maxIndex + 1)
            context.insert(c)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }

    private func deleteCategory() {
        if let category {
            context.delete(category)
            try? context.save()
            Haptics.warning()
        }
        dismiss()
    }
}
