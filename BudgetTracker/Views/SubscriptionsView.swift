import SwiftUI
import SwiftData

/// Subscription tracker. Free users see a teaser (count + monthly cost) behind a
/// paywall; Pro users get the full list, suggestions to confirm, cancel reminders,
/// and manual add/edit.
struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProStore

    @Query private var transactions: [Transaction]
    @Query(sort: \Subscription.name) private var subs: [Subscription]

    @State private var showPaywall = false
    @State private var editing: Subscription?
    @State private var showAdd = false

    // MARK: Derived
    private var suggested: [Subscription] { subs.filter { $0.status == .suggested } }
    private var active: [Subscription] {
        subs.filter { $0.status == .active }.sorted { $0.nextRenewal() < $1.nextRenewal() }
    }
    /// What the teaser counts: everything not dismissed/cancelled.
    private var previewSet: [Subscription] { active + suggested }
    private var activeMonthlyCents: Int { active.reduce(0) { $0 + $1.monthlyEquivalentCents } }
    private var teaserMonthlyCents: Int { previewSet.reduce(0) { $0 + $1.monthlyEquivalentCents } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.isPro {
                        proContent
                    } else {
                        teaser
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .auroraBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("Subscriptions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.tint(DS.accent)
                }
                if store.isPro {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }.tint(DS.accent)
                    }
                }
            }
        }
        .tint(DS.accent)
        .task { SubscriptionDetector.refresh(transactions: transactions, context: context) }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Unlock Pro to see every subscription and get reminders before they renew.")
        }
        .sheet(isPresented: $showAdd) { SubscriptionEditView(subscription: nil) }
        .sheet(item: $editing) { SubscriptionEditView(subscription: $0) }
    }

    // MARK: - Free teaser

    @ViewBuilder
    private var teaser: some View {
        AuroraCard(padding: 20) {
            VStack(spacing: 14) {
                IconChip(symbol: "arrow.triangle.2.circlepath.circle.fill", tint: DS.accent, size: 56)
                if previewSet.isEmpty {
                    Text("Find your subscriptions")
                        .font(.title3.bold()).foregroundStyle(DS.inkPrimary)
                    Text("Import a card statement and Budget Pro spots recurring charges like Netflix, Spotify and your telco — then reminds you before they renew.")
                        .font(.subheadline).foregroundStyle(DS.inkTertiary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("We found \(previewSet.count) subscription\(previewSet.count == 1 ? "" : "s")")
                        .font(.title3.bold()).foregroundStyle(DS.inkPrimary)
                    Text("costing about \(Money.string(teaserMonthlyCents)) / month")
                        .font(.subheadline).foregroundStyle(DS.inkSecondary)
                }
            }
        }

        if !previewSet.isEmpty {
            AuroraCard {
                VStack(spacing: 0) {
                    ForEach(Array(previewSet.prefix(4).enumerated()), id: \.element.id) { i, sub in
                        if i > 0 { Divider().overlay(DS.hairline) }
                        HStack(spacing: 12) {
                            IconChip(symbol: "creditcard.fill", tint: DS.accentSoft, size: 36)
                            Text(sub.name).font(.subheadline.weight(.medium)).foregroundStyle(DS.inkPrimary)
                            Spacer()
                            Image(systemName: "lock.fill").font(.footnote).foregroundStyle(DS.inkTertiary)
                        }
                        .padding(.vertical, 10)
                    }
                    if previewSet.count > 4 {
                        Divider().overlay(DS.hairline)
                        Text("and \(previewSet.count - 4) more")
                            .font(.caption).foregroundStyle(DS.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }
                }
            }
        }

        unlockButton
    }

    private var unlockButton: some View {
        Button { showPaywall = true } label: {
            HStack {
                Image(systemName: "crown.fill")
                Text("Unlock with Budget Pro").fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(LinearGradient(colors: [DS.accent, DS.accentSoft],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: DS.corner, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pro content

    @ViewBuilder
    private var proContent: some View {
        summaryCard

        if !suggested.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SUGGESTED").font(.caption.weight(.semibold)).foregroundStyle(DS.inkTertiary)
                    .padding(.leading, 4)
                ForEach(suggested) { sub in suggestionRow(sub) }
            }
        }

        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("ACTIVE").font(.caption.weight(.semibold)).foregroundStyle(DS.inkTertiary)
                    .padding(.leading, 4)
                ForEach(active) { sub in activeRow(sub) }
            }
        }

        if active.isEmpty && suggested.isEmpty {
            AuroraCard {
                VStack(spacing: 8) {
                    IconChip(symbol: "magnifyingglass", tint: DS.inkTertiary, size: 40)
                    Text("No subscriptions yet").font(.subheadline.weight(.medium)).foregroundStyle(DS.inkPrimary)
                    Text("Import a card statement to auto-detect them, or add one manually with +.")
                        .font(.caption).foregroundStyle(DS.inkTertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }

        Button { showAdd = true } label: {
            Label("Add subscription", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(DS.bgCard, in: RoundedRectangle(cornerRadius: DS.corner))
                .overlay(RoundedRectangle(cornerRadius: DS.corner)
                    .strokeBorder(DS.hairline, style: StrokeStyle(lineWidth: 1, dash: [5])))
                .foregroundStyle(DS.accentSoft)
        }
        .buttonStyle(.plain)
    }

    private var summaryCard: some View {
        AuroraCard(padding: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly").font(.caption).foregroundStyle(DS.inkTertiary)
                    MoneyText(cents: activeMonthlyCents, size: 30, color: DS.inkPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Yearly").font(.caption).foregroundStyle(DS.inkTertiary)
                    Text(Money.string(activeMonthlyCents * 12))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(DS.inkSecondary)
                }
            }
        }
    }

    private func suggestionRow(_ sub: Subscription) -> some View {
        AuroraCard {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    IconChip(symbol: "sparkles", tint: DS.accent, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sub.name).font(.subheadline.weight(.semibold)).foregroundStyle(DS.inkPrimary)
                        Text("\(Money.string(sub.amountCents)) \(sub.cycle.perLabel) · looks recurring")
                            .font(.caption).foregroundStyle(DS.inkTertiary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button { dismissSuggestion(sub) } label: {
                        Text("Not a subscription").font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(DS.bgCardHi, in: Capsule()).foregroundStyle(DS.inkSecondary)
                    }.buttonStyle(.plain)
                    Button { confirm(sub) } label: {
                        Text("Track it").font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(DS.accentDim, in: Capsule()).foregroundStyle(DS.accentSoft)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func activeRow(_ sub: Subscription) -> some View {
        Button { editing = sub } label: {
            AuroraCard {
                HStack(spacing: 12) {
                    IconChip(symbol: sub.category?.symbol ?? "creditcard.fill",
                             tint: sub.category?.color ?? DS.accentSoft, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sub.name).font(.subheadline.weight(.medium)).foregroundStyle(DS.inkPrimary)
                        HStack(spacing: 6) {
                            if sub.reminderEnabled {
                                Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(DS.accent)
                            }
                            Text("Renews \(DateHelpers.mediumDate(sub.nextRenewal()))")
                                .font(.caption).foregroundStyle(DS.inkTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Money.string(sub.amountCents))
                            .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(DS.inkPrimary)
                        Text(sub.cycle.perLabel).font(.caption2).foregroundStyle(DS.inkTertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func confirm(_ sub: Subscription) {
        sub.status = .active
        sub.updatedAt = .now
        try? context.save()
        reschedule()
        Haptics.success()
    }

    private func dismissSuggestion(_ sub: Subscription) {
        sub.status = .dismissed
        try? context.save()
        Haptics.tap()
    }

    private func reschedule() {
        SubscriptionReminderScheduler.reschedule(subscriptions: subs)
    }
}
