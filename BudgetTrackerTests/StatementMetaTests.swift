import XCTest
@testable import BudgetTracker

/// Statement-level metadata: the dates a statement prints about itself, and the
/// foreign-currency amounts the row parsers previously folded into descriptions.
final class StatementMetaTests: XCTestCase {

    private let cal = DateHelpers.calendar
    private func ymd(_ d: Date?) -> (y: Int, m: Int, day: Int)? {
        guard let d else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Statement / due dates

    /// The real UOB layout, label and value on one line.
    func testReadsStatementAndDueDateFromSameLine() {
        let text = """
        Statement Summary
        Statement Date                                 19 JUL 2026
        Total Credit Limit                               SGD 25,200
        Payment Summary
        Amount to Pay                                 SGD 2,755.03
        Due Date                                      07 AUG 2026
        """
        let meta = StatementParser.statementMeta(in: text)
        XCTAssertEqual(ymd(meta.statementDate)?.day, 19)
        XCTAssertEqual(ymd(meta.statementDate)?.m, 7)
        XCTAssertEqual(ymd(meta.dueDate)?.day, 7)
        XCTAssertEqual(ymd(meta.dueDate)?.m, 8)
        XCTAssertEqual(ymd(meta.dueDate)?.y, 2026)
    }

    /// PDFKit's stream order routinely splits a label from its value.
    func testReadsDatesSplitAcrossLines() {
        let text = """
        Statement Date
        19 JUL 2026
        Due Date
        07 AUG 2026
        """
        let meta = StatementParser.statementMeta(in: text)
        XCTAssertEqual(ymd(meta.statementDate)?.day, 19)
        XCTAssertEqual(ymd(meta.dueDate)?.day, 7)
        XCTAssertEqual(ymd(meta.dueDate)?.m, 8)
    }

    /// "Payment Due Date" contains "date" too — the due label must win its row
    /// rather than being claimed as the statement date.
    func testPaymentDueDateVariantIsNotMistakenForStatementDate() {
        let text = """
        Payment Due Date: 07 Aug 2026
        Statement Date: 19 Jul 2026
        """
        let meta = StatementParser.statementMeta(in: text)
        XCTAssertEqual(ymd(meta.dueDate)?.m, 8)
        XCTAssertEqual(ymd(meta.statementDate)?.m, 7)
    }

    func testSlashAndISODateFormats() {
        let slash = StatementParser.statementMeta(in: "Statement Date 19/07/2026")
        XCTAssertEqual(ymd(slash.statementDate)?.day, 19)
        let iso = StatementParser.statementMeta(in: "Statement Date 2026-07-19")
        XCTAssertEqual(ymd(iso.statementDate)?.m, 7)
        XCTAssertEqual(ymd(iso.statementDate)?.day, 19)
    }

    /// A statement with no such labels must yield nothing rather than guessing.
    func testAbsentDatesAreNil() {
        let meta = StatementParser.statementMeta(in: "16 May NTUC FAIRPRICE 52.30")
        XCTAssertNil(meta.statementDate)
        XCTAssertNil(meta.dueDate)
    }

    // MARK: Foreign currency

    func testExtractsForeignAmountAndCleansDescription() {
        guard let f = StatementParser.foreignAmount(in: "KOREAN AIRLINES Seoul KRW 775,200.00") else {
            return XCTFail("expected a foreign amount")
        }
        XCTAssertEqual(f.code, "KRW")
        XCTAssertEqual(f.cents, 77_520_000)
        XCTAssertEqual(f.cleanedDescription, "KOREAN AIRLINES Seoul")
    }

    func testExtractsUSDAndMYR() {
        XCTAssertEqual(StatementParser.foreignAmount(in: "OPENROUTER, INC NEW YORK USD 10.80")?.cents, 1080)
        XCTAssertEqual(StatementParser.foreignAmount(in: "THAI ODYSSEY GENTING MYR 698.75")?.code, "MYR")
    }

    /// Three capitals are not automatically a currency — otherwise ordinary
    /// merchant words would be stripped out of descriptions.
    func testNonCurrencyTokensAreIgnored() {
        XCTAssertNil(StatementParser.foreignAmount(in: "THE COFFEE BEAN 12.50"))
        XCTAssertNil(StatementParser.foreignAmount(in: "GST 8"))
        XCTAssertNil(StatementParser.foreignAmount(in: "NTUC FAIRPRICE"))
        XCTAssertNil(StatementParser.foreignAmount(in: "APPLE.COM/BILL CORK"))
    }

    /// The SGD amount posted to the card is unchanged; only the description moves.
    func testAnnotationPreservesPostedAmount() {
        let line = StatementParser.ParsedLine(date: .now,
                                              desc: "DeepSeek HONG KONG USD 53.00",
                                              amountCents: 7112)
        let out = StatementParser.annotateForeignAmounts([line])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].amountCents, 7112, "the SGD charge must not change")
        XCTAssertEqual(out[0].foreignCurrency, "USD")
        XCTAssertEqual(out[0].foreignAmountCents, 5300)
        XCTAssertEqual(out[0].desc, "DeepSeek HONG KONG")
    }

    /// Rows without a foreign fragment must pass through untouched.
    func testAnnotationLeavesDomesticRowsAlone() {
        let line = StatementParser.ParsedLine(date: .now, desc: "NTUC FAIRPRICE", amountCents: 5230)
        let out = StatementParser.annotateForeignAmounts([line])
        XCTAssertEqual(out[0].desc, "NTUC FAIRPRICE")
        XCTAssertNil(out[0].foreignCurrency)
        XCTAssertNil(out[0].foreignAmountCents)
    }
}
