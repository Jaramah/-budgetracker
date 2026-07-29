import XCTest
@testable import BudgetTracker

/// CSV import.
///
/// The original parser took the *rightmost* money-shaped column on every row and
/// stripped every non-digit from anything it inspected. Both are wrong in ways
/// that corrupt data silently rather than failing:
///
///   • `Date, Description, Amount, Balance` is the standard bank export, so the
///     rightmost number is the running balance — every import recorded balances.
///   • A date column parsed as a number: "16/05/2026" became $160,520.26.
///   • Credits were never excluded, so salary and refunds counted as spending.
///   • dd/MM was always tried before MM/dd, silently swapping US dates.
final class CSVParserTests: XCTestCase {

    private let cal = DateHelpers.calendar

    private func day(_ d: Date) -> (Int, Int, Int) {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Balance column

    /// The headline bug: the balance must never be imported as a charge.
    func testAmountIsReadFromTheAmountColumnNotTheBalance() {
        let csv = """
        Date,Description,Amount,Balance
        05/07/2026,COLD STORAGE,42.30,1958.70
        06/07/2026,SHELL PETROL,88.00,1870.70
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].amountCents, 4230, "must be the amount, not the 1958.70 balance")
        XCTAssertEqual(out[1].amountCents, 8800)
        XCTAssertEqual(out.map(\.desc), ["COLD STORAGE", "SHELL PETROL"])
    }

    /// A balance column can also sit before the amount, or be named differently.
    func testClosingBalanceIsExcludedWhereverItSits() {
        let csv = """
        Transaction Date,Particulars,Closing Balance,Debit Amount
        05/07/2026,NTUC FAIRPRICE,1958.70,42.30
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].amountCents, 4230)
    }

    // MARK: Separate debit / credit columns

    func testSeparateDebitAndCreditColumns() {
        let csv = """
        Date,Description,Debit,Credit
        05/07/2026,COLD STORAGE,42.30,
        06/07/2026,SALARY,,3500.00
        07/07/2026,SHELL PETROL,88.00,
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(out.count, 2, "the credit row is income, not spending")
        XCTAssertEqual(out.map(\.amountCents), [4230, 8800])
        XCTAssertFalse(out.contains { $0.desc.contains("SALARY") })
    }

    /// A single signed column: negatives are credits and must be dropped, matching
    /// how the PDF parsers already behave.
    func testNegativeAmountsAreTreatedAsCredits() {
        let csv = """
        Date,Description,Amount
        05/07/2026,COLD STORAGE,42.30
        06/07/2026,REFUND LAZADA,-19.90
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].amountCents, 4230)
    }

    /// Every imported amount must be a positive charge — the app's convention.
    func testAllImportedAmountsArePositive() {
        let csv = """
        Date,Description,Amount,Balance
        05/07/2026,A,42.30,100.00
        06/07/2026,B,88.00,12.00
        """
        XCTAssertTrue(StatementParser.parseCSV(csv).allSatisfy { $0.amountCents > 0 })
    }

    // MARK: Date ordering

    /// A US file: 07/03/2026 is 3 July. Evidence elsewhere in the file (13/…, 25/…
    /// would be impossible as months) settles the order for the whole file.
    func testMonthFirstDetectedFromEvidence() {
        let csv = """
        Date,Description,Amount
        07/03/2026,STARBUCKS,5.40
        12/25/2026,AMAZON,31.00
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(day(out[0].date).1, 7, "07/03 in a month-first file is July")
        XCTAssertEqual(day(out[0].date).2, 3)
        XCTAssertEqual(day(out[1].date).1, 12)
        XCTAssertEqual(day(out[1].date).2, 25)
    }

    /// A SG/UK file: 25/12 can only be day-first.
    func testDayFirstDetectedFromEvidence() {
        let csv = """
        Date,Description,Amount
        03/07/2026,KOPITIAM,5.40
        25/12/2026,GIFT SHOP,31.00
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(day(out[0].date).1, 7, "03/07 in a day-first file is July")
        XCTAssertEqual(day(out[0].date).2, 3)
        XCTAssertEqual(day(out[1].date).2, 25)
    }

    func testOrderDetectionReportsAmbiguityWhenThereIsNoEvidence() {
        let rows = [["05/07/2026", "A", "1.00"], ["06/08/2026", "B", "2.00"]]
        XCTAssertEqual(StatementParser.detectDayMonthOrder(rows: rows, dateColumn: 0), .ambiguous)
        XCTAssertEqual(StatementParser.detectDayMonthOrder(rows: [["25/12/2026"]], dateColumn: 0), .dayFirst)
        XCTAssertEqual(StatementParser.detectDayMonthOrder(rows: [["12/25/2026"]], dateColumn: 0), .monthFirst)
    }

    // MARK: parseAmount hardening

    func testDatesAndMerchantNamesAreNotAmounts() {
        XCTAssertNil(StatementParser.parseAmount("16/05/2026"), "a date is not an amount")
        XCTAssertNil(StatementParser.parseAmount("2026-07-19"))
        XCTAssertNil(StatementParser.parseAmount("16.05.2026"))
        XCTAssertNil(StatementParser.parseAmount("7-ELEVEN"), "used to parse as -7")
        XCTAssertNil(StatementParser.parseAmount("CRATE & BARREL"))
        XCTAssertNil(StatementParser.parseAmount("Description"))
        XCTAssertNil(StatementParser.parseAmount(""))
    }

    /// The dot-as-separator guard must not reject genuine decimals.
    func testRealAmountsStillParse() {
        XCTAssertEqual(StatementParser.parseAmount("12.5") ?? 0, 12.5, accuracy: 0.001)
        XCTAssertEqual(StatementParser.parseAmount("1,234.56") ?? 0, 1234.56, accuracy: 0.001)
        XCTAssertEqual(StatementParser.parseAmount("$1,234.56") ?? 0, 1234.56, accuracy: 0.001)
        XCTAssertEqual(StatementParser.parseAmount("1234") ?? 0, 1234, accuracy: 0.001)
        XCTAssertEqual(StatementParser.parseAmount("(352.00)") ?? 0, -352.0, accuracy: 0.001)
        XCTAssertEqual(StatementParser.parseAmount("45.00 CR") ?? 0, -45.0, accuracy: 0.001)
        XCTAssertEqual(StatementParser.parseAmount("-12.00") ?? 0, -12.0, accuracy: 0.001)
    }

    // MARK: Header handling

    func testLayoutMapsColumnsByName() {
        let l = StatementParser.csvLayout(header: ["Date", "Description", "Amount", "Balance"])
        XCTAssertEqual(l?.date, 0)
        XCTAssertEqual(l?.desc, 1)
        XCTAssertEqual(l?.amount, 2)
        XCTAssertEqual(l?.balance, 3)
    }

    /// A data row must not be mistaken for a header.
    func testDataRowIsNotTreatedAsAHeader() {
        XCTAssertNil(StatementParser.csvLayout(header: ["05/07/2026", "COLD STORAGE", "42.30"]))
    }

    /// No header at all — fall back to positional parsing rather than importing nothing.
    func testHeaderlessFileStillParses() {
        let csv = """
        05/07/2026,COLD STORAGE,42.30
        06/07/2026,SHELL PETROL,88.00
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.amountCents), [4230, 8800])
    }

    /// Quoted fields containing commas must not split the row.
    func testQuotedDescriptionWithCommaSurvives() {
        let csv = """
        Date,Description,Amount
        05/07/2026,"TOTAL WINE & MORE, ORCHARD",42.30
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].desc, "TOTAL WINE & MORE, ORCHARD")
        XCTAssertEqual(out[0].amountCents, 4230)
    }

    /// A description that happens to look numeric shouldn't win the amount slot.
    func testMerchantWithDigitsDoesNotBecomeTheAmount() {
        let csv = """
        Date,Description,Amount
        05/07/2026,7-ELEVEN BEDOK,4.20
        """
        let out = StatementParser.parseCSV(csv)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].amountCents, 420)
        XCTAssertEqual(out[0].desc, "7-ELEVEN BEDOK")
    }
}
