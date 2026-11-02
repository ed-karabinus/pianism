import XCTest
import notify

/// A UI test that keeps the screen and the app's UI tree as they were when it failed, so a failure
/// on CI can be diagnosed from its results without rerunning it. It kills the app (`kill(_:)`) when it ends,
/// so the next test's launch has no app to terminate.
class UITestCase: XCTestCase {
    private var isDroppingIssues = false
    @MainActor private static var hasWarmedUp = false

    override func setUp() {
        super.setUp()
        // UI tests run on the main thread, as in tearDown().
        if Thread.isMainThread {
            isDroppingIssues = true
            MainActor.assumeIsolated { Self.warmUp() }
            isDroppingIssues = false
        }
    }

    /// On CI, a freshly booted iOS 27 simulator sometimes takes 60 s to let XCTest reach a launched app, and for
    /// minutes after that a test's first query fails ("kAXErrorServerNotFound", or "does not have a process ID":
    /// #136). So before the run's first test, the app launches until XCTest can reach its window, for up to 10
    /// minutes, and what XCTest reports meanwhile is dropped (`record(_:)`). The 10 minutes are real time, which E3
    /// and E4 rule out for what a test checks; this waits for the simulator rather than testing the app.
    @MainActor
    private static func warmUp() {
        guard !hasWarmedUp else { return }
        hasWarmedUp = true
        let app = XCUIApplication()
        let start = Date.now
        for attempt in 1... {
            app.launch()
            let reachable = app.windows.firstMatch.waitForExistence(timeout: 10)
            XCTContext.runActivity(named: "Warm-up launch \(attempt): \(reachable ? "reached" : "not reached")") { _ in
            }
            _ = Self.kill(app)
            if reachable || Date.now.timeIntervalSince(start) > 600 { break }
        }
    }

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
        // before the failure it was taken for. So is one while the simulator settles (`warmUp()`).
        guard !isDroppingIssues else { return }
        var issue = issue
        // UI tests fail on the main thread; skipping the diagnostics elsewhere beats trapping.
        if Thread.isMainThread {
            isDroppingIssues = true
            let (screen, tree) = MainActor.assumeIsolated { Self.snapshot() }
            let screenshot = XCTAttachment(data: screen, uniformTypeIdentifier: "public.png")
            screenshot.name = "Screen at failure"
            issue.add(screenshot)
            if let tree {
                let attachment = XCTAttachment(string: tree)
                attachment.name = "UI tree at failure"
                issue.add(attachment)
            }
            isDroppingIssues = false
        }
        super.record(issue)
    }

    /// Skips a test that only the nightly and manual CI runs take, with `reason` saying what it leans on: real time
    /// or a simulator service a pull request's run shouldn't wait on until the test has passed nightly for a week.
    /// Those runs set `TEST_RUNNER_PIANISM_SOAKING=1` (`.github/workflows/ci.yml`), which xcodebuild hands the test
    /// runner as `PIANISM_SOAKING`; a local run sets it the same way.
    func skipUnlessSoaking(_ reason: String) throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PIANISM_SOAKING"] == "1", "Nightly and manual runs only: \(reason)")
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
