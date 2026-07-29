import XCTest
@testable import BudgetTracker

// TEMPORARY diagnostic — prints what each parser produces on the local UOB fixture.
// Delete after. Prints only merchant+amount (no name/address).
final class UOBDiagCheck: XCTestCase {
    func testDumpUOB() throws {
        let url = URL(fileURLWithPath: "/Users/jeremy/projects/finance_budget_tracker/Fixtures/uob_statement.pdf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "no fixture")

        func dump(_ name: String, _ lines: [StatementParser.ParsedLine]) {
            print("=== \(name): \(lines.count) rows ===")
            for l in lines {
                print(String(format: "  %@ | %8d | %@",
                             DateHelpers.mediumDate(l.date), l.amountCents, l.desc))
            }
        }
        dump("LINE", LineStatementParser.parse(url: url))
        dump("BLOCK", LineStatementParser.parseBlock(url: url))
        dump("COORD", CoordinateStatementParser.parse(url: url))
        dump("FINAL (parse)", try StatementParser.parse(url: url))
    }
}
