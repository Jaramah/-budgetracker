import XCTest
@testable import BudgetTracker

/// PayNow / FAST transfers on bank statements.
///
/// Outgoing transfers already imported — nothing filtered them. Incoming ones did
/// not: every credit was dropped, which is correct on a *card* statement (a credit
/// there is the user paying their bill) but throws away real income on a bank
/// statement. These tests pin the narrow exception, and — just as importantly —
/// that card bill payments are still excluded.
final class PayNowTests: XCTestCase {

    // MARK: Recognition

    func testRecognisesOutgoingTransfer() {
        guard let p = StatementParser.payNow(in: "PayNow Transfer To JOHN TAN") else {
            return XCTFail("expected a PayNow match")
        }
        XCTAssertFalse(p.isIncoming)
        XCTAssertEqual(p.counterparty, "JOHN TAN")
        XCTAssertEqual(p.cleanedDescription, "PayNow to JOHN TAN")
    }

    func testRecognisesIncomingTransfer() {
        guard let p = StatementParser.payNow(in: "PAYNOW TRANSFER FROM MARY LIM") else {
            return XCTFail("expected a PayNow match")
        }
        XCTAssertTrue(p.isIncoming)
        XCTAssertEqual(p.counterparty, "MARY LIM")
        XCTAssertEqual(p.cleanedDescription, "PayNow from MARY LIM")
    }

    /// Reference numbers and rail names must not end up inside a person's name.
    func testCounterpartyStripsReferenceNoise() {
        XCTAssertEqual(
            StatementParser.payNow(in: "INCOMING PAYNOW FROM ALICE TAN REF 123456789")?.counterparty,
            "ALICE TAN")
    }

    /// A PayNow QR payment at a shop names the merchant but no counterparty. The
    /// merchant is the useful half of the row, so the description must survive.
    func testQRPaymentKeepsTheMerchantName() {
        let raw = "PAYNOW-QR PAYMENT NTUC FAIRPRICE"
        guard let p = StatementParser.payNow(in: raw) else { return XCTFail("expected a match") }
        XCTAssertFalse(p.isIncoming)
        XCTAssertEqual(p.cleanedDescription, raw, "must not be replaced with a generic label")
    }

    /// Ordinary card charges are not transfers and must be left alone.
    func testNonTransfersAreNotMatched() {
        XCTAssertNil(StatementParser.payNow(in: "NTUC FAIRPRICE"))
        XCTAssertNil(StatementParser.payNow(in: "Total Wine & More"))
        XCTAssertNil(StatementParser.payNow(in: "PAYMT THRU E-BANK/HOMEB/CYBERB (EP50)"))
    }

    // MARK: Parsing a statement

    func testOutgoingTransferImportsAsSpending() {
        let page = """
        16 May PayNow Transfer To JOHN TAN 50.00
        17 May NTUC FAIRPRICE 52.30
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertEqual(out.count, 2)
        guard let t = out.first(where: { $0.desc.contains("JOHN TAN") }) else {
            return XCTFail("outgoing transfer missing")
        }
        XCTAssertEqual(t.amountCents, 5000, "money sent is spending")
        XCTAssertFalse(t.isTransferIn)
    }

    func testIncomingTransferSurvivesAsIncome() {
        let page = """
        16 May PAYNOW TRANSFER FROM MARY LIM 30.00 CR
        17 May NTUC FAIRPRICE 52.30
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        guard let t = out.first(where: { $0.isTransferIn }) else {
            return XCTFail("incoming transfer was dropped")
        }
        XCTAssertEqual(t.amountCents, -3000, "received money keeps the credit sign")
        XCTAssertEqual(t.desc, "PayNow from MARY LIM")
    }

    // MARK: Regression — credits that must STILL be dropped

    /// The bill payment from the real UOB statement. A credit, PayNow or not, that
    /// settles a card must never be imported as income.
    func testCardBillPaymentIsStillExcluded() {
        let page = """
        27 Jun PAYMT THRU E-BANK/HOMEB/CYBERB (EP50) 2,040.69 CR
        17 May NTUC FAIRPRICE 52.30
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertFalse(out.contains { $0.desc.uppercased().contains("PAYMT") })
        XCTAssertTrue(out.allSatisfy { $0.amountCents > 0 })
    }

    /// "PAYNOW PAYMENT" as a credit is ambiguous — on a card statement it is the
    /// bill being settled by PayNow. Without an explicit incoming marker it stays out.
    func testAmbiguousPayNowCreditIsStillExcluded() {
        let page = """
        27 Jun PAYNOW PAYMENT 500.00 CR
        17 May NTUC FAIRPRICE 52.30
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertFalse(out.contains { $0.isTransferIn },
                       "an unqualified PayNow credit must not be treated as income")
        XCTAssertTrue(out.allSatisfy { $0.amountCents > 0 })
    }

    /// The other SG credit notations carry no transfer wording and are unaffected.
    func testOtherCreditNotationsUnaffected() {
        let page = """
        16 May NTUC FAIRPRICE 52.30
        18 May PAYMENT THANK YOU 1,884.04 CR
        19 May REFUND STORE (352.00)
        20 May REBATE 30.82CR
        21 May CASHBACK +1,178.22
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        XCTAssertEqual(out.count, 1, "only the genuine debit")
        XCTAssertTrue(out.allSatisfy { $0.amountCents > 0 })
    }

    /// Received money must not inflate the charge total the statement is
    /// reconciled against.
    func testReceivedTransfersAreNotCountedAsCharges() {
        let page = """
        16 May PAYNOW TRANSFER FROM MARY LIM 30.00 CR
        17 May NTUC FAIRPRICE 52.30
        """
        let out = LineStatementParser.parse(pageTexts: [page])
        let charges = out.filter { $0.amountCents > 0 }.reduce(0) { $0 + $1.amountCents }
        XCTAssertEqual(charges, 5230, "only the debit counts toward spending")
    }
}
