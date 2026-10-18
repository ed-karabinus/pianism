import XCTest

/// End-to-end tests of the Practice screen (SES-1, SES-2, SES-6).
///
/// Each launch fixes the app's clock (see `App/PianismApp.swift`), so times are exact. Time
/// passes between launches, which also proves a session survives the app being killed.
final class PracticeTests: UITestCase {
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

    /// HIS-1: a finished session appears under Today with its time, and the day shows its total.
    /// History is visited before and after Stop in one launch, so it must refresh when shown again.
    /// It's stored, so it's still there after the app is killed and relaunched.
    @MainActor
    func testFinishedSessionAppearsInHistory() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()

        app = launch(at: start + 25 * 60 + 3)
        app.buttons["History"].firstMatch.tap()
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "History, empty")
        app.buttons["Practice"].firstMatch.tap()
        tap(app, "practice.stop")
        app.buttons["History"].firstMatch.tap()
        let day = element(app, "history.day")
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertEqual(day.label, "Today")
        XCTAssertEqual(day.value as? String, "25 minutes, 3 seconds")
        XCTAssertEqual(element(app, "history.session").value as? String, "25 minutes, 3 seconds")
        attachScreenshot(of: app, named: "History, one session")
        app.terminate()

        app = launch(at: start + 60 * 60)
        app.buttons["History"].firstMatch.tap()
        let relaunched = element(app, "history.day")
        XCTAssertTrue(relaunched.waitForExistence(timeout: 5))
        XCTAssertEqual(relaunched.value as? String, "25 minutes, 3 seconds")
    }

    /// TAG-1, TAG-2: a running session is tagged from Practice with a new piece and a built-in skill,
    /// and History shows them; a session left untagged shows "Untagged". The tags are stored, so
    /// they're still there after the app is killed and relaunched.
    @MainActor
    func testTagARunningSession() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Untagged")
        tap(app, "practice.tags")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Ballade No. 1")
        tap(app, "tags.add-piece")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Adding should put the keyboard away")
        XCTAssertTrue(app.buttons["Ballade No. 1"].isSelected)
        tap(app, "Scales")
        XCTAssertTrue(app.buttons["Scales"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        attachScreenshot(of: app, named: "Tag picker")
        tap(app, "tags.done")
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Ballade No. 1, Scales")
        attachScreenshot(of: app, named: "Practicing, tagged")
        app.terminate()

        app = launch(at: start + 25 * 60)
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Ballade No. 1, Scales")
        tap(app, "practice.stop")
        tap(app, "practice.start")
        tap(app, "practice.stop")
        app.buttons["History"].firstMatch.tap()
        XCTAssertTrue(element(app, "history.day").waitForExistence(timeout: 5))
        let sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.matching(NSPredicate(format: "label ENDSWITH 'Ballade No. 1, Scales'")).count, 1)
        XCTAssertEqual(sessions.matching(NSPredicate(format: "label ENDSWITH 'Untagged'")).count, 1)
        attachScreenshot(of: app, named: "History, tagged and untagged")
    }

    /// SES-5, TAG-2: a finished session is tagged, ended 5 minutes earlier and given a note from History,
    /// which shows the tags and the shorter practice time once the edit is saved. It's all stored, so
    /// it's still there after the app is killed and relaunched.
    @MainActor
    func testEditAFinishedSession() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        app.buttons["History"].firstMatch.tap()
        let session = element(app, "history.session")
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertTrue(session.label.hasSuffix("Untagged"), session.label)

        session.tap()
        tap(app, "editor.tags")
        tap(app, "Scales")
        XCTAssertTrue(app.buttons["Scales"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        tap(app, "tags.done")
        // The end picker's time button opens its wheels: hours, then minutes.
        app.datePickers["editor.end"].buttons.matching(NSPredicate(format: "label CONTAINS ':'")).firstMatch.tap()
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "20")
        app.buttons["PopoverDismissRegion"].tap()
        let note = element(app, "editor.note")
        note.tap()
        note.typeText("Coda, slowly")
        attachScreenshot(of: app, named: "Edit session")
        tap(app, "editor.save")
        XCTAssertTrue(app.buttons["editor.save"].waitForNonExistence(timeout: 5))
        let tagged = app.descendants(matching: .any).matching(identifier: "history.session")
            .matching(NSPredicate(format: "label ENDSWITH 'Scales'"))
        XCTAssertTrue(tagged.firstMatch.waitForExistence(timeout: 5), session.label)
        XCTAssertEqual(tagged.firstMatch.value as? String, "20 minutes")
        attachScreenshot(of: app, named: "History, edited")
        app.terminate()

        app = launch(at: start + 60 * 60)
        app.buttons["History"].firstMatch.tap()
        let relaunched = element(app, "history.session")
        XCTAssertTrue(relaunched.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.label.hasSuffix("Scales"), relaunched.label)
        XCTAssertEqual(relaunched.value as? String, "20 minutes")
        relaunched.tap()
        let savedNote = element(app, "editor.note")
        XCTAssertTrue(savedNote.waitForExistence(timeout: 5))
        XCTAssertEqual(savedNote.value as? String, "Coda, slowly")
    }

    /// ADR 0007: when the history can't open, practice goes on. Each finished session waits in the
    /// outbox, Practice says how many are waiting, and History shows them marked "not saved yet" under
    /// a notice. Once the history opens, the waiting sessions move into it.
    @MainActor
    func testWhenHistoryCantOpen() throws {
        var app = launch(at: start, reset: true, breakHistory: true)
        // Nothing saved and nothing waiting: the whole screen says History couldn't load.
        app.buttons["History"].firstMatch.tap()
        XCTAssertTrue(element(app, "history.unavailable").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "history.session").exists)
        app.buttons["Practice"].firstMatch.tap()
        for _ in 1...2 {
            tap(app, "practice.start")
            tap(app, "practice.stop")
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(text(app, "practice.waiting"), "2 sessions waiting to be saved")
        attachScreenshot(of: app, named: "Practice, sessions waiting")
        app.buttons["History"].firstMatch.tap()
        XCTAssertTrue(element(app, "history.unavailable").waitForExistence(timeout: 5))
        let notSavedYet = NSPredicate(format: "label CONTAINS 'not saved yet'")
        let waiting = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(waiting.count, 2)
        XCTAssertEqual(waiting.matching(notSavedYet).count, 2)
        attachScreenshot(of: app, named: "History, sessions waiting")
        app.terminate()

        app = launch(at: start + 60 * 60)
        XCTAssertFalse(app.staticTexts["practice.waiting"].exists)
        app.buttons["History"].firstMatch.tap()
        XCTAssertTrue(element(app, "history.day").waitForExistence(timeout: 5))
        let saved = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.matching(notSavedYet).count, 0)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func launch(at now: TimeInterval, reset: Bool = false, breakHistory: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PIANISM_NOW"] = String(now)
        if reset {
            app.launchEnvironment["PIANISM_RESET"] = "1"
        }
        if breakHistory {
            app.launchEnvironment["PIANISM_BREAK_HISTORY"] = "1"
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
