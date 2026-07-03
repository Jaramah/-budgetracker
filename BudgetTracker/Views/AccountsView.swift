import SwiftUI
import SwiftData

/// Accounts screen with two tabs: Cards (credit cards + per-card PDF statement
/// import) and Goals (savings goals). Matches the reference's Accounts screen.
struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CreditCardAccount.sortIndex) private var cards: [CreditCardAccount]
    @Query private var transactions: [Transaction]
    @Query(sort: \Goal.sortIndex) private var goals: [Goal]

    @State private var tab = 0
    @State private var showAddCard = false
    @State private var showAddGoal = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SegmentPills(options: ["Cards", "Goals"], selection: $tab)
                    if tab == 0 { cardsTab } else { goalsTab }
                    Color.clear.frame(height: 72)
                }
                .padding(.horizontal, 16)
            }
            .auroraBackground()
            .navigationTitle("Accounts")
            .sheet(isPresented: $showAddCard) { CardEditView(card: nil) }
            .sheet(isPresented: $showAddGoal) { GoalEditView(goal: nil) }
        }
    }

    private func balance(_ card: CreditCardAccount) -> Int {
        transactions.filter { $0.cardID == card.id && $0.isExpense }.reduce(0) { $0 + $1.amountCents }
    }

    // MARK: Cards tab
    private var cardsTab: some View {
        VStack(spacing: 14) {
            ForEach(cards) { card in
                NavigationLink { AccountDetailView(card: card) } label: {
                    cardVisual(card)
                }
                .buttonStyle(.plain)
            }
            Button { showAddCard = true } label: {
                Label("Add Card", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(DS.bgCard, in: RoundedRectangle(cornerRadius: DS.corner))
                    .overlay(RoundedRectangle(cornerRadius: DS.corner)
                        .strokeBorder(DS.hairline, style: StrokeStyle(lineWidth: 1, dash: [5])))
                    .foregroundStyle(DS.accentSoft)
            }
            .buttonStyle(.plain)
            if cards.isEmpty {
                Text("Add a credit card, then open it to upload that card's PDF statements.")
                    .font(.caption).foregroundStyle(DS.inkTertiary).multilineTextAlignment(.center)
            }
        }
    }

    private func cardVisual(_ card: CreditCardAccount) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(card.bank.label).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "creditcard.fill").foregroundStyle(.white.opacity(0.85))
            }
            Text("•••• \(card.last4.isEmpty ? "••••" : card.last4)")
                .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.95))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Balance").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Text(Money.string(balance(card)))
                        .font(.headline).monospacedDigit().foregroundStyle(.white)
                }
                Spacer()
                if card.creditLimitCents > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Limit").font(.caption2).foregroundStyle(.white.opacity(0.7))
                        Text(Money.string(card.creditLimitCents))
                            .font(.subheadline).monospacedDigit().foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [card.color, card.color.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: DS.corner, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: DS.corner).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }

    // MARK: Goals tab
    private var goalsTab: some View {
        VStack(spacing: 14) {
            ForEach(goals) { goal in
                AuroraCard {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            IconChip(symbol: goal.symbol, tint: Color(hex: goal.colorHex), size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.name).font(.subheadline.weight(.medium)).foregroundStyle(DS.inkPrimary)
                                Text("\(Money.string(goal.savedCents)) of \(Money.string(goal.targetCents))")
                                    .font(.caption).foregroundStyle(DS.inkTertiary)
                            }
                            Spacer()
                            Text("\(Int(goal.progress*100))%")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(goal.isComplete ? DS.moneyIn : DS.accentSoft)
                        }
                        ProgressBar(value: goal.progress,
                                    tint: goal.isComplete ? DS.moneyIn : Color(hex: goal.colorHex))
                        HStack {
                            Spacer()
                            Button {
                                goal.savedCents += 5000
                                try? context.save()
                                Haptics.tap()
                            } label: {
                                Text("+ \(Money.string(5000))")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(DS.accentDim, in: Capsule())
                                    .foregroundStyle(DS.accentSoft)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button { showAddGoal = true } label: {
                Label("New Goal", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(DS.bgCard, in: RoundedRectangle(cornerRadius: DS.corner))
                    .overlay(RoundedRectangle(cornerRadius: DS.corner)
                        .strokeBorder(DS.hairline, style: StrokeStyle(lineWidth: 1, dash: [5])))
                    .foregroundStyle(DS.accentSoft)
            }
            .buttonStyle(.plain)
        }
    }
}
