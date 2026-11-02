import CoreMIDI
import XCTest
import notify

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
        // MIDI-2: the line opens how to connect a piano, with the tip for a piano that doesn't show up over USB.
        XCTAssertEqual(app.buttons["practice.pianos"].label, "Connect a piano")
        tap(app, "practice.pianos")
        XCTAssertTrue(app.buttons["pianos.pair"].waitForExistence(timeout: 5), "No way to pair a Bluetooth piano")
        XCTAssertEqual(
            text(app, "pianos.replug"),
            "If your piano doesn't show up, unplug the cable at the piano's end and plug it back in.")
        attachScreenshot(of: app, named: "Connect a piano")
        tap(app, "pianos.done")
        XCTAssertTrue(app.buttons["pianos.pair"].waitForNonExistence(timeout: 5), "The sheet didn't close")

        tap(app, "practice.start")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        attachScreenshot(of: app, named: "Practicing")

        tap(app, "practice.pause")
        XCTAssertEqual(text(app, "practice.status"), "Paused")
        attachScreenshot(of: app, named: "Paused")
        // Side by side when they fit (testCommandsFitAtEveryTextSize).
        XCTAssertEqual(
            element(app, "practice.resume").frame.midY, element(app, "practice.stop").frame.midY, accuracy: 1)

        tap(app, "practice.resume")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")

        tap(app, "practice.stop")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertTrue(app.buttons["practice.start"].exists)
        // The clock is fixed, so it had no practice: under 10 s, it's dropped quietly (SES-1).
        XCTAssertFalse(app.staticTexts["practice.last-session"].exists, "A session under 10 s was kept")
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5), "A session under 10 s was kept")
    }

    /// MIDI-1: three notes start a session, and a Stop with under a minute of played time discards it and says so.
    /// The simulator has no piano, so the app plays a chord at launch, on the fixed clock.
    @MainActor
    func testThreeNotesStartASessionAndAShortStopDiscardsIt() throws {
        let app = launch(at: start, reset: true, midiNotes: "0,0,0", midiPiano: "MIDI KEYBOARD")
        XCTAssertTrue(app.buttons["practice.stop"].waitForExistence(timeout: 10), "The notes didn't start a session")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertEqual(app.buttons["practice.pianos"].label, "MIDI KEYBOARD connected")  // MIDI-2
        attachScreenshot(of: app, named: "A MIDI session, with the piano connected")

        tap(app, "practice.stop")

        XCTAssertTrue(app.staticTexts["practice.too-short"].waitForExistence(timeout: 5), "It didn't say so")
        XCTAssertEqual(text(app, "practice.too-short"), "Too short to save")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        attachScreenshot(of: app, named: "Too short to save")
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5), "A MIDI session under 1 min was kept")
    }

    /// MIDI-1: a silence pauses a MIDI session at its last note, and a longer one saves it 5 s after that note, with no
    /// tap. On the real clock, with the timeouts shortened to 10 and 20 s and the shortest session kept to 2 s.
    @MainActor
    func testPlayingPausesAfterSilenceAndSavesItself() throws {
        let app = launch(
            at: nil, reset: true, midiNotes: "0.5,0.8,1.1,2.5,4", midiPauseSeconds: 10, midiSaveSeconds: 20,
            midiMinimumSeconds: 2)
        XCTAssertTrue(app.buttons["practice.stop"].waitForExistence(timeout: 10), "The notes didn't start a session")

        let paused = app.staticTexts["practice.status"].wait(
            for: \.label, toEqual: "Paused at your last note", timeout: 30)
        XCTAssertTrue(paused, "The silence didn't pause it")
        attachScreenshot(of: app, named: "Paused at your last note")

        // Played from the first note to the last, 3.5 s; the 5 s after the last note were a pause.
        XCTAssertTrue(app.staticTexts["practice.last-session"].waitForExistence(timeout: 90), "It didn't save itself")
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 0:03")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        openHistory(app)
        XCTAssertEqual(element(app, "history.session").value as? String, "3 seconds")
    }

    /// MIDI-1, MIDI-R3: a MIDI session killed while the app is away, and opened after a minute's silence, opens
    /// paused at its last note, which the app stored as it left the screen, with no time counted for the silence.
    @MainActor
    func testAKillWhileAwayKeepsTheLastNote() throws {
        var app = launch(at: start, reset: true, midiNotes: "0,0,0")
        XCTAssertTrue(app.buttons["practice.stop"].waitForExistence(timeout: 10), "The notes didn't start a session")
        kill(app)
        // A note 30 s in changes nothing stored until the app leaves the screen.
        app = launch(at: start + 30, midiNotes: "0")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        goHome()
        kill(app)

        app = launch(at: start + 91)

        XCTAssertEqual(text(app, "practice.status"), "Paused at your last note")
        XCTAssertEqual(elapsed(app), "30 seconds")
        attachScreenshot(of: app, named: "Paused at its last note after a kill while away")
    }

    /// MIDI-R3: a MIDI session played for over a minute, then left alone for longer than ten minutes, ended at its
    /// last note and saved itself: Practice shows it as the last session, and History has it (device row M10). The
    /// notes come 30 s apart, inside the minute of silence that pauses a session, each in its own launch, and the
    /// app leaves the screen before each kill, as that's when it stores the last note.
    @MainActor
    func testAMIDISessionLeftForTenMinutesEndsAtItsLastNote() throws {
        var app = launch(at: start, reset: true, midiNotes: "0,0,0")
        XCTAssertTrue(app.buttons["practice.stop"].waitForExistence(timeout: 10), "The notes didn't start a session")
        for seconds in [30, 61] {
            goHome()
            kill(app)
            app = launch(at: start + TimeInterval(seconds), midiNotes: "0")
            XCTAssertEqual(text(app, "practice.status"), "Practicing")
        }
        goHome()
        kill(app)

        app = launch(at: start + 61 + 15 * 60)

        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertTrue(app.staticTexts["practice.last-session"].waitForExistence(timeout: 5), "No last session")
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 1:01")
        openHistory(app)
        let session = element(app, "history.session")
        XCTAssertTrue(session.waitForExistence(timeout: 5), "History doesn't have it")
        XCTAssertEqual(session.value as? String, "1 minute, 1 second")
    }

    /// SES-6: killed while running and while paused, the session comes back with the right time,
    /// and paused time never counts (SES-2).
    @MainActor
    func testSessionSurvivesBeingKilled() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        kill(app)

        app = launch(at: start + 25 * 60 + 3)
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertEqual(elapsed(app), "25 minutes, 3 seconds")
        attachScreenshot(of: app, named: "Restored after being killed")
        tap(app, "practice.pause")
        kill(app)

        app = launch(at: start + 40 * 60)
        XCTAssertEqual(text(app, "practice.status"), "Paused")
        XCTAssertEqual(elapsed(app), "25 minutes, 3 seconds")
        tap(app, "practice.resume")
        kill(app)

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
        kill(app)

        app = launch(at: start + 9 * 60 * 60)
        assertStoppedAtTheCap(app)
        tap(app, "practice.capped-edit")
        XCTAssertTrue(app.navigationBars["Edit session"].waitForExistence(timeout: 5), "The editor didn't open")
        attachScreenshot(of: app, named: "Editing the session the cap stopped")
        tap(app, "editor.cancel")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "history.session").value as? String, "4 hours")

        openPractice(app)
        XCTAssertTrue(app.staticTexts["practice.last-session"].waitForExistence(timeout: 5))
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 4:00:00")
        XCTAssertFalse(app.staticTexts["practice.capped"].exists, "Edit should hide the banner")
    }

    /// GLN-2: the widget's Start runs an intent in the app's process, which starts the session through the same model
    /// as a tap, so the nudge asks and the cap stops it as for any session. The widget can't be tapped on a simulator
    /// (ADR 0010), so the app performs the intent at launch instead; the device checklist covers the tap itself.
    @MainActor
    func testTheWidgetsIntentStartsASessionAndTheAppPicksItUp() throws {
        var app = launch(at: start, reset: true, intent: "start")
        XCTAssertEqual(text(app, "practice.status"), "Practicing", "The intent didn't start a session")
        attachScreenshot(of: app, named: "Started by the widget's intent")
        kill(app)

        app = launch(at: start + 95 * 60)
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 5), "It didn't ask")
        kill(app)

        app = launch(at: start + 9 * 60 * 60)
        assertStoppedAtTheCap(app)
    }

    /// GLN-1: the Live Activity's Pause, Resume and Stop run intents in the app's process, which change the session
    /// through the same model as the taps on Practice, so Practice agrees with the Lock Screen. XCUITest can't tap
    /// the activity's buttons, so the app performs each intent at launch and Practice shows the result; the tests
    /// below check the activity itself on the Home Screen, and the device checklist (L1–L9) its buttons.
    @MainActor
    func testTheLiveActivitysButtonsPauseResumeAndStop() throws {
        var app = launch(at: start, reset: true, intent: "start")
        assertStatus(app, becomes: "Practicing", "The intent didn't start a session")
        kill(app)

        app = launch(at: start + 10 * 60, intent: "pause")
        assertStatus(app, becomes: "Paused", "The intent didn't pause the session")
        XCTAssertEqual(elapsed(app), "10 minutes")
        attachScreenshot(of: app, named: "Paused by the Live Activity's intent")
        kill(app)

        app = launch(at: start + 15 * 60, intent: "resume")
        assertStatus(app, becomes: "Practicing", "The intent didn't resume the session")
        kill(app)

        app = launch(at: start + 25 * 60, intent: "stop")
        assertStatus(app, becomes: "Ready to practice", "The intent didn't stop the session")
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 20:00")
        attachScreenshot(of: app, named: "Stopped by the Live Activity's intent")
    }

    /// Asserts the status reads `expected`, waiting up to 5 s for it: an intent performed at launch runs in a task,
    /// which the first frame can beat.
    @MainActor
    private func assertStatus(_ app: XCUIApplication, becomes expected: String, _ message: String) {
        let status = app.staticTexts["practice.status"]
        let reads = expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: status)
        _ = XCTWaiter.wait(for: [reads], timeout: 5)
        XCTAssertEqual(status.label, expected, message)
    }

    /// SES-4: with the app left open, as on a music stand, the session ends itself when it reaches the cap,
    /// shortened to 12 seconds on the real clock, over the 10 s a session needs to be kept (SES-1). Nothing is
    /// checked while it runs, so a slow simulator can't miss it.
    @MainActor
    func testSessionStopsAtTheCapWhileOpen() throws {
        let app = launch(at: nil, reset: true, capSeconds: 12)
        tap(app, "practice.start")

        XCTAssertTrue(app.staticTexts["practice.capped"].waitForExistence(timeout: 30), "It didn't stop at the cap")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertEqual(
            text(app, "practice.capped"),
            "Pianism stopped your session at 12 seconds of practice, in case the timer was left running.")
    }

    /// SES-3: once a running session passes 90 minutes of practice, Practice asks "Still practicing?".
    /// "Still practicing", which stays as the way back after "I stopped earlier", puts it away for that session,
    /// even after a relaunch.
    @MainActor
    func testStillPracticingAsksOncePerSession() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        XCTAssertFalse(app.staticTexts["practice.still-practicing"].exists, "It asked too soon")
        kill(app)

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
        kill(app)

        app = launch(at: start + 100 * 60)
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertFalse(app.staticTexts["practice.still-practicing"].exists, "It asked again")
    }

    /// SES-3: a Pause after 90 minutes answers "Still practicing?", so it doesn't come back on Resume.
    @MainActor
    func testPauseAnswersStillPracticing() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        kill(app)

        app = launch(at: start + 95 * 60)
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 5), "It didn't ask")
        tap(app, "practice.pause")
        tap(app, "practice.resume")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertFalse(app.staticTexts["practice.still-practicing"].exists, "It asked again")
    }

    /// SES-3: with the notification offered, the answers stay side by side where they fit. The card was once measured
    /// for one arrangement and drawn with the other. The system offers it once per install, so the app offers it
    /// here whatever the system says, and a retry checks again. At the default text size they fit side by side on
    /// the iPhones and iPads CI picks, 402 pt wide or more.
    @MainActor
    func testRemindMeKeepsTheAnswersSideBySide() throws {
        let app = launch(at: nil, reset: true, nudgeSeconds: 3, offerNudges: true)
        tap(app, "practice.start")
        XCTAssertTrue(app.buttons["practice.remind-me"].waitForExistence(timeout: 20), "It didn't offer it")
        XCTAssertEqual(
            app.buttons["practice.still-practicing-yes"].frame.minY, app.buttons["practice.stopped-earlier"].frame.minY,
            accuracy: 1, "The answers stacked")
    }

    /// SES-3: the banner offers the notification, which then asks "Still practicing?" while the app is away, unless
    /// the session is paused. Its "Still practicing" answers for the session, and its "I stopped earlier" opens
    /// Practice to pick the end. A nudge that passes while History shows is asked when Practice is back. The clock
    /// is real and the nudge 20 s, as the system's notification needs time to pass.
    @MainActor
    func testNotificationAsksStillPracticing() throws {
        // 20 s, as the app has to be away before the nudge: a tick at the nudge with the app in front asks there and
        // cancels the notification. Starting, opening History and swiping home took 10 s on CI's iPhone Duo once the
        // Live Activity started alongside (2026-11-01), and had under a second to spare on a Mac with 10 s.
        let app = launch(at: nil, reset: true, nudgeSeconds: 20)
        tap(app, "practice.start")
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 30), "It didn't ask")
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
        tap(app, "practice.pause")
        goHome()
        XCTAssertFalse(notification.waitForExistence(timeout: 30), "It nudged a paused session")
        app.activate()
        tap(app, "practice.resume")
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
        Thread.sleep(forTimeInterval: 22)
        openPractice(app)
        XCTAssertTrue(
            app.staticTexts["practice.still-practicing"].waitForExistence(timeout: 3), "It didn't ask on Practice")
        // A new banner asks the system again, which says it's allowed.
        XCTAssertFalse(
            app.buttons["practice.remind-me"].waitForExistence(timeout: 3), "It offered the notification again")
    }

    /// SES-3: "I stopped earlier" shows wheels at the current time, which go back to when practice really
    /// stopped, and the session ends in that minute, at the start's seconds, so its length is whole minutes.
    @MainActor
    func testStoppedEarlier() throws {
        // Started 17 s into a minute, and picked 45 s into one: the wheels keep those 45 s hidden.
        var app = launch(at: start + 17, reset: true)
        tap(app, "practice.start")
        kill(app)

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
        kill(app)

        app = launch(at: start + 95 * 60, textSize: "AccessibilityXXXL")
        tap(app, "practice.stopped-earlier")
        XCTAssertTrue(app.datePickers["practice.stopped-at"].waitForExistence(timeout: 5), "No end to pick")
        attachScreenshot(of: app, named: "I stopped earlier, largest text")
        XCTAssertTrue(app.buttons["practice.stop-at"].exists)
        XCTAssertTrue(app.buttons["practice.still-practicing-yes"].exists)
        tap(app, "practice.pause")
        XCTAssertEqual(text(app, "practice.status"), "Paused")
    }

    /// SES-1, SES-2: at every text size, Pause or Resume and Stop stack where side by side would break their names
    /// mid-word, and stay above the tab bar.
    @MainActor
    func testCommandsFitAtEveryTextSize() throws {
        continueAfterFailure = true  // So one run reports every size that fails.
        let accessibilitySizes = ["M", "L", "XL", "XXL", "XXXL"].map { "Accessibility\($0)" }
        for size in ["L", "XL", "XXL", "XXXL"] + accessibilitySizes {
            let app = launch(at: start, reset: true, textSize: size)
            tap(app, "practice.start")
            assertCommandsFit(app, beside: "practice.pause", at: size)
            tap(app, "practice.pause")
            assertCommandsFit(app, beside: "practice.resume", at: size)
            attachScreenshot(of: app, named: "Paused, text size \(size)")
            kill(app)
        }
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

    /// HIS-1, HIS-2: a finished session appears under Today with its time, and the day and the week show their totals.
    /// History is visited before and after Stop in one launch, so it must refresh when shown again.
    /// Opening the session, and its end's wheels, changes nothing (SES-5). It's stored, so it's still there
    /// after the app is killed and relaunched.
    @MainActor
    func testFinishedSessionAppearsInHistory() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        kill(app)

        app = launch(at: start + 25 * 60 + 3)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "History, empty")
        openPractice(app)
        tap(app, "practice.stop")
        openHistory(app)
        let day = element(app, "history.day")
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertEqual(day.label, "Today")
        XCTAssertEqual(day.value as? String, "25 minutes, 3 seconds")
        // HIS-2: this week so far is this one session.
        let week = element(app, "history.week")
        XCTAssertEqual(week.label, "This week")
        XCTAssertEqual(week.value as? String, "25 minutes, 3 seconds")
        // Untagged time alone isn't broken down, as it would only repeat the total.
        XCTAssertFalse(element(app, "history.week-tag").exists)
        let session = element(app, "history.session")
        XCTAssertEqual(session.value as? String, "25 minutes, 3 seconds")
        XCTAssertTrue(session.isHittable, "The week pushed the session off the screen")
        attachScreenshot(of: app, named: "History, one session")
        // Its start and end fall at different seconds, which a time picked on the wheels would change.
        session.tap()
        XCTAssertTrue(app.navigationBars["Edit session"].waitForExistence(timeout: 5), "The editor didn't open")
        setEndMinute(app, to: nil, title: "Edit session")
        tap(app, "editor.cancel")
        let editor = app.navigationBars["Edit session"]
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "Cancel asked to discard a change")
        XCTAssertEqual(session.value as? String, "25 minutes, 3 seconds")
        kill(app)

        app = launch(at: start + 60 * 60)
        openHistory(app)
        let relaunched = element(app, "history.day")
        XCTAssertTrue(relaunched.waitForExistence(timeout: 5))
        XCTAssertEqual(relaunched.value as? String, "25 minutes, 3 seconds")
    }

    /// HIS-2: History shows this week, and earlier weeks with the arrows or a swipe on the chart, back to the week of
    /// the first session. A week before last is titled by its dates, with the year when it isn't this one. A tap on a
    /// day scrolls to its sessions.
    @MainActor
    func testEarlierWeeksShowWithTheArrowsOrASwipe() throws {
        let week: TimeInterval = 7 * 24 * 60 * 60
        for (startedAt, minutes) in [(start, 25.0), (start + week, 10.0), (start + 2 * week, 5.0)] {
            var app = launch(at: startedAt, reset: startedAt == start)
            tap(app, "practice.start")
            kill(app)
            app = launch(at: startedAt + minutes * 60)
            tap(app, "practice.stop")
            kill(app)
        }

        let app = launch(at: start + 2 * week + 60 * 60)
        openHistory(app)
        let shown = element(app, "history.week")
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        XCTAssertEqual("\(shown.label): \(shown.value ?? "")", "This week: 5 minutes")
        XCTAssertFalse(app.buttons["history.week-later"].isEnabled)
        tap(app, "history.week-earlier")
        XCTAssertEqual("\(shown.label): \(shown.value ?? "")", "Last week: 10 minutes")
        tap(app, "history.week-earlier")
        // The first session's week, which began in December 2026.
        XCTAssertTrue(shown.label.hasPrefix("Dec"), shown.label)
        XCTAssertTrue(shown.label.contains("2026"), shown.label)
        XCTAssertEqual(shown.value as? String, "25 minutes")
        XCTAssertFalse(app.buttons["history.week-earlier"].isEnabled, "There's no practice before the first week")
        attachScreenshot(of: app, named: "History, the first week")
        let firstWeek = shown.label
        element(app, "history.week-chart").swipeLeft()
        XCTAssertTrue(shown.wait(for: \.label, toEqual: "Last week", timeout: 5), "The swipe didn't show a later week")
        element(app, "history.week-chart").swipeRight()
        XCTAssertTrue(shown.wait(for: \.label, toEqual: firstWeek, timeout: 5), "The swipe didn't show an earlier week")

        // A tap on Thursday's bar scrolls to its session, unless it's on screen already, as on an iPad.
        let session = app.descendants(matching: .any).matching(identifier: "history.session")
            .matching(NSPredicate(format: "value == '25 minutes'")).firstMatch
        let wasShown = session.exists && session.isHittable
        element(app, "history.week-chart").descendants(matching: .any)["Thursday"].tap()
        if !wasShown {
            XCTAssertTrue(session.waitForExistence(timeout: 5))
            XCTAssertTrue(session.wait(for: \.isHittable, toEqual: true, timeout: 5), "The tap didn't show Thursday")
        }
        attachScreenshot(of: app, named: "History, a tapped day")
    }

    /// TAG-1, TAG-2, HIS-2: a running session is tagged from Practice with a new piece and a built-in skill,
    /// and History shows them on the session and in the week's time by tag; a session left untagged shows
    /// "Untagged". The tags are stored, so they're still there after the app is killed and relaunched.
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
        kill(app)

        app = launch(at: start + 25 * 60)
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Ballade No. 1, Scales")
        tap(app, "practice.stop")
        tap(app, "practice.start")
        kill(app)

        // A minute later, so the untagged session is long enough to keep (SES-1).
        app = launch(at: start + 26 * 60)
        tap(app, "practice.stop")
        openHistory(app)
        // HIS-2: the week's time with each tag is a tap away, so the sessions stay on screen.
        XCTAssertTrue(element(app, "history.week").waitForExistence(timeout: 5))
        let tagRows = app.descendants(matching: .any).matching(identifier: "history.week-tag")
        XCTAssertEqual(tagRows.count, 0)
        XCTAssertTrue(element(app, "history.session").isHittable, "The week pushed the sessions off the screen")
        tap(app, "history.week-by-tag")
        // The tagged session counts toward both of its tags, each marked as a piece or a skill.
        XCTAssertTrue(tagRows.firstMatch.waitForExistence(timeout: 5))
        func shownRows() -> [String] {
            (0..<tagRows.count).map {
                "\(tagRows.element(boundBy: $0).label): \(tagRows.element(boundBy: $0).value ?? "")"
            }
        }
        let expected = ["Ballade No. 1, Piece: 25 minutes", "Scales, Skill: 25 minutes", "Untagged: 1 minute"]
        XCTAssertEqual(shownRows(), expected)
        let nameStarts = (0..<tagRows.count).map { tagRows.element(boundBy: $0).staticTexts.firstMatch.frame.minX }
        XCTAssertEqual(Set(nameStarts).count, 1, "The names don't line up: \(nameStarts)")
        attachScreenshot(of: app, named: "History, this week by tag")
        // It stays open.
        kill(app)
        app = launch(at: start + 27 * 60)
        openHistory(app)
        XCTAssertTrue(tagRows.firstMatch.waitForExistence(timeout: 5), "The breakdown closed after a relaunch")
        XCTAssertEqual(shownRows(), expected)
        // Open, it pushes the sessions further down.
        app.swipeUp()
        XCTAssertTrue(element(app, "history.day").waitForExistence(timeout: 5))
        let sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.matching(NSPredicate(format: "label ENDSWITH 'Ballade No. 1, Scales'")).count, 1)
        XCTAssertEqual(sessions.matching(NSPredicate(format: "label ENDSWITH 'Untagged'")).count, 1)
        attachScreenshot(of: app, named: "History, tagged and untagged")
    }

    /// TAG-1: part of an archived piece's name finds it, marked Archived, above the button that would add a
    /// near-duplicate.
    @MainActor
    func testAnArchivedPieceIsFoundByPartOfItsName() throws {
        let app = launch(at: start, reset: true)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Ballade No. 1")
        tap(app, "tags.add-piece")
        // Untagged, so archiving takes it off the list.
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        tap(app, "Ballade No. 1")
        XCTAssertTrue(
            app.buttons["Ballade No. 1"].wait(for: \.isSelected, toEqual: false, timeout: 5), "It stayed tagged")
        revealSwipeActions(app.buttons["Ballade No. 1"])
        tap(app, "Archive")
        XCTAssertTrue(app.buttons["Ballade No. 1"].waitForNonExistence(timeout: 5), "Archiving didn't hide it")

        search.tap()
        search.typeText("Ballade")
        let archived = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Ballade No. 1' AND label CONTAINS 'Archived'")
        )
        .firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: 5), "Part of its name didn't find it")
        XCTAssertLessThan(archived.frame.midY, element(app, "tags.add-piece").frame.midY, "It wasn't above Add")
        attachScreenshot(of: app, named: "Tag picker, archived piece found")
    }

    /// TAG-3: a piece is given a composer and a target tempo from the tag picker, which shows them under its
    /// name. A tempo out of range can't be saved, and the details are still there after a relaunch.
    @MainActor
    func testPieceDetails() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Ballade No. 1")
        tap(app, "tags.add-piece")
        attachScreenshot(of: app, named: "Tag picker, piece added")
        revealSwipeActions(app.buttons["Ballade No. 1"])
        attachScreenshot(of: app, named: "Tag picker, piece swiped")
        tap(app, "tags.details")
        let composer = app.textFields["details.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "The details didn't open")
        composer.tap()
        composer.typeText("Chopin")
        let tempo = app.textFields["details.tempo"]
        tempo.tap()
        tempo.typeText("400")
        let save = app.buttons["details.save"]
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: false, timeout: 5), "A tempo out of range could be saved")
        attachScreenshot(of: app, named: "Piece details, tempo out of range")
        tempo.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "72")
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 5), "72 couldn't be saved")
        attachScreenshot(of: app, named: "Piece details")
        save.tap()
        XCTAssertTrue(composer.waitForNonExistence(timeout: 5), "The details didn't close")
        let withDetails = NSPredicate(format: "label BEGINSWITH 'Ballade No. 1' AND label CONTAINS 'Chopin, 72 BPM'")
        var ballade = app.buttons.matching(withDetails).firstMatch
        XCTAssertTrue(ballade.waitForExistence(timeout: 5), "No details under the name")
        attachScreenshot(of: app, named: "Tag picker, piece with details")
        kill(app)

        app = launch(at: start + 60)
        tap(app, "practice.tags")
        ballade = app.buttons.matching(withDetails).firstMatch
        XCTAssertTrue(ballade.waitForExistence(timeout: 5), "No details after a relaunch")
        revealSwipeActions(ballade)
        tap(app, "tags.details")
        XCTAssertTrue(app.textFields["details.composer"].waitForExistence(timeout: 5), "The details didn't open")
        XCTAssertEqual(app.textFields["details.composer"].value as? String, "Chopin")
        XCTAssertEqual(app.textFields["details.tempo"].value as? String, "72")
    }

    /// SYN-1: a piece iCloud brings from another device shows in the open tag picker, with no relaunch. A Debug
    /// switch saves it through a second store on the same file, as an iCloud import does, 25 seconds after
    /// launch, which leaves a slow CI iPad time to open the picker first. The picker is checked without it first,
    /// so a slow launch fails here rather than passing on the picker's own load as it opens.
    @MainActor
    func testAPieceFromAnotherDeviceShowsWhileOpen() throws {
        let app = launch(at: start, reset: true, syncArrivesSeconds: 25)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        XCTAssertTrue(app.buttons["tags.done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Synced piece"].exists, "The piece arrived before the picker opened")
        XCTAssertTrue(app.buttons["Synced piece"].waitForExistence(timeout: 45), "The piece didn't show")
    }

    /// SYN-1: a session iCloud brings from another device, tagged with a piece that came before it, shows in the
    /// open History. The same switch saves the piece after 20 seconds and the session after 40, so History opens
    /// first with nothing to wait for but the launch. Its own launch, so a slow tag picker can't use up the time.
    @MainActor
    func testASessionFromAnotherDeviceShowsWhileOpen() throws {
        let app = launch(at: start, reset: true, syncArrivesSeconds: 20)
        openHistory(app)
        let synced = app.descendants(matching: .any).matching(identifier: "history.session")
            .matching(NSPredicate(format: "label ENDSWITH 'Synced piece'")).firstMatch
        XCTAssertFalse(synced.exists, "The session arrived before History opened")
        XCTAssertTrue(synced.waitForExistence(timeout: 60), "The session didn't show")
        attachScreenshot(of: app, named: "History, with a session from another device")
    }

    /// SYN-1, #107: an edit saved after another device deleted the session says so, and the editor stays open with
    /// what was typed, so it can be copied.
    @MainActor
    func testSavingASessionDeletedElsewhereSaysSo() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        kill(app)
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        openHistory(app)
        let session = element(app, "history.session")
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.tap()
        let note = element(app, "editor.note")
        note.tap()
        note.typeText("Coda")

        let deleted = XCTDarwinNotificationExpectation(
            notificationName: "com.edkarabinus.Pianism.delete-elsewhere-done")
        notify_post("com.edkarabinus.Pianism.delete-elsewhere")
        wait(for: [deleted], timeout: 30)
        tap(app, "editor.save")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "Saving didn't say it failed")
        XCTAssertTrue(app.alerts.staticTexts["This session was deleted on another device."].exists, "It didn't say why")
        attachScreenshot(of: app, named: "Saving a session deleted on another device")
        app.alerts.buttons.firstMatch.tap()
        XCTAssertTrue(element(app, "editor.refusal").waitForExistence(timeout: 5), "The editor didn't stay open")
        attachScreenshot(of: app, named: "After OK")
        XCTAssertFalse(app.buttons["editor.save"].isEnabled, "Save is still offered")
        XCTAssertEqual(element(app, "editor.note").value as? String, "Coda", "What was typed is gone")
    }

    /// SES-5, TAG-2: a finished session is tagged, ended 5 minutes earlier and given a note from History,
    /// which shows the tags and the shorter practice time once the edit is saved. It's all stored, so
    /// it's still there after the app is killed and relaunched.
    @MainActor
    func testEditAFinishedSession() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        kill(app)
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
        kill(app)

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
        kill(app)
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
        kill(app)

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
        kill(app)
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
        kill(app)

        // The real 5 seconds.
        app = launch(at: start + 30 * 60)
        openHistory(app)
        deleteBySwipe(app)
        XCTAssertTrue(app.buttons["history.undo"].waitForNonExistence(timeout: 15), "Undo outlasted its 5 seconds")
        kill(app)

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
        kill(app)
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        tap(app, "practice.start")
        kill(app)
        // A long Undo, so only a kill, leaving History or leaving the app can end it.
        app = launch(at: start + 50 * 60, undoSeconds: 60)
        tap(app, "practice.stop")
        openHistory(app)
        deleteBySwipe(app)
        kill(app)

        app = launch(at: start + 51 * 60, undoSeconds: 60)
        openHistory(app)
        var sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertTrue(sessions.element(boundBy: 1).waitForExistence(timeout: 5), "A kill didn't keep the session")
        deleteBySwipe(app)
        openPractice(app)
        kill(app)

        app = launch(at: start + 52 * 60, undoSeconds: 60)
        openHistory(app)
        sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertTrue(sessions.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(sessions.count, 1, "Leaving History didn't save the deletion")
        deleteBySwipe(app)
        goHome()
        kill(app)

        app = launch(at: start + 53 * 60)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5), "Leaving the app didn't save it")
    }

    /// SYN-1: on a simulator signed out of iCloud, as every test simulator must be, History says its history isn't
    /// syncing, whether it's empty or has practice. This checks that test simulators stay signed out
    /// (docs/device-checklist.md).
    @MainActor
    func testHistorySaysWhenICloudIsntSyncing() throws {
        var app = launch(at: start, reset: true)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").waitForExistence(timeout: 5))
        let notice = element(app, "history.not-syncing")
        XCTAssertTrue(
            notice.waitForExistence(timeout: 10),
            "No notice: is this simulator signed into iCloud? Test simulators must stay signed out (docs/device-checklist.md)."
        )
        XCTAssertTrue(
            notice.label.contains(
                "Your history isn't syncing. In Settings, sign in to iCloud and turn it on for Pianism."),
            "It said \(notice.label)")
        attachScreenshot(of: app, named: "History, not syncing")

        openPractice(app)
        tap(app, "practice.start")
        kill(app)

        // A minute later, so the session is long enough to keep (SES-1).
        app = launch(at: start + 60)
        tap(app, "practice.stop")
        openHistory(app)
        XCTAssertTrue(element(app, "history.session").waitForExistence(timeout: 5))
        XCTAssertTrue(
            element(app, "history.not-syncing").waitForExistence(timeout: 10), "The notice went once there was practice"
        )
        attachScreenshot(of: app, named: "History, one session, not syncing")
    }

    /// SYN-1: at the largest text size, empty History scrolls, so the not-syncing notice can be read in full above
    /// the tab bar on iPhone, or the bottom of the screen on iPad, whose tab bar is at the top.
    @MainActor
    func testNotSyncingNoticeScrollsAtLargestText() throws {
        let app = launch(at: start, reset: true, textSize: "AccessibilityXXXL")
        openHistory(app)
        let notice = element(app, "history.not-syncing")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "No notice")
        app.swipeUp()
        let tabBar = app.tabBars.firstMatch
        let screen = app.windows.firstMatch.frame
        let bottom = tabBar.exists && tabBar.frame.minY > screen.midY ? tabBar.frame.minY : screen.maxY
        XCTAssertLessThanOrEqual(notice.frame.maxY, bottom, "The notice stays under the tab bar or off screen")
        attachScreenshot(of: app, named: "History, not syncing, largest text")
    }

    /// HIS-1, ADR 0006: saved sessions this version can't show, such as ones a newer version wrote, are counted
    /// with a request to update, rather than left out silently or called no practice.
    @MainActor
    func testSessionsThatCantBeShownAreCounted() throws {
        let app = launch(at: start, reset: true, unshowableSessions: 2)
        openHistory(app)
        let notice = element(app, "history.unshowable")
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "It didn't count them")
        XCTAssertTrue(
            notice.label.contains("2 sessions couldn't be shown. Try updating Pianism."), "It said \(notice.label)")
        XCTAssertFalse(element(app, "history.empty").exists, "It said there's no practice")
        attachScreenshot(of: app, named: "Sessions that can't be shown")
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
        openPractice(app)
        // Each stopped a minute after it started, in a later launch, so it's long enough to keep (SES-1).
        for minute in 1...2 {
            tap(app, "practice.start")
            kill(app)
            app = launch(at: start + TimeInterval(minute * 60), breakHistory: true)
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
        kill(app)

        app = launch(at: start + 60 * 60)
        XCTAssertFalse(app.staticTexts["practice.waiting"].exists)
        openHistory(app)
        XCTAssertTrue(element(app, "history.day").waitForExistence(timeout: 5))
        let saved = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.matching(notSavedYet).count, 0)
    }

    /// GLN-1: the Live Activity appears in the Dynamic Island as the session starts, as one activity only, which a
    /// relaunch keeps rather than doubles; it leaves as the session stops in the app, for a timer session and a MIDI
    /// one alike (device rows L1 and L6). The island is read from the Home Screen's accessibility tree, as the
    /// notification is, which only iPhones have. The real clock, as the island counts real time.
    @MainActor
    func testTheLiveActivityShowsWhileASessionRunsAndGoesWhenItStops() throws {
        try skipUnlessSoaking("the island is read on the real clock")
        try skipWithoutAnIsland()
        var app = launch(at: nil, reset: true)
        tap(app, "practice.start")
        goHome()
        XCTAssertTrue(liveActivities.firstMatch.waitForExistence(timeout: 10), "No activity on the Home Screen")
        XCTAssertEqual(liveActivities.count, 1)
        attachScreenshot(of: springboard, named: "The Live Activity in the island")
        kill(app)
        XCTAssertTrue(liveActivities.firstMatch.waitForExistence(timeout: 10), "The activity went with the app")

        app = launch(at: nil)
        goHome()
        XCTAssertTrue(liveActivities.firstMatch.waitForExistence(timeout: 10), "The activity went at the relaunch")
        XCTAssertEqual(liveActivities.count, 1, "The relaunch started another activity")
        app.activate()
        tap(app, "practice.stop")
        goHome()
        // Not "gone within 10 s": the Home Screen may not have drawn yet, so that could pass on an empty first look.
        XCTAssertFalse(liveActivities.firstMatch.waitForExistence(timeout: 5), "The activity stayed after Stop")
        kill(app)

        app = launch(at: nil, midiNotes: "0,0,0")
        XCTAssertTrue(app.buttons["practice.stop"].waitForExistence(timeout: 10), "The notes didn't start a session")
        goHome()
        XCTAssertTrue(liveActivities.firstMatch.waitForExistence(timeout: 10), "No activity for a MIDI session")
        app.activate()
        tap(app, "practice.stop")
        goHome()
        // Not "gone within 10 s": the Home Screen may not have drawn yet, so that could pass on an empty first look.
        XCTAssertFalse(liveActivities.firstMatch.waitForExistence(timeout: 5), "The activity stayed after Stop")
    }

    /// GLN-1, SES-4: with the app killed, the island's clock stops at the cap by itself, as its range ends there; the
    /// next launch ends the session at the cap and the activity goes (device row L5). 45 s on the real clock: the
    /// app has to be killed before the cap, or its own tick ends the session, and a slow simulator takes 10 s or
    /// more from Start to the Home Screen.
    @MainActor
    func testTheLiveActivityStopsAtTheCapByItself() throws {
        try skipUnlessSoaking("the island's clock runs on real time")
        try skipWithoutAnIsland()
        var app = launch(at: nil, reset: true, capSeconds: 45)
        tap(app, "practice.start")
        goHome()
        kill(app)
        XCTAssertTrue(liveActivities.firstMatch.waitForExistence(timeout: 10), "No activity on the Home Screen")
        // The clock is the text inside the activity: the activity's own label is set as its content changes, so it
        // reads the time of the last update. Past the cap, with a margin for a slow island, then a second read to
        // show the clock stopped.
        let clock = liveActivities.firstMatch.staticTexts.firstMatch
        XCTAssertTrue(
            clock.wait(for: \.label, toEqual: "0:45", timeout: 60), "The clock didn't reach the cap: \(clock.label)")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(clock.label, "0:45", "The clock counted past the cap")
        attachScreenshot(of: springboard, named: "The island stopped at the cap")

        app = launch(at: nil, capSeconds: 45)
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertEqual(
            text(app, "practice.capped"),
            "Pianism stopped your session at 45 seconds of practice, in case the timer was left running.")
        goHome()
        XCTAssertFalse(liveActivities.firstMatch.waitForExistence(timeout: 5), "The activity stayed past the cap")
    }

    /// MIDI-1, MIDI-2: a piano the system announces is heard through the app's own CoreMIDI adapter, not the test
    /// script: Practice names it, three notes start a session, and it reads "Connect a piano" again once the piano
    /// goes (device rows M1, M3 and P1, with a piano in software).
    @MainActor
    func testAPianoTheSystemAnnouncesIsHeard() throws {
        try skipUnlessSoaking("it needs the simulator's MIDI server")
        let piano = try VirtualPiano(named: "Test piano")
        // A failure stops the test before any deinit, so the piano goes in teardown, or the retry would hear it.
        addTeardownBlock { @MainActor in piano.remove() }
        let app = launch(at: start, reset: true)
        let pianos = app.buttons["practice.pianos"]
        XCTAssertTrue(
            pianos.wait(for: \.label, toEqual: "Test piano connected", timeout: 10), "Practice says \(pianos.label)")
        piano.send([0x2090_3C40, 0x2090_3E40, 0x2090_4040])  // three notes in one packet
        XCTAssertTrue(app.buttons["practice.stop"].waitForExistence(timeout: 5), "The notes didn't start a session")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        attachScreenshot(of: app, named: "Practicing from a piano the system announced")

        piano.remove()
        XCTAssertTrue(
            pianos.wait(for: \.label, toEqual: "Connect a piano", timeout: 10),
            "Practice still names the piano that went")
    }

    /// NFR-3: XCTest's accessibility audit finds nothing to report on Practice, ready, running and paused, on the
    /// piano sheet, and on History with a session: every element described, text that scales and isn't clipped,
    /// targets big enough to hit.
    @MainActor
    func testTheScreensPassTheAccessibilityAudit() throws {
        continueAfterFailure = true  // every screen reports, not just the first with an issue
        executionTimeAllowance = 5 * 60  // about 80 s on CI; one iPad (iOS 26) audit hung until the 15-min default
        var app = launch(at: start, reset: true)
        try audit(app, "Practice, ready")
        tap(app, "practice.pianos")
        XCTAssertTrue(app.buttons["pianos.done"].waitForExistence(timeout: 5), "The piano sheet didn't open")
        try audit(app, "Connect a piano", sheet: true)
        tap(app, "pianos.done")
        tap(app, "practice.start")
        try audit(app, "Practice, running")
        tap(app, "practice.pause")
        try audit(app, "Practice, paused")
        tap(app, "practice.resume")
        kill(app)

        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        openHistory(app)
        XCTAssertTrue(element(app, "history.session").waitForExistence(timeout: 5), "No session in History")
        try audit(app, "History")
    }

    // Only Xcode 27's SDK (Swift 6.4) has the VoiceOver service; Xcode 26.6 (Swift 6.3) builds the iOS 26 jobs.
    #if compiler(>=6.4)
        /// NFR-3: VoiceOver, moving through Practice with a session running, says the commands by name: Pause and Stop
        /// (device row L7's app half). The service is new in iOS 27, so iOS 26 skips.
        @MainActor
        func testVoiceOverSaysTheCommands() throws {
            try skipUnlessSoaking("VoiceOver's service is new in iOS 27")
            guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver can't be driven before iOS 27") }
            let app = launch(at: start, reset: true)
            tap(app, "practice.start")
            let voiceOver = XCUIDevice.shared.voiceOverService
            try voiceOver.enable()
            // Off in teardown, which runs after a failure too, or every later test would run under VoiceOver.
            addTeardownBlock { @MainActor in try? voiceOver.disable() }
            var said: [String] = []
            func heard(_ command: String) -> Bool { said.contains { $0.hasPrefix(command) } }
            while said.count < 30, !(heard("Pause") && heard("Stop")) {
                said.append(try voiceOver.moveForward().utterance)
            }
            XCTAssertTrue(heard("Pause") && heard("Stop"), "VoiceOver said \(said)")
        }
    #endif

    /// Runs the audit on the screen `name`, every type iOS supports, and fails the test once with all it found of
    /// the types that hold today: every element described and detected, with its traits, and big enough to hit.
    /// Contrast, Dynamic Type and clipping are noted in the results instead, as what the audit finds there is a
    /// design call (#165), not a test's; the failing set grows as each is decided. An iPad shows a `sheet` in the
    /// middle of the screen with the dimmed screen still readable around it; that text is out of VoiceOver's reach
    /// while the sheet is up, by design, and the audit reports it as inaccessible, so a sheet's audit notes element
    /// detection there instead.
    @MainActor
    private func audit(_ app: XCUIApplication, _ name: String, sheet: Bool = false) throws {
        var failing: XCUIAccessibilityAuditType = [
            .hitRegion, .sufficientElementDescription, .elementDetection, .trait,
        ]
        if sheet, UIDevice.current.userInterfaceIdiom == .pad { failing.remove(.elementDetection) }
        var found: [String] = []
        var noted: [String] = []
        try XCTContext.runActivity(named: "Audit \(name)") { _ in
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' \($0.frame)" } ?? "?"
                let line = "\(issue.compactDescription): \(element)"
                if failing.contains(issue.auditType) {
                    found.append(line)
                } else {
                    noted.append(line)
                }
                return true
            }
        }
        if !noted.isEmpty {
            XCTContext.runActivity(named: "\(name), noted: \(noted.joined(separator: "; "))") { _ in }
        }
        XCTAssertTrue(found.isEmpty, "\(name) has accessibility issues: \(found.joined(separator: "; "))")
    }

    /// Skips on an iPad, which has no Dynamic Island to show the activity on the Home Screen.
    @MainActor
    private func skipWithoutAnIsland() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "The activity shows in an iPhone's island only")
    }

    /// The Home Screen, where the system shows notifications.
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// The "Still practicing?" notification, as the Home Screen shows it.
    @MainActor private var notification: XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Pianism is still timing your session.'")).firstMatch
    }

    /// The session's Live Activities as the Dynamic Island shows them on the Home Screen: the compact form reads
    /// "Piano, 0:12", the piano symbol then the clock.
    @MainActor private var liveActivities: XCUIElementQuery {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Piano, '"))
    }

    /// Goes to the Home Screen and checks the app left the screen. iPhone swipes up from the bottom edge, as a person
    /// does: on the iPhone Duo simulator (iOS 27.1), XCUIDevice's Home button press takes 5 s and leaves the app in
    /// front. iPad presses Home, as a swipe there can open the app switcher instead. The swipe assumes a Face ID
    /// iPhone: on one with a Home button, it would open Control Center. A busy CI simulator can take over 5 s to
    /// report the app in the background, or miss the gesture, so it waits 10 s and tries once more.
    @MainActor
    private func goHome() {
        let app = XCUIApplication()
        for _ in 0..<2 {
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCUIDevice.shared.press(.home)
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.999)).press(
                    forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)),
                    withVelocity: .fast, thenHoldForDuration: 0)
            }
            if app.wait(for: .runningBackground, timeout: 10) { return }
        }
        XCTFail("The app stayed in front after leaving it twice")
    }

    /// Leaves the app and answers its "Still practicing?" notification with the button titled `answer`. The system
    /// shows no notification for the app in front, and takes up to about 20 s to show it after the nudge.
    @MainActor
    private func answerNotification(with answer: String) {
        goHome()
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

    /// Asserts Stop is below the button `identifier` names, or beside it at the same height, as a name broken onto a
    /// second line makes its button taller, and that both are above the tab bar.
    @MainActor
    private func assertCommandsFit(_ app: XCUIApplication, beside identifier: String, at size: String) {
        let other = element(app, identifier).frame
        let stop = element(app, "practice.stop").frame
        if stop.minY < other.maxY {
            XCTAssertEqual(stop.height, other.height, accuracy: 1, "A name broke beside Stop at \(size)")
        }
        let tabBar = app.tabBars.firstMatch
        let screen = app.windows.firstMatch.frame
        let bottom = tabBar.exists && tabBar.frame.minY > screen.midY ? tabBar.frame.minY : screen.maxY
        XCTAssertLessThanOrEqual(max(stop.maxY, other.maxY), bottom, "A button is under the tab bar at \(size)")
    }

    /// Asserts the session ended itself at 4 hours and the banner says so (SES-4).
    @MainActor
    private func assertStoppedAtTheCap(_ app: XCUIApplication) {
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        XCTAssertEqual(
            text(app, "practice.capped"),
            "Pianism stopped your session at 4 hours of practice, in case the timer was left running.")
        attachScreenshot(of: app, named: "Stopped at the cap")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Launches the app with its clock fixed at `now`, or on the real clock if `nil`.
    @MainActor
    private func launch(
        at now: TimeInterval?, reset: Bool = false, breakHistory: Bool = false, unshowableSessions: Int? = nil,
        undoSeconds: Int? = nil, nudgeSeconds: Int? = nil, capSeconds: Int? = nil, offerNudges: Bool = false,
        textSize: String? = nil, syncArrivesSeconds: Int? = nil, midiNotes: String? = nil, midiPauseSeconds: Int? = nil,
        midiSaveSeconds: Int? = nil, midiMinimumSeconds: Int? = nil, midiPiano: String? = nil, intent: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // With iCloud sync on, as Release will have it, on a simulator signed out of iCloud: the app must
        // work as before, with no sign-in prompt (SYN-1).
        app.launchEnvironment["PIANISM_SYNC"] = "1"
        // Stops Xcode mirroring the app's unified log to stderr (it stays readable with `log show`). Each UI query makes
        // the accessibility runtime log dozens of lines, and when stderr drains slowly, queries time out ("Timed out
        // while evaluating UI query").
        app.launchEnvironment["OS_ACTIVITY_DT_MODE"] = "NO"
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory\(textSize)"]
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
        if offerNudges {
            app.launchEnvironment["PIANISM_OFFER_NUDGES"] = "1"
        }
        if reset {
            app.launchEnvironment["PIANISM_RESET"] = "1"
        }
        if breakHistory {
            app.launchEnvironment["PIANISM_BREAK_HISTORY"] = "1"
        }
        if let syncArrivesSeconds {
            app.launchEnvironment["PIANISM_SYNC_ARRIVES_SECONDS"] = String(syncArrivesSeconds)
        }
        if let unshowableSessions {
            app.launchEnvironment["PIANISM_UNSHOWABLE_SESSIONS"] = String(unshowableSessions)
        }
        if let midiNotes {
            app.launchEnvironment["PIANISM_MIDI_NOTES"] = midiNotes
        }
        if let midiPiano {
            app.launchEnvironment["PIANISM_MIDI_PIANO"] = midiPiano
        }
        if let midiPauseSeconds {
            app.launchEnvironment["PIANISM_MIDI_PAUSE_SECONDS"] = String(midiPauseSeconds)
        }
        if let midiSaveSeconds {
            app.launchEnvironment["PIANISM_MIDI_SAVE_SECONDS"] = String(midiSaveSeconds)
        }
        if let midiMinimumSeconds {
            app.launchEnvironment["PIANISM_MIDI_MINIMUM_SECONDS"] = String(midiMinimumSeconds)
        }
        if let intent {
            app.launchEnvironment["PIANISM_INTENT"] = intent
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

    /// Opens Practice from History, tapping again if the tab bar swallowed the tap, as iOS 26's sometimes does
    /// (#80): before a kill, a swallowed tap lost the deletion that leaving History saves.
    @MainActor
    private func openPractice(_ app: XCUIApplication) {
        let tab = app.buttons["Practice"].firstMatch
        let history = app.navigationBars["History"]
        tab.tap()
        if !history.waitForNonExistence(timeout: 3) { tab.tap() }
        XCTAssertTrue(app.staticTexts["practice.status"].waitForExistence(timeout: 5), "Practice didn't open")
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
        revealSwipeActions(sessions.firstMatch)
        tap(app, "history.delete")
        confirmDelete(app)
        XCTAssertTrue(sessions.element(boundBy: count - 1).waitForNonExistence(timeout: 5))
    }

    /// Shows `row`'s swipe actions with a press, then a drag halfway across, rather than a full swipe. A busy
    /// simulator can read swipeLeft as a tap, which would open or toggle the row instead.
    @MainActor
    private func revealSwipeActions(_ row: XCUIElement) {
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No row to swipe")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
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

/// A piano in software: a MIDI source in the simulator, which the app hears as it would a piano on a cable.
@MainActor
private final class VirtualPiano {
    private var client = MIDIClientRef()
    private var endpoint = MIDIEndpointRef()

    /// Throws when CoreMIDI refuses, as it does with kMIDINotPermitted (-10844) for a process without the audio
    /// background mode, which `make test-app` gives the test runner.
    init(named name: String) throws {
        for (call, status) in [
            ("MIDIClientCreateWithBlock", MIDIClientCreateWithBlock(name as CFString, &client, nil)),
            ("MIDISourceCreateWithProtocol", MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &endpoint)),
        ] where status != noErr {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: call])
        }
    }

    /// Unplugs the piano, once; a second call does nothing.
    func remove() {
        guard endpoint != 0 else { return }
        MIDIEndpointDispose(endpoint)
        MIDIClientDispose(client)
        endpoint = 0
    }

    /// Sends these Universal MIDI Packet words as one packet.
    func send(_ words: [UInt32]) {
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, words.count, words)
        MIDIReceivedEventList(endpoint, &list)
    }
}
