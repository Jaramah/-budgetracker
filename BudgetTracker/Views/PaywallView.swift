import SwiftUI

/// The Pro upgrade sheet. A single one-time purchase that removes ads and lifts
/// the free one-card limit. Shown when a free user hits the card limit, and from
/// Settings.
struct PaywallView: View {
    @EnvironmentObject private var store: ProStore
    @Environment(\.dismiss) private var dismiss

    /// Optional context line explaining why the sheet appeared (e.g. hit the card limit).
    var reason: String?

    @State private var restoreMessage: String?
    @State private var purchaseMessage: String?

    private let features: [(String, String, String)] = [
        ("creditcard.fill", "Unlimited cards", "Add as many credit cards as you like and import each one's statements."),
        ("arrow.triangle.2.circlepath", "Subscription tracker", "Auto-spot recurring charges and get reminded before they renew — so you can cancel what you don't use."),
        ("hand.raised.slash.fill", "No ads", "Remove the banner ads across every tab."),
        ("heart.fill", "Support development", "A one-time purchase that keeps the app growing — no subscription.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    if let reason {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(DS.inkSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 12) {
                        ForEach(features, id: \.1) { feature in
                            featureRow(icon: feature.0, title: feature.1, subtitle: feature.2)
                        }
                    }
                    buyButton
                    restoreButton
                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .auroraBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.tint(DS.accent)
                }
            }
        }
        .tint(DS.accent)
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
        .alert("Restore Purchases", isPresented: .constant(restoreMessage != nil)) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
        .alert("Purchase", isPresented: .constant(purchaseMessage != nil)) {
            Button("OK") { purchaseMessage = nil }
        } message: {
            Text(purchaseMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            IconChip(symbol: "crown.fill", tint: DS.accent, size: 64)
            Text("Budget Pro")
                .font(.largeTitle.bold())
                .foregroundStyle(DS.inkPrimary)
            Text("Unlock everything with a one-time purchase.")
                .font(.subheadline)
                .foregroundStyle(DS.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconChip(symbol: icon, tint: DS.accentSoft, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.inkPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DS.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.cardPadding)
        .background(DS.bgCard, in: RoundedRectangle(cornerRadius: DS.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.corner, style: .continuous)
            .strokeBorder(DS.hairline, lineWidth: 1))
    }

    private var buyButton: some View {
        Button {
            Task {
                switch await store.purchase() {
                case .success, .cancelled:
                    break               // success dismisses via onChange; cancel is silent
                case .pending:
                    purchaseMessage = "Your purchase is pending approval. Pro unlocks once it's approved."
                case .unavailable:
                    purchaseMessage = "Budget Pro isn't available right now. If you're testing, run the app from Xcode (or sign in to a Sandbox account); otherwise check your connection and try again."
                case .failed(let reason):
                    purchaseMessage = reason
                }
            }
        } label: {
            HStack {
                if store.purchaseInFlight {
                    ProgressView().tint(.white)
                } else {
                    Text(buyTitle).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: [DS.accent, DS.accentSoft],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: DS.corner, style: .continuous)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(store.purchaseInFlight)
    }

    private var buyTitle: String {
        let price = store.priceText
        return price.isEmpty ? "Unlock Pro" : "Unlock Pro — \(price)"
    }

    private var restoreButton: some View {
        Button {
            Task {
                let ok = await store.restore()
                restoreMessage = ok
                    ? "Your Pro purchase has been restored."
                    : "No previous purchase was found on this Apple ID."
            }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.accentSoft)
        }
        .buttonStyle(.plain)
    }

    private var legalFooter: some View {
        Text("One-time purchase. No subscription. Restores across devices signed in to the same Apple ID.")
            .font(.caption2)
            .foregroundStyle(DS.inkTertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}
