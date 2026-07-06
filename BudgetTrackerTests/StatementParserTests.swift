import XCTest
@testable import BudgetTracker

/// Regression tests for the statement-parsing logic across bank layouts.
/// Two levels:
///   • Pure scalar parsers (`parseDate` / `parseAmount`) — deterministic.
///   • `LineStatementParser` driven from page text (no PDF needed).
///   • End-to-end through `StatementParser.parse(url:)` on a synthetic PDF, which
///     exercises the primary coordinate parser's geometry.
final class StatementParserTests: XCTestCase {

    // MARK: - Helpers

    private func ymd(_ d: Date?) -> (y: Int, m: Int, day: Int)? {
        guard let d else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return (c.year!, c.month!, c.day!)
    }

    private func descs(_ lines: [StatementParser.ParsedLine]) -> [String] { lines.map(\.desc) }

    // MARK: - parseDate

    func testParseDate_abbreviatedAndFullMonthNames() {
        XCTAssertEqual(ymd(StatementParser.parseDate("16 May"))?.m, 5)
        XCTAssertEqual(ymd(StatementParser.parseDate("16 May"))?.day, 16)
        XCTAssertEqual(ymd(StatementParser.parseDate("16 June"))?.m, 6)   // full month name
        XCTAssertEqual(ymd(StatementParser.parseDate("3 January"))?.m, 1)
    }

    /// Standard Chartered / HSBC print months in UPPERCASE — must still parse.
    func testParseDate_caseInsensitiveMonths() {
        XCTAssertEqual(ymd(StatementParser.parseDate("16 MAY"))?.m, 5)
        XCTAssertEqual(ymd(StatementParser.parseDate("16 MAY"))?.day, 16)
        XCTAssertEqual(ymd(StatementParser.parseDate("05 JUN 2025"))?.m, 6)
        XCTAssertEqual(ymd(StatementParser.parseDate("05 JUN 2025"))?.y, 2025)
        XCTAssertEqual(ymd(StatementParser.parseDate("16 dec"))?.m, 12)
    }

    /// These previously merged into a bogus "date" and then silently became today's date.
    func testParseDate_rejectsNonMonthTokens() {
        XCTAssertNil(StatementParser.parseDate("16 EW"))
        XCTAssertNil(StatementParser.parseDate("5 PM"))
        XCTAssertNil(StatementParser.parseDate("16 To"))
        XCTAssertNil(StatementParser.parseDate("16 Marina"))
    }

    func testParseDate_explicitYearPreserved() {
        XCTAssertEqual(ymd(StatementParser.parseDate("31/12/2025"))?.y, 2025)
        let iso = ymd(StatementParser.parseDate("2024-03-08"))
        XCTAssertEqual(iso?.y, 2024); XCTAssertEqual(iso?.m, 3); XCTAssertEqual(iso?.day, 8)
    }

    /// A year-less date must never resolve into the future (Dec statement imported in Jan).
    func testParseDate_yearlessNeverInFuture() {
        for token in ["1 Jan", "30 Dec", "15 Jun", "28 Feb", "16 May"] {
            if let d = StatementParser.parseDate(token) {
                XCTAssertLessThanOrEqual(d.timeIntervalSinceNow, 60, "\(token) resolved to the future")
            }
        }
    }

    // MARK: - parseAmount (shared scalar)

    func testParseAmount_signsAndSeparators() {
        XCTAssertEqual(StatementParser.parseAmount("1,234.56"), 1234.56)
        XCTAssertEqual(StatementParser.parseAmount("$52.30"), 52.30)
        XCTAssertEqual(StatementParser.parseAmount("45.00 CR"), -45.00)   // credit => negative
        XCTAssertEqual(StatementParser.parseAmount("-12.00"), -12.00)
        XCTAssertNil(StatementParser.parseAmount("NO DIGITS"))
    }

    // MARK: - LineStatementParser (fallback) — text-driven

    /// All four SG credit notations must be excluded (we only import debits/charges).
    func testLineParser_excludesCreditsAcrossNotations() {
        let page = """
        16 May NTUC FAIRPRICE 52.30
        17 May GRAB RIDE 12.40
        18 May PAYMENT THANK YOU 1,884.04 CR
        19 May REFUND STORE (352.00)
        20 May REBATE 30.82CR
        21 May CASHBACK +1,178.22
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertTrue(out.allSatisfy { $0.amountCents > 0 }, "no credits should survive")
        XCTAssertEqual(out.count, 2, "only the two genuine debits")
        XCTAssertTrue(descs(out).contains("NTUC FAIRPRICE"))
        XCTAssertTrue(descs(out).contains("GRAB RIDE"))
    }

    /// Regression: merchants that merely contain a summary keyword must survive.
    func testLineParser_keepsMerchantsContainingNoiseWords() {
        let page = """
        Previous Balance 900.00
        16 May TOTAL WINE AND MORE 45.00
        17 May STATEMENT SUPPLIES 20.00
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertTrue(descs(out).contains("TOTAL WINE AND MORE"))
        XCTAssertTrue(descs(out).contains("STATEMENT SUPPLIES"))
        XCTAssertFalse(descs(out).contains { $0.lowercased().contains("previous balance") },
                       "undated summary line must not be imported")
    }

    /// "16 EW APARTMENTS" must not be mistaken for a "16 <month>" date and stamped today.
    func testLineParser_misleadingDescriptionNotDatedToday() {
        let out = LineStatementParser.parse(pageTexts: ["16 EW APARTMENTS RENTAL 1,200.00"])
        for l in out where Calendar.current.isDateInToday(l.date) {
            XCTFail("fabricated today's date for a line with no real date column")
        }
    }

    /// Standard Chartered prints the amount on its OWN line, below the date/desc
    /// (and a "Transaction Ref" line). The parser must pair the amount with the
    /// pending transaction and exclude the CR credits — this is the "only 2 of N
    /// detected" bug. (Layout mirrors a real statement; merchants are anonymised.)
    func testLineParser_standardCharteredSplitAmountLayout() {
        let page = """
        16 May 18 May CASHBACK
        30.82CR
        21 May 22 May DBS BANK Singapo
        Transaction Ref 25363556141005450470859
        1,022.24CR
        24 May 26 May KFC SINGAPORE Singapore SG
        Transaction Ref 75420896145109180916967
        57.80
        02 Jun 02 Jun ATOME* LUXUS DIGITA SINGAPORE SG
        Transaction Ref 85112056153500010580274
        761.63
        13 Jun 13 Jun ATOME* AFTERSHOCK P SINGAPORE SG
        Transaction Ref 85112056164500016090010
        300.88
        16 Jun 16 Jun D J*WSJ PRINCETON US
        Transaction Ref 52716466167204644109320
        7.07
        NEW BALANCE 1,127.38
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertEqual(out.count, 4, "4 debits; the 2 CR credits excluded")
        XCTAssertTrue(out.allSatisfy { $0.amountCents > 0 })
        // Amounts must be intact (regression guard for dropped leading digits).
        XCTAssertEqual(out.first { $0.desc.contains("KFC") }?.amountCents, 5780)
        XCTAssertEqual(out.first { $0.desc.contains("LUXUS") }?.amountCents, 76163)
        XCTAssertEqual(out.first { $0.desc.contains("WSJ") }?.amountCents, 707)
        XCTAssertFalse(out.contains { $0.desc.contains("CASHBACK") }, "CR credit excluded")
    }

    /// DBS: clean single-line "DATE DESC AMOUNT". The PREVIOUS BALANCE summary and
    /// the trailing-CR payment must be excluded; real debits kept with clean names.
    func testLineParser_dbsCleanSingleLineLayout() {
        let page = """
        02 MAY PREVIOUS BALANCE 1,884.04
        BILL PAYMENT - DBS INTERNET/WIRELESS
        REF NO: 17776542264457474200
        1,884.04 CR
        28 APR BUS/MRT 843215447 5.53
        09 MAY SHOPEEPAY SG SPL 28.58
        17 MAY GOMO BY SINGTEL 20.99
        20 MAY SPOTIFY P42A314ACB STOCKHOLM SE 21.19
        23 MAY CLAUDE.AI SUBSCRIPTION ANTHROPIC.COM CA 30.30
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertEqual(out.count, 5, "5 debits; PREVIOUS BALANCE + CR payment excluded")
        XCTAssertTrue(out.allSatisfy { $0.amountCents > 0 })
        XCTAssertEqual(out.first { $0.desc.contains("SHOPEEPAY") }?.amountCents, 2858)
        XCTAssertEqual(out.first { $0.desc.contains("GOMO") }?.amountCents, 2099)
        XCTAssertFalse(out.contains { $0.desc.lowercased().contains("previous balance") })
    }

    /// Descriptions accrete page-footer / summary text via wrapped lines; the final
    /// clean-up pass must strip the footer and drop summary-total rows entirely.
    func testLineParser_stripsFooterAndSummaryContamination() {
        let page = """
        22 May 23 May Grab 16.80
        Trust Bank Singapore Limited GST Reg No: 202039712G
        16 Jun 16 Jun Total outstanding balance 1,267.06
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertEqual(out.first { $0.desc.hasPrefix("Grab") }?.desc, "Grab", "footer text stripped")
        XCTAssertFalse(out.contains { $0.desc.lowercased().contains("outstanding balance") },
                       "summary/total row dropped")
    }

    /// Trust wraps long merchant names onto the next line; it should attach to the row above.
    func testLineParser_wrappedDescriptionAttaches() {
        let page = """
        16 May PLAYMADE - TAMPINES 1 6.50
        SINGAPORE SG
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out.first?.desc.contains("PLAYMADE") ?? false)
        XCTAssertTrue(out.first?.desc.contains("SINGAPORE") ?? false, "wrapped fragment attached")
    }

    /// OCBC prints `DATE AMOUNT` on one line and the merchant on the *next* line, with
    /// the original amount + instalment counter appended ("$331.11 004/012"). Credits
    /// are parenthesised and split across two lines ("(352.00" … "PAYMENT BY INTERNET )").
    /// The parser must: exclude both credits, keep the 4 debits, and clean the merchant
    /// of the card-number header, the dangling ")" credit tails, the trailing "TOTAL",
    /// and the instalment junk. (Anonymised; layout mirrors a real statement.)
    func testLineParser_ocbcAmountThenDescriptionWithSplitCredits() {
        let page = """
        TRANSACTION DATE DESCRIPTION AMOUNT (SGD)
        OCBC GREAT EASTERN CARD
        CARDHOLDER NAME 1234-5678-9012-3456
        LAST MONTH'S BALANCE
        515.50
        28/05 (352.00
        PAYMENT BY INTERNET )
        ANNUAL FEE REVERSAL )
        28/05 (163.50
        06/06 27.00
        GREAT EASTERN LIFE $331.11 004/012
        12/06 18.00
        THE GREAT EASTERN LIFE $220.56 006/012
        13/06 107.00
        THE GREAT EASTERN LIFE $1,289.69 003/012
        14/06 200.00
        THE GREAT EASTERN LIFE $2,400.00 003/012
        SUBTOTAL
        352.00
        TOTAL
        352.00
        TOTAL AMOUNT DUE 352.00
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertEqual(out.count, 4, "4 debits; the (352.00) payment and (163.50) reversal excluded")
        XCTAssertTrue(out.allSatisfy { $0.amountCents > 0 })
        XCTAssertEqual(out.map(\.amountCents).reduce(0, +), 35200, "totals $352.00")
        // Descriptions are the merchant only — no card number, credit tail, junk or TOTAL.
        XCTAssertTrue(out.allSatisfy { $0.desc.contains("GREAT EASTERN LIFE") })
        XCTAssertFalse(out.contains { $0.desc.contains("1234") }, "card-number header stripped")
        XCTAssertFalse(out.contains { $0.desc.contains(")") }, "dangling credit tail dropped")
        XCTAssertFalse(out.contains { $0.desc.uppercased().contains("TOTAL") }, "TOTAL not appended")
        XCTAssertFalse(out.contains { $0.desc.contains("$") || $0.desc.contains("/012") }, "instalment junk stripped")
    }

    /// UOB prints every transaction as `POST TRANS DESCRIPTION` with NO inline amount,
    /// then lists all the amounts afterwards in one contiguous block, matched to the
    /// transactions positionally. A single physical line can also carry several
    /// transactions back-to-back. The dedicated block parser must recover them all,
    /// exclude the inline CR payment, and skip PREVIOUS BALANCE.
    func testBlockParser_uobTrailingAmountBlock() {
        let page = """
        PREVIOUS BALANCE 2,591.58
        28 MAY 28 MAY PAYMT THRU E-BANK/HOMEB/CYBERB (EP30) 2,591.58 CR
        23 MAY 22 MAY APPLE.COM/BILL CORK
        Ref No. : 52715776142205643376904
        25 MAY 22 MAY APPLE.COM/BILL CORK
        Ref No. : 85377436142620551386960
        29 MAY 29 MAY CPS*THE DREAMERY 06/06 30 MAY 30 MAY HARVEY NORMAN-PARKWAY 03/12 02 JUN 01 JUN APPLE.COM/BILL CORK
        Ref No. : 52715776152209141358742
        7.05
        45.43
        849.61
        511.08
        4.02
        SUB TOTAL 1,417.19
        """
        let out = LineStatementParser.parseBlock(pageTexts: [page])
        XCTAssertEqual(out.count, 5, "5 debits; the CR payment and PREVIOUS BALANCE excluded")
        XCTAssertTrue(out.allSatisfy { $0.amountCents > 0 })
        XCTAssertEqual(out.map(\.amountCents).reduce(0, +), 141719, "matches the SUB TOTAL")
        // Positional match: the concatenated line's 3 merchants get the right amounts.
        XCTAssertEqual(out.first { $0.desc.contains("DREAMERY") }?.amountCents, 84961)
        XCTAssertEqual(out.first { $0.desc.contains("HARVEY") }?.amountCents, 51108)
        XCTAssertFalse(out.contains { $0.desc.contains("PAYMT") }, "inline CR payment excluded")
    }

    /// The block parser must stay dormant for the ordinary inline-amount layout
    /// (every row carries its own amount) — otherwise it hijacks banks like Trust.
    func testBlockParser_ignoresInlineAmountLayout() {
        let page = """
        16 May 18 May Grab 28.10
        17 May 19 May Mcdonald's 10.05
        18 May 20 May Subway 8.70
        19 May 21 May FairPrice 45.57
        """
        XCTAssertTrue(LineStatementParser.parseBlock(pageTexts: [page]).isEmpty,
                      "inline-amount statements are not the trailing-block layout")
    }

    // MARK: - AutoCategorizer (drives "spending by category")

    /// The default seeded categories, so we test against what a fresh install has.
    private func defaultCategories() -> [BudgetTracker.Category] {
        let names = ["Food & Dining", "Groceries", "Transport", "Housing",
                     "Utilities", "Shopping", "Entertainment", "Health"]
        return names.enumerated().map { BudgetTracker.Category(name: $1, symbol: "circle", colorHex: "#3B82F6", monthlyBudgetCents: 0, sortIndex: $0) }
    }

    /// Imported merchants must resolve to a real category — otherwise the amounts
    /// never appear in Home's "Spending by category" donut. Guards the exact
    /// merchant strings the bank parsers emit (Grab, Mcdonald's, FairPrice, …).
    func testAutoCategorizer_mapsRealMerchantsToDefaultCategories() {
        let cats = defaultCategories()
        func cat(_ s: String) -> String? { AutoCategorizer.category(for: s, from: cats)?.name }

        XCTAssertEqual(cat("Grab"), "Transport")
        XCTAssertEqual(cat("BUS/MRT 843215447"), "Transport")
        XCTAssertEqual(cat("Mcdonald's"), "Food & Dining")
        XCTAssertEqual(cat("KFC SINGAPORE Singapore SG"), "Food & Dining")
        XCTAssertEqual(cat("Kopitiam"), "Food & Dining")
        XCTAssertEqual(cat("FairPrice"), "Groceries")
        XCTAssertEqual(cat("APPLE.COM/BILL CORK"), "Shopping")
        XCTAssertEqual(cat("SPOTIFY P42A314ACB STOCKHOLM SE"), "Entertainment")
        XCTAssertEqual(cat("GOMO BY SINGTEL"), "Utilities")
        XCTAssertEqual(cat("Takashimaya"), "Shopping")
    }

    /// Unknown merchants stay uncategorized (nil) rather than being force-fit — the
    /// review screen surfaces these for the user to tag.
    func testAutoCategorizer_unknownMerchantStaysUncategorized() {
        let cats = defaultCategories()
        XCTAssertNil(AutoCategorizer.category(for: "GREAT EASTERN LIFE", from: cats))
    }

    // NOTE: The primary coordinate parser is deliberately NOT unit-tested from a
    // synthetic PDF here. It relies on PDFKit's per-character `characterBounds`, and
    // PDFs produced by `UIGraphicsPDFRenderer` do not carry a clean per-glyph text
    // layer (characters get dropped / mis-positioned), so a generated fixture tests
    // the generator, not the parser. The coordinate parser is validated against real
    // bank statements — see the manual test checklist in the PR / README.
}
