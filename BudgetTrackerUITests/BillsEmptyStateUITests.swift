import XCTest

/// Verifies that once every upcoming bill is marked paid, the Home "Upcoming bills"
/// card stays visible and shows the "All bills paid" empty state (rather than the
/// whole card disappearing).
final class BillsEmptyStateUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testAllBillsPaidShowsEmptyState() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Upcoming bills"].waitForExistence(timeout: 15))

        // Open the Bills sheet (the bills section's "See all").
        app.buttons["See all"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Bills"].waitForExistence(timeout: 5), "Bills sheet didn't open")

        // Mark every still-upcoming bill paid (no-op if they're already settled).
        var safety = 0
        while app.buttons["Mark paid"].firstMatch.waitForExistence(timeout: 2), safety < 25 {
            app.buttons["Mark paid"].firstMatch.tap()
            safety += 1
        }

        // Dismiss the sheet by dragging the nav bar down.
        let bar = app.navigationBars["Bills"]
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
        start.press(forDuration: 0.1, thenDragTo: end)

        // Home should still show the card, now with the empty state.
        XCTAssertTrue(app.staticTexts["All bills paid"].waitForExistence(timeout: 5),
                      "Home should show 'All bills paid' after all bills are settled")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "home-all-bills-paid"; shot.lifetime = .keepAlways
        add(shot)
    }
}
