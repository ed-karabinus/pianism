import XCTest

/// The App Store screenshots (#56), from sample practice (`Showcase` in the app), each attached to the results under
/// its place in the listing. Skipped unless `make screenshots` asks for them, as they check nothing.
final class ScreenshotTests: UITestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testAppStoreScreenshots() throws {
        let asked = ProcessInfo.processInfo.environment["PIANISM_SCREENSHOTS"] == "1"
        try XCTSkipUnless(asked, "Only for make screenshots")
        let app = XCUIApplication()
        app.launchEnvironment = [
            "PIANISM_RESET": "1", "PIANISM_SKIP_WELCOME": "1", "PIANISM_SHOWCASE": "1",
            // Thursday 12 November 2026, 7:30 pm, in Los Angeles whatever the Mac's time zone, as the status bar says.
            "PIANISM_NOW": "1794540600", "TZ": "America/Los_Angeles",
            "PIANISM_STORE": "free", "PIANISM_PRO": "1", "PIANISM_MIDI_PIANO": "Digital piano",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["practice.stop"].waitForExistence(timeout: 30), "The piano session isn't running")
        attachScreenshot(of: app, named: "2 Practice")
        app.buttons["practice.tags"].tap()
        XCTAssertTrue(app.buttons["tags.done"].waitForExistence(timeout: 5), "The tags didn't open")
        attachScreenshot(of: app, named: "5 Tags")
        app.buttons["tags.done"].tap()

        // A second tap if needed, as on iOS 26 a tap while the tab bar is still moving doesn't switch tabs.
        for _ in 0..<2 where !app.navigationBars["History"].waitForExistence(timeout: 3) {
            app.buttons["History"].firstMatch.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["history.weeks-met"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "1 Week")
        // Today's header dragged to just under the bar: first far enough to shrink the title, then the rest, measured
        // from the bar as it is then.
        let list = app.collectionViews.firstMatch
        drag(list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)), up: 60)
        let today = app.descendants(matching: .any)["history.day"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "Today's sessions aren't on screen")
        let bar = app.navigationBars["History"]
        let top = today.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        drag(top, up: today.frame.minY - bar.frame.maxY - 12)
        XCTAssertLessThan(abs(today.frame.minY - bar.frame.maxY - 12), 20, "Today's header didn't stop under the bar")
        attachScreenshot(of: app, named: "3 History")
        app.buttons["History"].firstMatch.tap()
        app.buttons["history.piece-stats"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["piece-stats.piece"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "4 Pieces")
    }

    /// Scrolls by `points` with no fling: slowly, and held before lifting, so the list stops where the finger does.
    @MainActor
    private func drag(_ start: XCUICoordinate, up points: CGFloat) {
        start.press(
            forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -points)), withVelocity: .slow,
            thenHoldForDuration: 0.5)
    }
}
