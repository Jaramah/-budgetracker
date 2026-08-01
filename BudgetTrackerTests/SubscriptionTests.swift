import XCTest
import SwiftData
@testable import BudgetTracker

@MainActor
final class SubscriptionTests: XCTestCase {

    // MARK: matchKey normalization

    func testMatchKeyNormalization() {
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "NETFLIX.COM"), "netflix")
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "SPOTIFY P42A314ACB STOCKHOLM SE"), "spotify")
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "GOMO BY SINGTEL"), "gomo")
        XCTAssertNil(SubscriptionDetector.matchKey(for: "1234 5678"))
    }

    /// Processor-routed charges print the gateway first, so keying on the leading
    /// token grouped every PayPal subscription under "paypal" and matched none of
    /// them to their real brand.
    func testMatchKeySkipsPaymentProcessorPrefixes() {
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "PAYPAL *SPOTIFY"), "spotify")
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "PAYPAL*NETFLIX"), "netflix")
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "SQ * MUBI LONDON"), "mubi")
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "GOOGLE *YouTube Premium"), "youtube")
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "STRIPE *NOTION LABS"), "notion")
    }

    /// The prefix rule needs the gateway's `*`. A merchant that merely begins with
    /// one of those words must be left alone.
    func testProcessorStrippingRequiresTheGatewayMarker() {
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "GOOGLE ONE"), "google")
        XCTAssertEqual(SubscriptionDetector.matchKey(for: "AMAZON PRIME VIDEO"), "amazon")
        XCTAssertEqual(SubscriptionDetector.strippingProcessorPrefix("SQUARE ENIX"), "SQUARE ENIX")
    }

    /// A processor prefix with nothing after it must not erase the description.
    func testProcessorStrippingKeepsSomethingUsable() {
        XCTAssertEqual(SubscriptionDetector.strippingProcessorPrefix("PAYPAL *"), "PAYPAL *")
        XCTAssertNotNil(SubscriptionDetector.matchKey(for: "PAYPAL *"))
    }

    // MARK: detection

    func testKnownBrandDetectedFromSingleCharge() throws {
        let ctx = try makeContext()
        ctx.insert(Transaction(amountCents: 1998, note: "NETFLIX.COM", date: .now))
        try ctx.save()

        let added = SubscriptionDetector.refresh(transactions: allTx(ctx), context: ctx)
        XCTAssertEqual(added, 1)
        let subs = try ctx.fetch(FetchDescriptor<Subscription>())
        XCTAssertEqual(subs.first?.name, "Netflix")
        XCTAssertEqual(subs.first?.status, .suggested)
        XCTAssertEqual(subs.first?.amountCents, 1998)
    }

    func testRecurringUnknownMerchantDetectedAsMonthly() throws {
        let ctx = try makeContext()
        let cal = DateHelpers.calendar
        for m in [0, 1, 2] {
            let d = cal.date(byAdding: .month, value: -m, to: .now)!
            ctx.insert(Transaction(amountCents: 1299, note: "IRONWORKS GYM", date: d))
        }
        try ctx.save()

        SubscriptionDetector.refresh(transactions: allTx(ctx), context: ctx)
        let subs = try ctx.fetch(FetchDescriptor<Subscription>())
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.cycle, .monthly)
    }

    func testAmbiguousBrandSingleChargeNotDetected() throws {
        // A one-off Apple Store purchase must NOT be flagged as a subscription.
        let ctx = try makeContext()
        ctx.insert(Transaction(amountCents: 19900, note: "APPLE STORE ORCHARD", date: .now))
        try ctx.save()

        let added = SubscriptionDetector.refresh(transactions: allTx(ctx), context: ctx)
        XCTAssertEqual(added, 0, "ambiguous retail brands need a recurring pattern to count")
    }

    func testOneOffUnknownMerchantNotDetected() throws {
        let ctx = try makeContext()
        ctx.insert(Transaction(amountCents: 4500, note: "CORNER BISTRO", date: .now))
        try ctx.save()

        let added = SubscriptionDetector.refresh(transactions: allTx(ctx), context: ctx)
        XCTAssertEqual(added, 0, "a single charge from an unknown merchant is not a subscription")
    }

    func testDismissedMerchantNotResuggested() throws {
        let ctx = try makeContext()
        ctx.insert(Transaction(amountCents: 1699, note: "SPOTIFY SG"))
        try ctx.save()
        SubscriptionDetector.refresh(transactions: allTx(ctx), context: ctx)

        let sub = try ctx.fetch(FetchDescriptor<Subscription>()).first!
        sub.status = .dismissed
        try ctx.save()

        let added = SubscriptionDetector.refresh(transactions: allTx(ctx), context: ctx)
        XCTAssertEqual(added, 0, "a dismissed merchant must never be re-suggested")
    }

    // MARK: model math

    func testMonthlyEquivalent() {
        let yearly = Subscription(name: "X", matchKey: "x", amountCents: 12000, cycle: .yearly)
        XCTAssertEqual(yearly.monthlyEquivalentCents, 1000)
        let weekly = Subscription(name: "Y", matchKey: "y", amountCents: 1200, cycle: .weekly)
        XCTAssertEqual(weekly.monthlyEquivalentCents, (1200 * 52) / 12)
    }

    func testNextRenewalRollsIntoTheFuture() {
        let cal = DateHelpers.calendar
        let twoMonthsAgo = cal.date(byAdding: .month, value: -2, to: .now)!
        let sub = Subscription(name: "X", matchKey: "x", amountCents: 1000,
                               cycle: .monthly, anchorDate: twoMonthsAgo)
        XCTAssertGreaterThanOrEqual(sub.nextRenewal(), cal.startOfDay(for: .now))
    }

    // MARK: helpers

    private func allTx(_ ctx: ModelContext) -> [Transaction] {
        (try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Transaction.self, Subscription.self, Category.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }
}
