import XCTest

/// End-to-end smoke test: the built app launches and shows its first screen.
final class LaunchTests: UITestCase {
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

    /// Fails on purpose, and passes only if the failure kept what `UITestCase` attaches.
    @MainActor
    func testAFailureKeepsTheScreenAndUITree() throws {
        XCUIApplication().launch()

        XCTExpectFailure(
            "Deliberate: checks what UITestCase keeps",
            issueMatcher: { $0.attachments.map(\.name) == ["Screen at failure", "UI tree at failure"] })
        XCTFail("A failing UI test no longer keeps its screen and UI tree: see UITestCase")
    }
}
