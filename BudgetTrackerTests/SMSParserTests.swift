import XCTest
@testable import BudgetTracker

/// Parsing bank alert SMS text.
///
/// iOS gives apps no way to read the inbox, so this only ever sees text the user
/// pasted or shared. Two things matter most: real Singapore bank alerts parse, and
/// ordinary messages produce nothing at all — an OTP or a text from a friend must
/// never turn into a transaction.
final class SMSParserTests: XCTestCase {

    private let cal = DateHelpers.calendar

    // MARK: Outgoing

    func testParsesPayNowTransferToAPerson() {
        guard let r = SMSTransactionParser.parse(
            "You have made a PayNow transfer of SGD25.00 to JOHN TAN on 25 Aug 2026.")
        else { return XCTFail("expected a parse") }
        XCTAssertEqual(r.amountCents, 2500)
        XCTAssertFalse(r.isIncoming)
        XCTAssertEqual(r.counterparty, "JOHN TAN")
        XCTAssertEqual(r.suggestedNote, "PayNow to JOHN TAN")
        XCTAssertEqual(cal.dateComponents([.day], from: r.date ?? .now).day, 25)
    }

    func testParsesPayNowToAMerchant() {
        let r = SMSTransactionParser.parse("PayNow: S$52.30 transferred to NTUC FAIRPRICE on 25/08/26")
        XCTAssertEqual(r?.amountCents, 5230)
        XCTAssertEqual(r?.counterparty, "NTUC FAIRPRICE")
    }

    /// "debited from your account ... to MERCHANT" names both. Keying on "from"
    /// would return the user's own account rather than who they paid.
    func testDebitAlertNamesThePayeeNotTheAccount() {
        let r = SMSTransactionParser.parse(
            "SGD 18.50 was debited from your account ending 1234 via PayNow to KOPITIAM PTE LTD.")
        XCTAssertEqual(r?.amountCents, 1850)
        XCTAssertFalse(r?.isIncoming ?? true)
        XCTAssertEqual(r?.counterparty, "KOPITIAM PTE LTD")
    }

    /// A card alert names the merchant with "at", and isn't a PayNow transfer, so
    /// the note is the merchant alone.
    func testParsesCardChargeAlert() {
        let r = SMSTransactionParser.parse(
            "Your card ending 1234 was charged SGD 52.30 at NTUC FAIRPRICE on 25 Aug.")
        XCTAssertEqual(r?.amountCents, 5230)
        XCTAssertEqual(r?.counterparty, "NTUC FAIRPRICE")
        XCTAssertEqual(r?.suggestedNote, "NTUC FAIRPRICE")
    }

    /// A single digit in a merchant name must survive; only long runs are refs.
    func testShortDigitsInMerchantNamesSurvive() {
        let r = SMSTransactionParser.parse("You have made a PayNow payment of S$8.00 to 7-ELEVEN BEDOK.")
        XCTAssertEqual(r?.amountCents, 800)
        XCTAssertEqual(r?.counterparty, "7-ELEVEN BEDOK")
    }

    // MARK: Incoming

    func testParsesReceivedPayNow() {
        guard let r = SMSTransactionParser.parse("You have received SGD30.00 via PayNow from MARY LIM.")
        else { return XCTFail("expected a parse") }
        XCTAssertTrue(r.isIncoming)
        XCTAssertEqual(r.amountCents, 3000)
        XCTAssertEqual(r.suggestedNote, "PayNow from MARY LIM")
    }

    func testParsesCreditedAlertWithThousandsSeparator() {
        let r = SMSTransactionParser.parse(
            "Your account has been credited SGD 1,200.00 via PayNow from ACME PTE LTD.")
        XCTAssertEqual(r?.amountCents, 120_000)
        XCTAssertTrue(r?.isIncoming ?? false)
        XCTAssertEqual(r?.counterparty, "ACME PTE LTD")
    }

    // MARK: Must NOT parse

    /// The important half. Anything without both a money amount and payment
    /// wording has to return nil rather than inventing a transaction.
    func testOrdinaryMessagesAreRejected() {
        XCTAssertNil(SMSTransactionParser.parse("Hi, are we still on for dinner tonight?"))
        XCTAssertNil(SMSTransactionParser.parse("Your OTP is 123456. Do not share it."))
        XCTAssertNil(SMSTransactionParser.parse(""))
        XCTAssertNil(SMSTransactionParser.parse("   "))
        XCTAssertNil(SMSTransactionParser.parse("Your PayNow transfer failed."),
                     "payment wording without an amount is not a transaction")
        XCTAssertNil(SMSTransactionParser.parse("SGD 25.00"),
                     "an amount with no payment wording is not a transaction")
    }

    func testAmountFormats() {
        XCTAssertEqual(SMSTransactionParser.amountCents(in: "paid SGD25.00"), 2500)
        XCTAssertEqual(SMSTransactionParser.amountCents(in: "paid S$ 1,200.50"), 120_050)
        XCTAssertEqual(SMSTransactionParser.amountCents(in: "paid $8"), 800)
        XCTAssertEqual(SMSTransactionParser.amountCents(in: "paid 18.50 SGD"), 1850)
        XCTAssertNil(SMSTransactionParser.amountCents(in: "no money here"))
    }
}
