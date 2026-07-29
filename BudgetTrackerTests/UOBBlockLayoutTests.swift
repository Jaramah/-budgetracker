import XCTest
@testable import BudgetTracker

/// Regression tests for UOB's "trailing amount block" layout.
///
/// UOB prints the transaction table as `POST TRANS DESCRIPTION` rows with the SGD
/// amounts batched into a separate column block, so `parseBlock` pairs the two
/// positionally. That pairing is only correct if the two arrays stay in lockstep —
/// and on a real July 2026 statement they did not, which put every amount on the
/// wrong merchant while leaving each row looking perfectly plausible.
///
/// Three independent defects caused the drift, one test each below:
///   1. A standalone credit is two tokens ("2,040.69 CR"), so it was never counted
///      as a block amount — but its transaction still occupied a slot in `awaiting`.
///   2. The PREVIOUS BALANCE figure was counted as a transaction amount.
///   3. Summary-panel figures printed above the table header were counted too.
///
/// The fixture is the real statement's structure and amounts with the cardholder
/// name, card number and reference numbers removed.
final class UOBBlockLayoutTests: XCTestCase {

    // MARK: Fixture

    /// Page 1: summary panel (whose figures must be ignored), then the table.
    private let page1 = """
    KRISFLYER UOB CREDIT CARD
    2,406.52
    73.00
    PERSONAL LOAN
    348.51
    2,755.03
    421.51
    KRISFLYER UOB CREDIT CARD
    Post Trans Description of Transaction Transaction Amount
    Date Date SGD
    PREVIOUS BALANCE
    27 JUN 27 JUN PAYMT THRU E-BANK/HOMEB/CYBERB (EP50)
    24 JUN 18 JUN KOREAN AIRLINES Seoul
    Ref No. : REDACTED
    KRW 775,200.00
    22 JUN 20 JUN Xsolla*Xsolla Limassol
    Ref No. : REDACTED
    24 JUN 23 JUN OPENROUTER, INC NEW YORK
    Ref No. : REDACTED
    USD 10.80
    26 JUN 25 JUN DeepSeek HONG KONG
    Ref No. : REDACTED
    USD 53.00
    29 JUN 26 JUN THAI ODYSSEY SB-GSK GENTING HIGHL
    Ref No. : REDACTED
    MYR 698.75
    30 JUN 30 JUN HARVEY NORMAN-PARKWAY 04/12
    01 JUL 30 JUN www.anywheel.sg Singapore
    Ref No. : REDACTED
    02 JUL 01 JUL SP Digital PL-Utilitie SINGAPORE
    Ref No. : REDACTED
    02 JUL 01 JUL APPLE.COM/BILL CORK
    Ref No. : REDACTED
    2,040.69
    2,040.69 CR
    681.85
    150.47
    14.43
    71.12
    228.32
    511.08
    26.90
    25.57
    4.02
    """

    /// Page 2: continuation, terminated by the printed SUB TOTAL.
    private let page2 = """
    KRISFLYER UOB CREDIT CARD
    Post Trans Description of Transaction Transaction Amount
    Date Date SGD
    03 JUL 02 JUL P.SKOOL.COM/FQKLF EL SEGUNDO
    Ref No. : REDACTED
    USD 47.00
    04 JUL 03 JUL Xsolla*Xsolla Limassol
    Ref No. : REDACTED
    06 JUL 04 JUL APPLE.COM/SG SINGAPORE
    Ref No. : REDACTED
    07 JUL 06 JUL APPLE.COM/BILL CORK
    Ref No. : REDACTED
    13 JUL 11 JUL ATOME* AFTERSHOCK PC SINGAPORE
    Ref No. : REDACTED
    14 JUL 13 JUL Grab* A-9J28VVCGWQB8AV Singapore
    Ref No. : REDACTED
    17 JUL 15 JUL FAIRPRICE FINEST - BED SINGAPORE
    Ref No. : REDACTED
    62.98
    150.47
    150.70
    11.09
    300.88
    11.60
    5.04
    SUB TOTAL
    2,406.52
    """

    /// Merchant → amount in cents, exactly as the bank printed them.
    private let expected: [(desc: String, cents: Int)] = [
        ("KOREAN AIRLINES",   68185),
        ("Xsolla",            15047),
        ("OPENROUTER",         1443),
        ("DeepSeek",           7112),
        ("THAI ODYSSEY",      22832),
        ("HARVEY NORMAN",     51108),
        ("anywheel",           2690),
        ("SP Digital",         2557),
        ("APPLE.COM/BILL",      402),
        ("P.SKOOL",            6298),
        ("Xsolla",            15047),
        ("APPLE.COM/SG",      15070),
        ("APPLE.COM/BILL",     1109),
        ("ATOME",             30088),
        ("Grab",               1160),
        ("FAIRPRICE",           504),
    ]

    private func parsed() -> [StatementParser.ParsedLine] {
        LineStatementParser.parseBlock(pageTexts: [page1, page2])
    }

    // MARK: Tests

    /// The headline bug: each merchant must carry *its own* amount. Before the fix
    /// KOREAN AIRLINES (681.85) was shown as 14.43 — OPENROUTER's amount — and every
    /// row below it was shifted likewise.
    func testEachMerchantKeepsItsOwnAmount() {
        let rows = parsed()
        XCTAssertEqual(rows.count, expected.count,
                       "expected \(expected.count) debits, got \(rows.count)")
        for (i, want) in expected.enumerated() where i < rows.count {
            XCTAssertTrue(rows[i].desc.contains(want.desc),
                          "row \(i): expected description containing '\(want.desc)', got '\(rows[i].desc)'")
            XCTAssertEqual(rows[i].amountCents, want.cents,
                           "row \(i) '\(want.desc)': amount mispaired")
        }
    }

    /// The parsed debits must add up to the SUB TOTAL the bank printed. This is the
    /// check that would have caught the original bug on any bank, not just UOB —
    /// mispairing preserves the multiset of amounts, but dropping or duplicating one
    /// (which the credit desync did) breaks the sum.
    func testDebitsReconcileWithPrintedSubTotal() {
        let sum = parsed().reduce(0) { $0 + $1.amountCents }
        XCTAssertEqual(sum, 240652, "debits must equal the printed SUB TOTAL of 2,406.52")
    }

    /// The payment row is a credit and must not be imported as spending at all.
    func testPaymentCreditIsExcluded() {
        XCTAssertFalse(parsed().contains { $0.desc.uppercased().contains("PAYMT") },
                       "the 2,040.69 CR payment must not be imported as a charge")
        XCTAssertFalse(parsed().contains { $0.amountCents == 204069 },
                       "the previous-balance figure must never appear as a transaction")
    }

    /// Foreign-currency transactions: the SGD amount is what posts, and the FCY line
    /// belongs in the description, not in the amount column.
    func testForeignCurrencyRowsPostInSGD() {
        let rows = parsed()
        guard let korean = rows.first(where: { $0.desc.contains("KOREAN AIRLINES") }) else {
            return XCTFail("KOREAN AIRLINES row missing")
        }
        XCTAssertEqual(korean.amountCents, 68185, "KRW 775,200.00 must post as SGD 681.85")
        guard let openrouter = rows.first(where: { $0.desc.contains("OPENROUTER") }) else {
            return XCTFail("OPENROUTER row missing")
        }
        XCTAssertEqual(openrouter.amountCents, 1443, "USD 10.80 must post as SGD 14.43")
    }

    // MARK: Reconciliation helpers

    func testDeclaredTotalIsReadFromStatement() {
        let text = [page1, page2].joined(separator: "\n")
        XCTAssertEqual(StatementParser.declaredTotalCents(in: text), 240652)
    }

    /// A mispaired parse that still uses every amount would slip past a naive sum,
    /// so confirm the guard rejects a parse that drops or invents one.
    func testReconcilesRejectsWrongTotal() {
        let good = parsed()
        XCTAssertTrue(StatementParser.reconciles(good, declared: 240652))
        XCTAssertFalse(StatementParser.reconciles(Array(good.dropLast()), declared: 240652))
        // No printed total to check against → never rejects.
        XCTAssertTrue(StatementParser.reconciles(good, declared: nil))
    }
}
