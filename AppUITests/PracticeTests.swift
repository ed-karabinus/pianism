import XCTest

/// End-to-end tests of the Practice screen (SES-1, SES-2, SES-6).
///
/// Each launch fixes the app's clock (see `App/LaunchOptions.swift`), so times are exact. Time
/// passes between launches, which also proves a session survives the app being killed.
final class PracticeTests: XCTestCase {
    /// 2027-01-01 00:00:00 UTC.
    private let start: TimeInterval = 1_798_761_600

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartPauseResumeStop() throws {
        let app = launch(at: start, reset: true)
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")

        tap(app, "practice.start")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        attachScreenshot(of: app, named: "Practicing")

        tap(app, "practice.pause")
        XCTAssertEqual(text(app, "practice.status"), "Paused")
        attachScreenshot(of: app, named: "Paused")

        tap(app, "practice.resume")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")

        tap(app, "practice.stop")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertTrue(app.buttons["practice.start"].exists)
    }

    /// SES-6: killed while running and while paused, the session comes back with the right time,
    /// and paused time never counts (SES-2).
    @MainActor
    func testSessionSurvivesBeingKilled() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()

        app = launch(at: start + 25 * 60 + 3)
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertEqual(elapsed(app), "25 minutes, 3 seconds")
        attachScreenshot(of: app, named: "Restored after being killed")
        tap(app, "practice.pause")
        app.terminate()

        app = launch(at: start + 40 * 60)
        XCTAssertEqual(text(app, "practice.status"), "Paused")
        XCTAssertEqual(elapsed(app), "25 minutes, 3 seconds")
        tap(app, "practice.resume")
        app.terminate()

        app = launch(at: start + 50 * 60)
        XCTAssertEqual(elapsed(app), "35 minutes, 3 seconds")
        tap(app, "practice.stop")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 35:03")
        attachScreenshot(of: app, named: "Stopped")
    }

    @MainActor
    private func launch(at now: TimeInterval, reset: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PIANISM_NOW"] = String(now)
        if reset {
            app.launchEnvironment["PIANISM_RESET"] = "1"
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["practice.status"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No \(identifier) button")
        button.tap()
    }

    @MainActor
    private func text(_ app: XCUIApplication, _ identifier: String) -> String {
        app.staticTexts[identifier].label
    }

    /// The elapsed time as VoiceOver reads it.
    @MainActor
    private func elapsed(_ app: XCUIApplication) -> String? {
        app.staticTexts["practice.elapsed"].value as? String
    }
}
