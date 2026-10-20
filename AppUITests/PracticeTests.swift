import XCTest

/// End-to-end tests of the Practice screen (SES-1, SES-2, SES-6).
///
/// Each launch fixes the app's clock (see `App/PianismApp.swift`), so times are exact, unless a test
/// needs real time to pass. Time passes between launches, which also proves a session survives the app
/// being killed.
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

    /// SES-4: a session left running ends itself at 4 hours of practice. When the app next opens, a banner
    /// says so, and its Edit opens the session in History, which counts the 4 hours.
    @MainActor
    func testSessionLeftRunningStopsAtTheCap() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()

        app = launch(at: start + 9 * 60 * 60)
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertEqual(
            text(app, "practice.capped"),
            "Pianism stopped your session at 4 hours of practice, in case the timer was left running.")
        attachScreenshot(of: app, named: "Stopped at the cap")
        tap(app, "practice.capped-edit")
        XCTAssertTrue(app.navigationBars["Edit session"].waitForExistence(timeout: 5), "The editor didn't open")
        attachScreenshot(of: app, named: "Editing the session the cap stopped")
        tap(app, "editor.cancel")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "history.session").value as? String, "4 hours")

        app.buttons["Practice"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["practice.last-session"].waitForExistence(timeout: 5))
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 4:00:00")
        XCTAssertFalse(app.staticTexts["practice.capped"].exists, "Edit should hide the banner")
    }

    /// SES-4: with the app left open, as on a music stand, the session ends itself when it reaches the cap,
    /// shortened to 3 seconds on the real clock. Nothing is checked while it runs, so a slow simulator can't
    /// miss it.
    @MainActor
    func testSessionStopsAtTheCapWhileOpen() throws {
        let app = launch(at: nil, reset: true, capSeconds: 3)
        tap(app, "practice.start")

        XCTAssertTrue(app.staticTexts["practice.capped"].waitForExistence(timeout: 30), "It didn't stop at the cap")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertEqual(
            text(app, "practice.capped"),
            "Pianism stopped your session at 3 seconds of practice, in case the timer was left running.")
    }

    /// SES-3: once a running session passes 90 minutes of practice, Practice asks "Still practicing?".
    /// "Still practicing", which stays as the way back after "I stopped earlier", puts it away for that session,
    /// even after a relaunch.
    @MainActor
    func testStillPracticingAsksOncePerSession() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        XCTAssertFalse(app.staticTexts["practice.still-practicing"].exists, "It asked too soon")
        app.terminate()

        app = launch(at: start + 95 * 60)
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 5), "It didn't ask")
        attachScreenshot(of: app, named: "Still practicing?")
        XCTAssertEqual(app.buttons["practice.stopped-earlier"].label, "I stopped earlier")
        tap(app, "practice.stopped-earlier")
        XCTAssertTrue(app.datePickers["practice.stopped-at"].waitForExistence(timeout: 5), "No end to pick")
        XCTAssertEqual(app.buttons["practice.stop-at"].label, "Stop at this time")
        XCTAssertEqual(app.buttons["practice.still-practicing-yes"].label, "Still practicing")
        tap(app, "practice.still-practicing-yes")
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        app.terminate()

        app = launch(at: start + 100 * 60)
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertFalse(app.staticTexts["practice.still-practicing"].exists, "It asked again")
    }

    /// SES-3: a Pause after 90 minutes answers "Still practicing?", so it doesn't come back on Resume.
    @MainActor
    func testPauseAnswersStillPracticing() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()

        app = launch(at: start + 95 * 60)
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 5), "It didn't ask")
        tap(app, "practice.pause")
        tap(app, "practice.resume")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertFalse(app.staticTexts["practice.still-practicing"].exists, "It asked again")
    }

    /// SES-3: the banner offers the notification, which then asks "Still practicing?" while the app is away. Its
    /// "Still practicing" answers for the session, and its "I stopped earlier" opens Practice to pick the end. A
    /// nudge that passes while History shows is asked when Practice is back. The clock is real and the nudge 10 s,
    /// as the system's notification needs time to pass.
    @MainActor
    func testNotificationAsksStillPracticing() throws {
        let app = launch(at: nil, reset: true, nudgeSeconds: 10)
        tap(app, "practice.start")
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 20), "It didn't ask")
        // The system asks once per install, so a retry on the same simulator finds the notification allowed.
        let remind = app.buttons["practice.remind-me"]
        if remind.waitForExistence(timeout: 3) {
            attachScreenshot(of: app, named: "Still practicing? with Remind me")
            remind.tap()
            let allow = springboard.alerts.buttons["Allow"]
            XCTAssertTrue(allow.waitForExistence(timeout: 10), "The system didn't ask")
            allow.tap()
            XCTAssertTrue(remind.waitForNonExistence(timeout: 5), "It offered the notification again")
        }
        tap(app, "practice.still-practicing-yes")

        tap(app, "practice.stop")
        tap(app, "practice.start")
        answerNotification(with: "Still practicing")
        app.activate()
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertFalse(
            app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 3), "The answer was lost")

        tap(app, "practice.stop")
        tap(app, "practice.start")
        // Left on History, so the notification has to bring Practice back.
        openHistory(app)
        answerNotification(with: "I stopped earlier")
        XCTAssertTrue(app.datePickers["practice.stopped-at"].waitForExistence(timeout: 10), "No end to pick")
        attachScreenshot(of: app, named: "Opened from the notification's I stopped earlier")
        tap(app, "practice.stop-at")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")

        tap(app, "practice.start")
        openHistory(app)
        // Real time has to pass the nudge, with nothing in History to wait for.
        Thread.sleep(forTimeInterval: 12)
        app.buttons["Practice"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 3), "It didn't ask on Practice")
    }

    /// SES-3: "I stopped earlier" shows wheels at the current time, which go back to when practice really
    /// stopped, and the session ends in that minute, at the start's seconds, so its length is whole minutes.
    @MainActor
    func testStoppedEarlier() throws {
        // Started 17 s into a minute, and picked 45 s into one: the wheels keep those 45 s hidden.
        var app = launch(at: start + 17, reset: true)
        tap(app, "practice.start")
        app.terminate()

        app = launch(at: start + 2 * 60 * 60 + 40 * 60 + 45)
        tap(app, "practice.stopped-earlier")
        let picker = app.datePickers["practice.stopped-at"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "No end to pick")
        // Date, hour, minute, AM or PM: from 2 h 40 min in, back to 2 h 10 min. This assumes the wheel order of
        // English and a time zone a whole number of hours from UTC, as on CI and the Mac. adjust can stop a row
        // short, so it tries again until the wheel shows the minute.
        let minutes = picker.pickerWheels.element(boundBy: 2)
        for _ in 1...3 where (minutes.value as? String)?.hasPrefix("10") != true {
            minutes.adjust(toPickerWheelValue: "10")
        }
        XCTAssertEqual((minutes.value as? String)?.hasPrefix("10"), true, "The wheel shows \(minutes.value ?? "")")
        attachScreenshot(of: app, named: "I stopped earlier")
        tap(app, "practice.stop-at")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 2:10:00")
    }

    /// SES-3: at the largest text size, with the wheels open, Practice scrolls so every control can still be
    /// reached. Without the scrolling, Pause sat below the screen's edge.
    @MainActor
    func testStoppedEarlierAtTheLargestTextSize() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()

        app = launch(at: start + 95 * 60, largestText: true)
        tap(app, "practice.stopped-earlier")
        XCTAssertTrue(app.datePickers["practice.stopped-at"].waitForExistence(timeout: 5), "No end to pick")
        attachScreenshot(of: app, named: "I stopped earlier, largest text")
        XCTAssertTrue(app.buttons["practice.stop-at"].exists)
        XCTAssertTrue(app.buttons["practice.still-practicing-yes"].exists)
        tap(app, "practice.pause")
        XCTAssertEqual(text(app, "practice.status"), "Paused")
    }

    /// SES-3, SES-4: with the app open, Practice asks "Still practicing?" at the nudge, then ends the session at
    /// the cap, shortened to 3 and 45 seconds on the real clock. The gap is wide, so a slow simulator can't miss
    /// the question before the cap ends it.
    @MainActor
    func testStillPracticingThenCapWhileOpen() throws {
        let app = launch(at: nil, reset: true, nudgeSeconds: 3, capSeconds: 45)
        tap(app, "practice.start")

        XCTAssertTrue(app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 30), "It didn't ask")
        XCTAssertTrue(app.staticTexts["practice.capped"].waitForExistence(timeout: 90), "It didn't stop at the cap")
    }

    /// HIS-1: a finished session appears under Today with its time, and the day shows its total.
    /// History is visited before and after Stop in one launch, so it must refresh when shown again.
    /// Opening the session, and its end's wheels, changes nothing (SES-5). It's stored, so it's still there
    /// after the app is killed and relaunched.
    @MainActor
    func testFinishedSessionAppearsInHistory() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()

        app = launch(at: start + 25 * 60 + 3)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "History, empty")
        app.buttons["Practice"].firstMatch.tap()
        tap(app, "practice.stop")
        openHistory(app)
        let day = element(app, "history.day")
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertEqual(day.label, "Today")
        XCTAssertEqual(day.value as? String, "25 minutes, 3 seconds")
        let session = element(app, "history.session")
        XCTAssertEqual(session.value as? String, "25 minutes, 3 seconds")
        attachScreenshot(of: app, named: "History, one session")
        // Its start and end fall at different seconds, which a time picked on the wheels would change.
        session.tap()
        XCTAssertTrue(app.navigationBars["Edit session"].waitForExistence(timeout: 5), "The editor didn't open")
        setEndMinute(app, to: nil, title: "Edit session")
        tap(app, "editor.cancel")
        let editor = app.navigationBars["Edit session"]
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "Cancel asked to discard a change")
        XCTAssertEqual(session.value as? String, "25 minutes, 3 seconds")
        app.terminate()

        app = launch(at: start + 60 * 60)
        openHistory(app)
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
        openHistory(app)
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
        openHistory(app)
        let session = element(app, "history.session")
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertTrue(session.label.hasSuffix("Untagged"), session.label)

        session.tap()
        tap(app, "editor.tags")
        tap(app, "Scales")
        XCTAssertTrue(app.buttons["Scales"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        tap(app, "tags.done")
        setEndMinute(app, to: "20", title: "Edit session")
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
        openHistory(app)
        let relaunched = element(app, "history.session")
        XCTAssertTrue(relaunched.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.label.hasSuffix("Scales"), relaunched.label)
        XCTAssertEqual(relaunched.value as? String, "20 minutes")
        relaunched.tap()
        let savedNote = element(app, "editor.note")
        XCTAssertTrue(savedNote.waitForExistence(timeout: 5))
        XCTAssertEqual(savedNote.value as? String, "Coda, slowly")
    }

    /// SES-5: a session is added after the fact from History. It starts 30 minutes long, and History
    /// shows it once it's saved.
    @MainActor
    func testAddASessionAfterTheFact() throws {
        let app = launch(at: start, reset: true)
        openHistory(app)
        tap(app, "history.add")
        XCTAssertTrue(app.navigationBars["Add session"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Add session")

        tap(app, "editor.save")
        XCTAssertTrue(app.buttons["editor.save"].waitForNonExistence(timeout: 5))
        let session = element(app, "history.session")
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertEqual(session.value as? String, "30 minutes")
        attachScreenshot(of: app, named: "History, added")
    }

    /// SES-5: with no changes, Cancel just closes the editor. Once something changes, it can't be swiped
    /// away, and Cancel asks before discarding the change.
    @MainActor
    func testUnsavedChangesAskBeforeClosing() throws {
        let app = launch(at: start, reset: true)
        openHistory(app)
        let editor = app.navigationBars["Add session"]
        tap(app, "history.add")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        tap(app, "editor.cancel")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))

        tap(app, "history.add")
        let note = element(app, "editor.note")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("Scales, slowly")
        // Drags the editor by its title to the bottom of the screen, which closes a sheet that allows it.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)))
        XCTAssertFalse(editor.waitForNonExistence(timeout: 3), "The editor was swiped away with a change")
        tap(app, "editor.cancel")
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Discard changes")
        discard.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5))
    }

    /// SES-5: a session that shares practice with another says so, but can still be saved. "Don't Show
    /// Again" turns the warning off for good, even after a relaunch.
    @MainActor
    func testOverlapWarningCanBeTurnedOff() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        openHistory(app)
        tap(app, "history.add")
        // The added session ends where the practiced one starts, so it warns only once it ends 20 minutes in.
        XCTAssertTrue(element(app, "editor.note").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "editor.overlap").exists, "The added session overlaps before any change")
        setEndMinute(app, to: "20", title: "Add session")
        XCTAssertTrue(element(app, "editor.overlap").waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Add session, overlapping")
        tap(app, "editor.overlap-off")
        XCTAssertTrue(element(app, "editor.overlap").waitForNonExistence(timeout: 5))
        tap(app, "editor.save")
        XCTAssertTrue(app.buttons["editor.save"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "history.session").count, 2)
        app.terminate()

        app = launch(at: start + 30 * 60)
        openHistory(app)
        tap(app, "history.add")
        // It now ends where the session added above starts, so ending at :45 shares 15 minutes with it.
        XCTAssertTrue(element(app, "editor.note").waitForExistence(timeout: 5))
        setEndMinute(app, to: "45", title: "Add session")
        let practiceTime = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Practice time'"))
        XCTAssertEqual(practiceTime.firstMatch.value as? String, "45 minutes")
        XCTAssertFalse(element(app, "editor.overlap").exists)
    }

    /// SES-5: a session is deleted with a swipe or from the editor, each confirmed first. Undo brings it
    /// back; once its 5 seconds are up, the deletion holds, across a relaunch too.
    @MainActor
    func testDeleteASessionWithUndo() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()
        // A long Undo, so a slow simulator's checks and screenshots can't outlast it.
        app = launch(at: start + 25 * 60, undoSeconds: 60)
        tap(app, "practice.stop")
        openHistory(app)
        deleteBySwipe(app)
        XCTAssertTrue(app.staticTexts["Session deleted"].exists)
        attachScreenshot(of: app, named: "Undo")
        tap(app, "history.undo")
        let session = element(app, "history.session")
        XCTAssertTrue(session.waitForExistence(timeout: 5))

        session.tap()
        tap(app, "editor.delete")
        XCTAssertTrue(app.staticTexts["Delete this session?"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Delete this session")
        confirmDelete(app)
        XCTAssertTrue(session.waitForNonExistence(timeout: 5))
        tap(app, "history.undo")
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        app.terminate()

        // The real 5 seconds.
        app = launch(at: start + 30 * 60)
        openHistory(app)
        deleteBySwipe(app)
        XCTAssertTrue(app.buttons["history.undo"].waitForNonExistence(timeout: 15), "Undo outlasted its 5 seconds")
        app.terminate()

        app = launch(at: start + 31 * 60)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5))
    }

    /// SES-5: a deletion is saved only when its undo ends, so a session deleted just before Pianism is killed
    /// is still there. Leaving History, or the app, ends the undo at once.
    @MainActor
    func testDeletionWaitsForUndoToEnd() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        app.terminate()
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        tap(app, "practice.start")
        app.terminate()
        // A long Undo, so only a kill, leaving History or leaving the app can end it.
        app = launch(at: start + 50 * 60, undoSeconds: 60)
        tap(app, "practice.stop")
        openHistory(app)
        deleteBySwipe(app)
        app.terminate()

        app = launch(at: start + 51 * 60, undoSeconds: 60)
        openHistory(app)
        var sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertTrue(sessions.element(boundBy: 1).waitForExistence(timeout: 5), "A kill didn't keep the session")
        deleteBySwipe(app)
        app.buttons["Practice"].firstMatch.tap()
        app.terminate()

        app = launch(at: start + 52 * 60, undoSeconds: 60)
        openHistory(app)
        sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertTrue(sessions.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(sessions.count, 1, "Leaving History didn't save the deletion")
        deleteBySwipe(app)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.terminate()

        app = launch(at: start + 53 * 60)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5), "Leaving the app didn't save it")
    }

    /// ADR 0007: when the history can't open, practice goes on. Each finished session waits in the
    /// outbox, Practice says how many are waiting, and History shows them marked "not saved yet" under
    /// a notice. Once the history opens, the waiting sessions move into it.
    @MainActor
    func testWhenHistoryCantOpen() throws {
        var app = launch(at: start, reset: true, breakHistory: true)
        // Nothing saved and nothing waiting: the whole screen says History couldn't load.
        openHistory(app)
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
        openHistory(app)
        XCTAssertTrue(element(app, "history.unavailable").waitForExistence(timeout: 5))
        let notSavedYet = NSPredicate(format: "label CONTAINS 'not saved yet'")
        let waiting = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(waiting.count, 2)
        XCTAssertEqual(waiting.matching(notSavedYet).count, 2)
        attachScreenshot(of: app, named: "History, sessions waiting")
        app.terminate()

        app = launch(at: start + 60 * 60)
        XCTAssertFalse(app.staticTexts["practice.waiting"].exists)
        openHistory(app)
        XCTAssertTrue(element(app, "history.day").waitForExistence(timeout: 5))
        let saved = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.matching(notSavedYet).count, 0)
    }

    /// The Home Screen, where the system shows notifications.
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// Leaves the app and answers its "Still practicing?" notification with the button titled `answer`. The system
    /// shows no notification for the app in front, and takes up to about 20 s to show it after the nudge.
    @MainActor
    private func answerNotification(with answer: String) {
        XCUIDevice.shared.press(.home)
        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Pianism is still timing your session.'")).firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: 40), "No notification")
        let button = springboard.buttons[answer]
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad shows the buttons when the banner is pulled down slowly from its bottom edge and held, not on a
            // long press. The pull sometimes misses, so it tries again while the banner is there.
            for _ in 0..<2 where notification.exists && !button.exists {
                let edge = springboard.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: notification.frame.midX, dy: notification.frame.maxY - 10))
                edge.press(
                    forDuration: 0.1, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: 500)), withVelocity: .slow,
                    thenHoldForDuration: 2.5)
                _ = button.waitForExistence(timeout: 3)
            }
        } else {
            notification.press(forDuration: 1.5)
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No \(answer) button")
        button.tap()
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Launches the app with its clock fixed at `now`, or on the real clock if `nil`.
    @MainActor
    private func launch(
        at now: TimeInterval?, reset: Bool = false, breakHistory: Bool = false, undoSeconds: Int? = nil,
        nudgeSeconds: Int? = nil, capSeconds: Int? = nil, largestText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if let now {
            app.launchEnvironment["PIANISM_NOW"] = String(now)
        }
        if let undoSeconds {
            app.launchEnvironment["PIANISM_UNDO_SECONDS"] = String(undoSeconds)
        }
        if let nudgeSeconds {
            app.launchEnvironment["PIANISM_NUDGE_SECONDS"] = String(nudgeSeconds)
        }
        if let capSeconds {
            app.launchEnvironment["PIANISM_CAP_SECONDS"] = String(capSeconds)
        }
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

    /// Opens the History tab. On iOS 26 a tap can land while the tab bar is still animating and not switch
    /// tabs, so it taps once more if History doesn't appear.
    @MainActor
    private func openHistory(_ app: XCUIApplication) {
        let tab = app.buttons["History"].firstMatch
        let history = app.navigationBars["History"]
        tab.tap()
        if !history.waitForExistence(timeout: 3) { tab.tap() }
        XCTAssertTrue(history.waitForExistence(timeout: 5), "History didn't open")
    }

    /// Taps Delete session in the confirmation, which iOS nests in a button with the same frame and identifier.
    @MainActor
    private func confirmDelete(_ app: XCUIApplication) {
        let confirm = app.buttons["delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No delete.confirm button")
        confirm.tap()
    }

    /// Deletes History's first session with a swipe, confirmed, and checks the list lost one.
    @MainActor
    private func deleteBySwipe(_ app: XCUIApplication) {
        let sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertTrue(sessions.firstMatch.waitForExistence(timeout: 5), "No session to delete")
        let count = sessions.count
        // A press, then a drag halfway across, which shows Delete without a full swipe. A busy simulator
        // can read swipeLeft as a tap, which opens the editor instead.
        let row = sessions.firstMatch
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        tap(app, "history.delete")
        confirmDelete(app)
        XCTAssertTrue(sessions.element(boundBy: count - 1).waitForNonExistence(timeout: 5))
    }

    /// Sets the editor's end minute with the end picker's wheels: hours, then minutes. With no minute, it opens
    /// the wheels and closes them without turning them.
    @MainActor
    private func setEndMinute(_ app: XCUIApplication, to minute: String?, title: String) {
        app.datePickers["editor.end"].buttons.matching(NSPredicate(format: "label CONTAINS ':'")).firstMatch.tap()
        let minutes = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(minutes.waitForExistence(timeout: 5), "The wheels didn't open")
        if let minute { minutes.adjust(toPickerWheelValue: minute) }
        // Closes the wheels with a tap on the editor's title, which does nothing if the tap gets through.
        // Elsewhere a tap can land on the wheels or the Tags row, and the status bar doesn't reach the app.
        let frame = app.navigationBars.staticTexts[title].frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.buttons["PopoverDismissRegion"].waitForNonExistence(timeout: 5))
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
