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

    /// Fails on purpose, so that `make test-app` can check what a failure keeps.
    @MainActor
    func testAFailureKeepsTheScreenAndUITree() throws {
        XCUIApplication().launch()

        XCTExpectFailure("Deliberate: scripts/check-failure-diagnostics.sh looks for what this keeps")
        XCTFail("Deliberate failure")
    }
}

/// A UI test that keeps the screen and the app's UI tree as they were when it failed, so a failure
/// on CI can be diagnosed from its results without rerunning it.
class UITestCase: XCTestCase {
    private var isRecordingDiagnostics = false

    override func record(_ issue: XCTIssue) {
        var issue = issue
        // UI tests fail on the main thread. Skipping the diagnostics elsewhere beats trapping, and
        // the flag stops a failure while taking them from recursing.
        if Thread.isMainThread, !isRecordingDiagnostics {
            isRecordingDiagnostics = true
            let (screen, tree) = MainActor.assumeIsolated { Self.snapshot() }
            let screenshot = XCTAttachment(data: screen, uniformTypeIdentifier: "public.png")
            screenshot.name = "Screen at failure"
            var attachments = [screenshot]
            if let tree {
                attachments.append(XCTAttachment(string: tree))
                attachments[1].name = "UI tree at failure"
            }
            for attachment in attachments {
                // Kept even when the failure was expected, as in testAFailureKeepsTheScreenAndUITree.
                attachment.lifetime = .keepAlways
                issue.add(attachment)
            }
            isRecordingDiagnostics = false
        }
        super.record(issue)
    }

    /// The screen as a PNG, and the app's UI tree if the app is running.
    @MainActor
    private static func snapshot() -> (screen: Data, tree: String?) {
        let app = XCUIApplication()
        let tree = app.state == .runningForeground ? app.debugDescription : nil
        return (XCUIScreen.main.screenshot().pngRepresentation, tree)
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
