import XCTest
@testable import BudgetTracker

/// Guards the free-tier card gate so a refactor can't silently let free users add
/// unlimited cards (which would give away Pro's main benefit).
@MainActor
final class MonetizationTests: XCTestCase {

    func testFreeTierIsLimitedToOneCard() {
        // Start from a known non-Pro state.
        UserDefaults.standard.removeObject(forKey: "proUnlocked")
        let store = ProStore()

        XCTAssertEqual(ProStore.freeCardLimit, 1)
        XCTAssertFalse(store.isPro, "A fresh install should not be Pro")

        XCTAssertTrue(store.canAddCard(currentCount: 0),  "First card is free")
        XCTAssertFalse(store.canAddCard(currentCount: 1), "A second card requires Pro")
        XCTAssertFalse(store.canAddCard(currentCount: 5), "Still gated well past the limit")
    }

    func testProProductIDMatchesStoreKitConfig() {
        // Must stay in sync with BudgetTracker.storekit and App Store Connect.
        XCTAssertEqual(ProStore.productID, "com.github.jaramah.BudgetTracker.pro")
    }
}
