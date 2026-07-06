import XCTest

/// Drives the app (with the DEMO_SEED demo data) to produce App Store marketing
/// assets on a 6.9" device:
///   • `testCaptureScreenshots` saves full-resolution screenshots as attachments.
///   • `testPreviewTour` performs a slow, smooth navigation loop that an external
///     `simctl io recordVideo` captures into an App Preview video.
final class AppStoreAssetsUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DEMO_SEED"] = "1"
        return app
    }

    private func snap(_ name: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let b = app.buttons[label]
        if b.waitForExistence(timeout: 5) { b.tap() }
    }

    /// Tap a segmented-control pill and confirm the switch took by waiting for a
    /// control that only exists once the new segment is showing. Retries because the
    /// custom pill occasionally swallows the first tap right after a tab change.
    @discardableResult
    private func selectSegment(_ app: XCUIApplication, _ label: String, confirms confirm: String) -> Bool {
        let pill = app.buttons[label]
        guard pill.waitForExistence(timeout: 5) else { return false }
        for _ in 0..<4 {
            pill.tap()
            if app.buttons[confirm].waitForExistence(timeout: 3)
                || app.staticTexts[confirm].waitForExistence(timeout: 1) { return true }
        }
        return false
    }

    func testCaptureScreenshots() {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 20), "app never launched")
        Thread.sleep(forTimeInterval: 1.2)
        snap("01-Home")

        tapTab(app, "Cards")
        Thread.sleep(forTimeInterval: 1.0)
        snap("02-Cards")

        // Budget segment → Categories sub-tab (budget-vs-actual bars).
        selectSegment(app, "Budget", confirms: "Categories")
        Thread.sleep(forTimeInterval: 1.2)
        snap("03-Budget")

        // Analytics sub-tab (category donut + weekly bars).
        selectSegment(app, "Analytics", confirms: "By category")
        Thread.sleep(forTimeInterval: 1.2)
        snap("04-Analytics")

        tapTab(app, "Activity")
        Thread.sleep(forTimeInterval: 1.0)
        snap("05-Activity")
    }

    /// A gentle guided tour for the App Preview recording (~26s). Navigation uses
    /// normalized coordinate taps (not accessibility lookups) so every tap lands
    /// deterministically while an external `simctl io recordVideo` captures it.
    func testPreviewTour() {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 20))

        func tap(_ dx: Double, _ dy: Double) {
            app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }
        // Tab bar (bottom) and segment-pill rows, as fractions of the screen.
        let tabY = 0.965
        let tabHome = 0.11, tabActivity = 0.31, tabCards = 0.69, tabSettings = 0.89
        let segRowY = 0.135, subRowY = 0.205
        let segCards = 0.20, segBudget = 0.50
        let subCategories = 0.30, subAnalytics = 0.70

        func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

        pause(2.6)                       // Home hero: available-to-spend + donut
        app.swipeUp(velocity: .slow); pause(2.0)     // reveal bills + recent activity
        app.swipeDown(velocity: .slow); pause(1.4)

        tap(tabCards, tabY); pause(2.6)  // Cards wall
        tap(segBudget, segRowY); pause(0.6)
        tap(subCategories, subRowY); pause(2.6)      // budget-vs-actual bars
        tap(subAnalytics, subRowY); pause(2.8)       // donut + weekly bars

        tap(tabActivity, tabY); pause(2.2)           // transaction list
        app.swipeUp(velocity: .slow); pause(2.0)

        tap(tabSettings, tabY); pause(2.0)           // settings
        tap(tabHome, tabY); pause(2.2)               // back to hero
    }
}
