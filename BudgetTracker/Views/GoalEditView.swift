import SwiftUI
import SwiftData

/// Add or edit a savings goal.
struct GoalEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.sortIndex) private var goals: [Goal]

    var goal: Goal?

    @State private var name = ""
    @State private var targetText = ""
    @State private var savedText = ""
    @State private var colorHex = "#3B82F6"
    @State private var symbol = "target"

    private let symbols = ["target", "airplane", "car.fill", "house.fill", "gift.fill",
                           "graduationcap.fill", "heart.fill", "banknote.fill", "star.fill"]
    private let colors = ["#3B82F6", "#8B5CF6", "#EC4899", "#F59E0B", "#10B981", "#06B6D4", "#F43F5E"]

    private var isEditing: Bool { goal != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Name (e.g. Emergency Fund)", text: $name)
                    TextField("Target amount", text: $targetText).keyboardType(.decimalPad)
                    TextField("Already saved", text: $savedText).keyboardType(.decimalPad)
                }
                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(symbols, id: \.self) { s in
                                IconChip(symbol: s, tint: Color(hex: colorHex), size: 42)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(symbol == s ? DS.accent : Color.clear, lineWidth: 2))
                                    .onTapGesture { symbol = s }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(colorHex == c ? Color.white : Color.clear, lineWidth: 2))
                                .onTapGesture { colorHex = c }
                        }
                    }
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) { deleteGoal() } label: {
                            Label("Delete goal", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bgBase.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty || Money.cents(from: targetText) == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let g = goal else { return }
        name = g.name
        targetText = String(format: "%.2f", Double(g.targetCents)/100)
        savedText = g.savedCents > 0 ? String(format: "%.2f", Double(g.savedCents)/100) : ""
        colorHex = g.colorHex; symbol = g.symbol
    }

    private func save() {
        guard let target = Money.cents(from: targetText) else { return }
        let saved = Money.cents(from: savedText) ?? 0
        if let g = goal {
            g.name = name; g.targetCents = max(0, target); g.savedCents = max(0, saved)
            g.colorHex = colorHex; g.symbol = symbol
        } else {
            let g = Goal(name: name, targetCents: max(0, target), savedCents: max(0, saved),
                         colorHex: colorHex, symbol: symbol, sortIndex: goals.count)
            context.insert(g)
        }
        try? context.save()
        dismiss()
    }

    private func deleteGoal() {
        if let g = goal { context.delete(g); try? context.save() }
        dismiss()
    }
}
