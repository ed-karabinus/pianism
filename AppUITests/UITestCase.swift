import XCTest

/// A UI test that keeps the screen and the app's UI tree as they were when it failed, so a failure
/// on CI can be diagnosed from its results without rerunning it.
class UITestCase: XCTestCase {
    private var isRecordingDiagnostics = false

    override func record(_ issue: XCTIssue) {
        // A failure while taking the diagnostics is dropped: recording it would stop the test
        // before the failure it was taken for.
        guard !isRecordingDiagnostics else { return }
        var issue = issue
        // UI tests fail on the main thread; skipping the diagnostics elsewhere beats trapping.
        if Thread.isMainThread {
            isRecordingDiagnostics = true
            let (screen, tree) = MainActor.assumeIsolated { Self.snapshot() }
            let screenshot = XCTAttachment(data: screen, uniformTypeIdentifier: "public.png")
            screenshot.name = "Screen at failure"
            issue.add(screenshot)
            if let tree {
                let attachment = XCTAttachment(string: tree)
                attachment.name = "UI tree at failure"
                issue.add(attachment)
            }
            isRecordingDiagnostics = false
        }
        super.record(issue)
    }

    /// Keeps a screenshot in the test results as visual evidence for PR review.
    /// `make evidence` exports these from the last run.
    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The screen as a PNG, and the app's UI tree if the app is running.
    @MainActor
    private static func snapshot() -> (screen: Data, tree: String?) {
        let app = XCUIApplication()
        let tree = app.state == .runningForeground ? app.debugDescription : nil
        return (XCUIScreen.main.screenshot().pngRepresentation, tree)
    }
}
