import XCTest

/// End-to-end smoke test: the built app launches and shows its first screen.
final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToRootScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["root"].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "Root screen")
    }
}

extension XCTestCase {
    /// Keeps a screenshot in the test results as visual evidence for PR review.
    /// `make evidence` exports these from the last run.
    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
