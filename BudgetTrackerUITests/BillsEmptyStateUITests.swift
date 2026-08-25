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

        // Open the Bills sheet. Match the identifier, not the label: Home renders
        // three "See all" buttons (categories, bills, activity) and firstMatch
        // picked the categories one, which switches tab instead of opening a sheet.
        let seeAllBills = app.buttons["seeAll.Upcoming bills"]
        XCTAssertTrue(seeAllBills.waitForExistence(timeout: 5), "bills See all missing")
        // Existing is not the same as tappable. Home scrolls, and the bills section
        // sits low enough that the button lands under the tab bar and the ad banner
        // — present in the hierarchy, but not hittable. Scroll it clear first.
        var scrolls = 0
        while !seeAllBills.isHittable && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(seeAllBills.isHittable, "bills See all never scrolled clear of the tab bar")
        seeAllBills.tap()
        // A sheet presentation on a loaded CI runner can take well over five
        // seconds. This assertion has timed out intermittently while the tap
        // itself was fine, so wait longer rather than treating slowness as a bug.
        XCTAssertTrue(app.navigationBars["Bills"].waitForExistence(timeout: 15), "Bills sheet didn't open")

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
