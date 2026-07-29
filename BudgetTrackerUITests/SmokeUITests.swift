import XCTest

/// Runtime smoke test: launches the app and visits every tab, asserting the app
/// stays in the foreground (i.e. doesn't crash) and capturing a screenshot of each
/// screen as a test attachment for visual review.
final class SmokeUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func testVisitEveryTabWithoutCrashing() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 15), "tab bar never appeared")
        snap(app, "01-Home")

        // The tab bar is Home · Activity · [+] · Cards · Settings. "Budget" is a
        // segment inside Cards, not a tab — testBudgetSegmentInsideCardsTab covers
        // it. Listing it here made this test fail on a control that never existed.
        let tabs = [("Activity", "02-Activity"),
                    ("Cards",    "03-Cards"),
                    ("Settings", "04-Settings"),
                    ("Home",     "05-Home-again")]

        for (label, name) in tabs {
            let btn = app.buttons[label]
            XCTAssertTrue(btn.waitForExistence(timeout: 5), "\(label) tab button missing")
            btn.tap()
            // Give SwiftUI a beat to render, then confirm we're still alive.
            Thread.sleep(forTimeInterval: 0.7)
            XCTAssertEqual(app.state, .runningForeground, "app left foreground after tapping \(label)")
            snap(app, name)
        }
    }

    /// The Budget screen lives as a segment inside the Cards tab, with the month
    /// stepper aligned with the "Accounts" title on the trailing edge.
    func testBudgetSegmentInsideCardsTab() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Cards"].waitForExistence(timeout: 15))
        app.buttons["Cards"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        snap(app, "04-Cards")

        let budgetSegment = app.buttons["Budget"]
        XCTAssertTrue(budgetSegment.waitForExistence(timeout: 5), "Budget segment missing in Cards tab")
        budgetSegment.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(app.state, .runningForeground, "app crashed showing Budget segment")
        // The Budget content's own sub-tabs should be visible.
        XCTAssertTrue(app.buttons["Categories"].waitForExistence(timeout: 5), "Budget content didn't render")
        snap(app, "07-Cards-Budget")
    }
}
