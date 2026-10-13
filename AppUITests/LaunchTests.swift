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
    }
}
