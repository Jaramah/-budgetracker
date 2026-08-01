import XCTest
@testable import BudgetTracker

/// Credit-card payment due dates.
///
/// `paymentDueDay` is a day-of-month, which is ambiguous on its own. The rule the
/// model implements is "the first occurrence of the due day strictly after the
/// statement date", which resolves both shapes a card can take:
///
///   • due day <= statement day  → due the FOLLOWING month (UOB: cut 19th, due 7th)
///   • due day  > statement day  → due the SAME month       (cut 5th, due 25th)
///
/// The regression these guard is the first case being resolved into the statement's
/// own month, which puts the due date in the past and makes a paid card look overdue.
final class DueDateTests: XCTestCase {

    private let cal = DateHelpers.calendar

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    private func card(statementDay: Int, dueDay: Int) -> CreditCardAccount {
        CreditCardAccount(bank: .uob, nickname: "Test",
                          statementDay: statementDay, paymentDueDay: dueDay)
    }

    private func assertSameDay(_ a: Date?, _ b: Date, _ msg: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("expected a due date — \(msg)", file: file, line: line) }
        XCTAssertTrue(cal.isDate(a, inSameDayAs: b),
                      "\(msg): got \(DateHelpers.mediumDate(a)), expected \(DateHelpers.mediumDate(b))",
                      file: file, line: line)
    }

    // MARK: The reported bug

    /// The real UOB statement: issued 19 Jul 2026, due 7 Aug 2026.
    func testDueDayBeforeStatementDayRollsToNextMonth() {
        let c = card(statementDay: 19, dueDay: 7)
        assertSameDay(c.dueDate(forStatementDate: date(2026, 7, 19)),
                      date(2026, 8, 7),
                      "statement 19 Jul with due day 7 must be due 7 Aug, not 7 Jul")
    }

    /// December must roll into January of the following year.
    func testRollingAcrossTheYearBoundary() {
        let c = card(statementDay: 19, dueDay: 7)
        assertSameDay(c.dueDate(forStatementDate: date(2026, 12, 19)),
                      date(2027, 1, 7),
                      "December statement must be due in January of the next year")
    }

    /// A due day equal to the statement day still belongs to the next month — a
    /// statement issued on the 15th is not also due on the 15th.
    func testDueDayEqualToStatementDayRollsForward() {
        let c = card(statementDay: 15, dueDay: 15)
        assertSameDay(c.dueDate(forStatementDate: date(2026, 7, 15)),
                      date(2026, 8, 15),
                      "same day must roll forward, never resolve to the statement date itself")
    }

    // MARK: The other shape — must not over-correct

    /// Blindly adding a month would break this: due day after the statement day
    /// falls in the same month.
    func testDueDayAfterStatementDayStaysInSameMonth() {
        let c = card(statementDay: 5, dueDay: 25)
        assertSameDay(c.dueDate(forStatementDate: date(2026, 7, 5)),
                      date(2026, 7, 25),
                      "statement 5 Jul with due day 25 is due 25 Jul, same month")
    }

    // MARK: Calendar edge cases

    /// February is shorter than the highest permitted due day, so the date must
    /// clamp to the last day of the month rather than silently vanish.
    func testDueDayClampsToShortMonth() {
        let c = card(statementDay: 10, dueDay: 28)
        assertSameDay(c.dueDate(forStatementDate: date(2027, 2, 10)),
                      date(2027, 2, 28),
                      "28 Feb exists in a non-leap year and must be used as-is")
    }

    // MARK: Days 29–31
    //
    // The pickers used to stop at 28, so a card genuinely due on the 30th or 31st
    // could not be entered at all. Allowing them requires every derived date to be
    // clamped to the month's real length rather than the day being dropped.

    func testDueDaysUpToThirtyOneAreAccepted() {
        for d in 1...31 {
            XCTAssertTrue(card(statementDay: 1, dueDay: d).hasDueDay, "due day \(d) rejected")
        }
        XCTAssertFalse(card(statementDay: 1, dueDay: 0).hasDueDay)
        XCTAssertFalse(card(statementDay: 1, dueDay: 32).hasDueDay)
    }

    /// A 31st due day in a 30-day month lands on the 30th, not the 1st of the next.
    func testDayThirtyOneClampsToThirtyDayMonth() {
        let c = card(statementDay: 5, dueDay: 31)
        assertSameDay(c.dueDate(forStatementDate: date(2026, 4, 5)),
                      date(2026, 4, 30),
                      "31st due day in April must clamp to the 30th")
    }

    func testDayThirtyOneClampsInFebruary() {
        let c = card(statementDay: 5, dueDay: 31)
        assertSameDay(c.dueDate(forStatementDate: date(2027, 2, 5)),
                      date(2027, 2, 28),
                      "non-leap February clamps to the 28th")
        assertSameDay(c.dueDate(forStatementDate: date(2028, 2, 5)),
                      date(2028, 2, 29),
                      "leap February clamps to the 29th, not the 28th")
    }

    /// The screenshot case: a DBS card due on the 30th.
    func testDayThirtyIsHonouredInLongMonths() {
        let c = card(statementDay: 5, dueDay: 30)
        assertSameDay(c.dueDate(forStatementDate: date(2026, 7, 5)),
                      date(2026, 7, 30),
                      "July has a 30th — no clamping should occur")
    }

    /// Clamping must not make the due date collapse onto or before the statement
    /// date, which would resolve it into the wrong cycle.
    func testClampedDueDateStillFollowsTheStatement() {
        let c = card(statementDay: 28, dueDay: 31)
        guard let due = c.dueDate(forStatementDate: date(2027, 2, 28)) else {
            return XCTFail("expected a due date")
        }
        XCTAssertGreaterThan(due, date(2027, 2, 28),
                             "clamping to 28 Feb must roll to March, not equal the statement date")
        assertSameDay(due, date(2027, 3, 31), "next month's 31st")
    }

    /// Every day/month combination must produce a date, with no gaps.
    func testEveryDueDayResolvesInEveryMonth() {
        for dueDay in 28...31 {
            let c = card(statementDay: 1, dueDay: dueDay)
            for month in 1...12 {
                XCTAssertNotNil(c.dueDate(forStatementDate: date(2027, month, 1)),
                                "no due date for day \(dueDay) in month \(month)")
            }
        }
    }

    func testNoDueDayConfiguredReturnsNil() {
        let c = card(statementDay: 19, dueDay: 0)
        XCTAssertNil(c.dueDate(forStatementDate: date(2026, 7, 19)))
        XCTAssertNil(c.nextDueDate(asOf: date(2026, 7, 19)))
        XCTAssertNil(c.daysUntilDue(asOf: date(2026, 7, 19)))
    }

    // MARK: nextDueDate — what the card list shows

    /// Before the due day has passed this month, the next due date is this month's.
    func testNextDueDateBeforeTheDayIsThisMonth() {
        let c = card(statementDay: 19, dueDay: 7)
        assertSameDay(c.nextDueDate(asOf: date(2026, 8, 3)),
                      date(2026, 8, 7),
                      "on 3 Aug the next due date is 7 Aug")
    }

    /// After it has passed, it must move on rather than showing a date in the past.
    func testNextDueDateAfterTheDayIsNextMonth() {
        let c = card(statementDay: 19, dueDay: 7)
        assertSameDay(c.nextDueDate(asOf: date(2026, 8, 9)),
                      date(2026, 9, 7),
                      "on 9 Aug the next due date is 7 Sep, never 7 Aug")
    }

    /// On the day itself it counts as still due — the payment hasn't been missed.
    func testNextDueDateOnTheDayIsToday() {
        let c = card(statementDay: 19, dueDay: 7)
        assertSameDay(c.nextDueDate(asOf: date(2026, 8, 7)),
                      date(2026, 8, 7),
                      "the due date is still today on the due day")
        XCTAssertEqual(c.daysUntilDue(asOf: date(2026, 8, 7)), 0)
    }

    func testDaysUntilDueCountsForward() {
        let c = card(statementDay: 19, dueDay: 7)
        XCTAssertEqual(c.daysUntilDue(asOf: date(2026, 8, 1)), 6)
        XCTAssertEqual(c.daysUntilDue(asOf: date(2026, 8, 6)), 1)
    }

    /// `nextDueDate` never looks backwards, so this can't go negative.
    func testDaysUntilDueIsNeverNegative() {
        let c = card(statementDay: 19, dueDay: 7)
        for day in 1...28 {
            let d = c.daysUntilDue(asOf: date(2026, 8, day))
            XCTAssertNotNil(d)
            XCTAssertGreaterThanOrEqual(d ?? -1, 0, "negative countdown on \(day) Aug")
        }
    }
}
