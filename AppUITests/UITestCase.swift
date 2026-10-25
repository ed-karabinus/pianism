import XCTest
import notify

/// A UI test that keeps the screen and the app's UI tree as they were when it failed, so a failure
/// on CI can be diagnosed from its results without rerunning it. It kills the app (`kill(_:)`) when it ends,
/// so the next test's launch has no app to terminate.
class UITestCase: XCTestCase {
    private var isRecordingDiagnostics = false

    override func tearDown() {
        // Not async: with an async tearDown, XCTest stops a failing test (continueAfterFailure = false) by
        // restarting the test runner, which loses the test's retry. UI tests run on the main thread, as in record(_:).
        if Thread.isMainThread {
            XCTAssertTrue(MainActor.assumeIsolated { Self.kill(XCUIApplication()) }, "The app didn't exit")
        }
        super.tearDown()
    }

    /// Kills the app without warning, as SES-6 needs. `XCUIApplication.terminate()` gives up after 60 s if the app
    /// hasn't exited, as does `launch()` when it terminates an app still running, and on CI a freshly booted iOS 27
    /// simulator sometimes takes longer. So a Debug build exits on this Darwin notification (`PianismApp`), and the
    /// test waits longer.
    @MainActor
    func kill(_ app: XCUIApplication) {
        XCTAssertTrue(Self.kill(app), "The app didn't exit")
    }

    /// Whether the app, if it was running, has exited.
    @MainActor
    private static func kill(_ app: XCUIApplication) -> Bool {
        let state = app.state
        guard state != .notRunning else { return true }
        // A background app may already be suspended, and a suspended app can't hear the notification.
        if state != .runningForeground { app.activate() }
        notify_post("com.edkarabinus.Pianism.kill")
        return app.wait(for: .notRunning, timeout: 180)
    }

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
