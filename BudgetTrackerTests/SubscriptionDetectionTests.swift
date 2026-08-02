import XCTest
import SwiftData
@testable import BudgetTracker

/// Subscription detection, and — more importantly — what it must *refuse* to detect.
///
/// A regular habit is indistinguishable from a subscription by shape alone. The
/// same commute on the same date each month, at the same fare, produces exactly the
/// signal a monthly subscription does. These tests pin the guards that keep those
/// out, because a detector that flags your Grab rides is worse than one that misses
/// a streaming service.
@MainActor
final class SubscriptionDetectionTests: XCTestCase {

    private let cal = DateHelpers.calendar

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    private func tx(_ note: String, _ cents: Int, _ d: Date, category: Category? = nil) -> Transaction {
        Transaction(amountCents: cents, isExpense: true, note: note, date: d,
                    category: category, paymentMethod: .credit)
    }

    /// An in-memory container so `refresh` can insert without touching the real store.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Category.self, Transaction.self, Subscription.self,
                             CreditCardAccount.self, StatementImport.self, StatementLine.self,
                             RecurringRule.self, Goal.self, Bill.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func detect(_ txs: [Transaction]) throws -> [Subscription] {
        let ctx = try makeContext()
        SubscriptionDetector.refresh(transactions: txs, context: ctx)
        return (try? ctx.fetch(FetchDescriptor<Subscription>())) ?? []
    }

    // MARK: - Must NOT be detected

    /// The reported worry: the same trip, same fare, same date, every month.
    /// Regular by every measure, and still not a subscription.
    func testMonthlyGrabRideAtTheSameFareIsNotASubscription() throws {
        let txs = [
            tx("Grab* A-9JENDDUGXEJ Singapore SG", 1820, date(2026, 5, 16)),
            tx("Grab* A-9JFQMC9WW39 Singapore SG", 1820, date(2026, 6, 16)),
            tx("Grab* A-9JXYZ12AB34 Singapore SG", 1820, date(2026, 7, 16))
        ]
        let subs = try detect(txs)
        XCTAssertFalse(subs.contains { $0.matchKey == "grab" },
                       "a monthly commute must never be flagged as a subscription")
    }

    /// Two charges inside one month disqualify a monthly cadence outright — the
    /// guard that works even for merchants on no list at all.
    func testTwoChargesInOneMonthDisqualifyMonthly() {
        let txs = [
            tx("SOMEPLACE", 1000, date(2026, 5, 3)),
            tx("SOMEPLACE", 1000, date(2026, 5, 16)),
            tx("SOMEPLACE", 1000, date(2026, 6, 3))
        ]
        XCTAssertFalse(
            SubscriptionDetector.chargedAtMostOncePerCycle(txs.sorted { $0.date < $1.date },
                                                           cycle: .monthly),
            "a merchant charged twice in May cannot be a monthly subscription")
    }

    /// Category is the second guard, for merchants not on the keyword list.
    func testTransportCategoryIsNeverASubscription() throws {
        let ctx = try makeContext()
        let transport = Category(name: "Transport")
        ctx.insert(transport)
        let txs = [
            tx("SOMECAB CO", 2500, date(2026, 5, 10), category: transport),
            tx("SOMECAB CO", 2500, date(2026, 6, 10), category: transport),
            tx("SOMECAB CO", 2500, date(2026, 7, 10), category: transport)
        ]
        txs.forEach { ctx.insert($0) }
        SubscriptionDetector.refresh(transactions: txs, context: ctx)
        let subs = (try? ctx.fetch(FetchDescriptor<Subscription>())) ?? []
        XCTAssertFalse(subs.contains { $0.matchKey == "somecab" },
                       "anything the user files under Transport is not a subscription")
    }

    func testFoodAndGroceryMerchantsAreExcluded() {
        for key in ["grab", "foodpanda", "deliveroo", "fairprice", "starbucks", "clinic"] {
            XCTAssertTrue(SubscriptionDetector.isNeverSubscription(key: key, txs: []),
                          "\(key) should be excluded from subscription detection")
        }
        XCTAssertFalse(SubscriptionDetector.isNeverSubscription(key: "netflix", txs: []))
        XCTAssertFalse(SubscriptionDetector.isNeverSubscription(key: "playstation", txs: []))
    }

    /// Two occurrences is a coincidence any habit produces; three is a pattern.
    func testTwoChargesAreNotEnoughForAnUnknownMerchant() throws {
        let txs = [
            tx("OBSCURE SERVICE", 990, date(2026, 6, 12)),
            tx("OBSCURE SERVICE", 990, date(2026, 7, 12))
        ]
        let subs = try detect(txs)
        XCTAssertTrue(subs.isEmpty, "two charges are not enough evidence")
    }

    // MARK: - Must still be detected

    /// A known brand needs no pattern — one charge is enough.
    func testKnownBrandDetectedFromASingleCharge() throws {
        let subs = try detect([tx("NETFLIX.COM SINGAPORE", 1998, date(2026, 7, 3))])
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.name, "Netflix")
    }

    /// Three steady monthly charges from a merchant we don't recognise.
    func testUnknownMerchantWithThreeSteadyChargesIsSuggested() throws {
        let txs = [
            tx("OBSCURE SERVICE", 990, date(2026, 5, 12)),
            tx("OBSCURE SERVICE", 990, date(2026, 6, 12)),
            tx("OBSCURE SERVICE", 990, date(2026, 7, 12))
        ]
        let subs = try detect(txs)
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.cycle, .monthly)
        XCTAssertEqual(subs.first?.status, .suggested,
                       "a guess must be suggested, never activated behind the user's back")
    }

    /// A price rise used to kill detection, because amount stability was mandatory.
    /// The steady billing day now carries it — and a price change is exactly the
    /// thing worth surfacing.
    func testPriceRiseStillDetectedViaStableBillingDay() throws {
        let txs = [
            tx("OBSCURE SERVICE", 990, date(2026, 5, 12)),
            tx("OBSCURE SERVICE", 990, date(2026, 6, 12)),
            tx("OBSCURE SERVICE", 1490, date(2026, 7, 12))
        ]
        let subs = try detect(txs)
        XCTAssertEqual(subs.count, 1, "a price change must not hide a subscription")
        XCTAssertEqual(subs.first?.amountCents, 1490, "tracks the latest price")
    }

    func testQuarterlyCadenceIsDetected() throws {
        let txs = [
            tx("OBSCURE SERVICE", 2990, date(2026, 1, 12)),
            tx("OBSCURE SERVICE", 2990, date(2026, 4, 12)),
            tx("OBSCURE SERVICE", 2990, date(2026, 7, 12))
        ]
        let subs = try detect(txs)
        XCTAssertEqual(subs.first?.cycle, .quarterly, "90-day gaps are quarterly, not nothing")
    }

    // MARK: - Billing-day helper

    func testStableBillingDayToleratesSmallDrift() {
        let steady = [tx("X", 100, date(2026, 5, 12)),
                      tx("X", 100, date(2026, 6, 13)),
                      tx("X", 100, date(2026, 7, 11))]
        XCTAssertTrue(SubscriptionDetector.billedOnAStableDayOfMonth(steady))

        let scattered = [tx("X", 100, date(2026, 5, 2)),
                         tx("X", 100, date(2026, 6, 19)),
                         tx("X", 100, date(2026, 7, 27))]
        XCTAssertFalse(SubscriptionDetector.billedOnAStableDayOfMonth(scattered))
    }

    /// Month-end billing wraps past the 1st and must still count as steady.
    func testStableBillingDayHandlesMonthEndWrap() {
        let wrapped = [tx("X", 100, date(2026, 4, 30)),
                       tx("X", 100, date(2026, 6, 1)),
                       tx("X", 100, date(2026, 6, 30))]
        XCTAssertTrue(SubscriptionDetector.billedOnAStableDayOfMonth(wrapped),
                      "the 30th and the 1st are two days apart, not 29")
    }

    // MARK: - Refresh keeps tracked subscriptions current

    func testRefreshUpdatesAnExistingSubscriptionsPrice() throws {
        let ctx = try makeContext()
        let existing = Subscription(name: "Obscure", matchKey: "obscure",
                                    amountCents: 990, cycle: .monthly,
                                    anchorDate: date(2026, 5, 12), status: .active)
        ctx.insert(existing)

        let txs = [tx("OBSCURE SERVICE", 1490, date(2026, 7, 12))]
        SubscriptionDetector.refresh(transactions: txs, context: ctx)

        XCTAssertEqual(existing.amountCents, 1490, "price rise must be picked up")
        XCTAssertEqual(cal.dateComponents([.month], from: existing.anchorDate).month, 7,
                       "anchor should advance to the latest charge")
    }

    /// Detection must never touch imported transactions — it only ever inserts
    /// Subscription rows, so an import cannot be altered by a wrong guess.
    func testDetectionLeavesTransactionsUntouched() throws {
        let ctx = try makeContext()
        let t = tx("NETFLIX.COM", 1998, date(2026, 7, 3))
        t.isReconciled = true
        ctx.insert(t)
        SubscriptionDetector.refresh(transactions: [t], context: ctx)

        XCTAssertEqual(t.amountCents, 1998)
        XCTAssertEqual(t.note, "NETFLIX.COM")
        XCTAssertTrue(t.isReconciled)
        XCTAssertNil(t.category)
    }
}
