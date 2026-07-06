import StoreKit
import SwiftUI

/// StoreKit 2 wrapper for the single non-consumable **Pro** unlock.
///
/// Pro is a one-time purchase that (1) removes ads and (2) lifts the free-tier
/// one-card limit. `isPro` is the single source of truth the rest of the app
/// reads; it's cached to `UserDefaults` so gating is correct at the very first
/// frame (StoreKit's `currentEntitlements` is async and would otherwise flash
/// the free state on cold launch).
@MainActor
final class ProStore: ObservableObject {
    /// Must match the non-consumable product ID created in App Store Connect
    /// (and in `BudgetTracker.storekit` for local testing).
    static let productID = "com.github.jaramah.BudgetTracker.pro"

    /// Free users may keep at most this many cards; Pro is unlimited.
    static let freeCardLimit = 1

    @Published private(set) var product: Product?
    @Published private(set) var isPro: Bool
    @Published private(set) var purchaseInFlight = false

    private static let cacheKey = "proUnlocked"
    private var updatesTask: Task<Void, Never>?

    init() {
        // Optimistic launch-time value; reconciled against StoreKit in `refresh()`.
        isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)
        updatesTask = observeTransactionUpdates()
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    /// Localised price (e.g. "S$3.98") once the product has loaded, else "".
    var priceText: String { product?.displayPrice ?? "" }

    /// Whether a free user with `count` cards is allowed to add another.
    func canAddCard(currentCount count: Int) -> Bool {
        isPro || count < Self.freeCardLimit
    }

    /// Load the product metadata and reconcile the current entitlement.
    func refresh() async {
        await loadProduct()
        await updateEntitlement()
    }

    private func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            // Offline / not yet configured in App Store Connect — try again later.
        }
    }

    /// Recompute `isPro` from StoreKit's verified current entitlements.
    private func updateEntitlement() async {
        var unlocked = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.productID,
               tx.revocationDate == nil {
                unlocked = true
            }
        }
        setPro(unlocked)
    }

    /// Kick off the purchase flow. Returns true once Pro is unlocked.
    @discardableResult
    func purchase() async -> Bool {
        if product == nil { await loadProduct() }
        guard let product else { return false }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let tx) = verification else { return false }
                await tx.finish()
                setPro(true)
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    /// Restore a previous purchase (new device / reinstall). Returns `isPro`.
    @discardableResult
    func restore() async -> Bool {
        try? await AppStore.sync()
        await updateEntitlement()
        return isPro
    }

    private func setPro(_ value: Bool) {
        if isPro != value { isPro = value }
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
    }

    /// Long-lived listener so entitlements from another device (or Ask-to-Buy
    /// approvals) unlock Pro without a relaunch.
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await _ in StoreKit.Transaction.updates {
                await self?.updateEntitlement()
            }
        }
    }
}
