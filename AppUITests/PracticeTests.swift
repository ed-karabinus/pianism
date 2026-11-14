import CoreMIDI
import StoreKitTest
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
        XCTAssertFalse(element(app, "practice.pianos").exists, "Practice names a piano with none connected")  // MIDI-2

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
        // The clock is fixed, so it had no practice: under 10 s, it isn't saved (SES-1).
        XCTAssertFalse(app.staticTexts["practice.last-session"].exists, "A session under 10 s was kept")
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").appears(within: 5), "A session under 10 s was kept")
    }

    /// NFR-10: on the real clock, the shown time advances second by second while a session runs and holds
    /// while it is paused: the timeline that draws the time ticks only while the session counts.
    @MainActor
    func testPracticeTimeAdvancesWhileRunningAndHoldsWhilePaused() throws {
        let app = launch(at: nil, reset: true)
        tap(app, "practice.start")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")

        let time = app.staticTexts["practice.elapsed"]
        XCTAssertTrue(time.appears(within: 5), "No practice time")
        let started = elapsed(app)
        let moved = expectation(
            for: NSPredicate(format: "value != %@", started ?? ""), evaluatedWith: time)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, "The running time didn't advance")
        attachScreenshot(of: app, named: "Practicing, counting")

        tap(app, "practice.pause")
        XCTAssertEqual(text(app, "practice.status"), "Paused")
        let held = elapsed(app)
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(elapsed(app), held, "The paused time moved")
        attachScreenshot(of: app, named: "Paused, time held")
    }

    /// MIDI-1: three notes start a session, and a Stop with under a minute of played time discards it and says so.
    /// The simulator has no piano, so the app plays a chord at launch, on the fixed clock.
    @MainActor
    func testThreeNotesStartASessionAndAShortStopDiscardsIt() throws {
        let app = launch(at: start, reset: true, midiNotes: "0,0,0", midiPiano: "MIDI KEYBOARD")
        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 10), "The notes didn't start a session")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertEqual(text(app, "practice.pianos"), "MIDI KEYBOARD connected")  // MIDI-2
        attachScreenshot(of: app, named: "A MIDI session, with the piano connected")

        tap(app, "practice.stop")

        XCTAssertTrue(app.staticTexts["practice.too-short"].appears(within: 5), "It didn't say so")
        XCTAssertEqual(text(app, "practice.too-short"), "Not saved: under a minute of playing")
        XCTAssertEqual(text(app, "practice.not-saved-pop-up"), "Not saved: under a minute of playing")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")
        attachScreenshot(of: app, named: "Not saved, a piano's session")
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").appears(within: 5), "A MIDI session under 1 min was kept")
    }

    /// SES-1: a tapped session stopped under 10 s isn't saved, which a pop-up says for 4 s and a line under Start
    /// until the next start, so it doesn't look like the app lost it.
    @MainActor
    func testAShortTappedSessionSaysItWasntSaved() throws {
        // Given a session started by tapping
        let app = launch(at: start, reset: true)
        tap(app, "practice.start")
        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 5), "Start didn't start")

        // When it's stopped at once
        tap(app, "practice.stop")

        // Then a pop-up and the line say it wasn't saved, and the pop-up goes after a few seconds
        let popUp = app.staticTexts["practice.not-saved-pop-up"]
        XCTAssertTrue(popUp.appears(within: 5), "No pop-up")
        XCTAssertEqual(popUp.label, "Not saved: under 10 seconds")
        XCTAssertEqual(text(app, "practice.too-short"), "Not saved: under 10 seconds")
        attachScreenshot(of: app, named: "Not saved, a tapped session")
        XCTAssertTrue(popUp.disappears(within: 8), "The pop-up stayed")
        XCTAssertEqual(text(app, "practice.too-short"), "Not saved: under 10 seconds", "The line went too")
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").appears(within: 5), "A session under 10 s was kept")
    }

    /// MIDI-1: a silence pauses a MIDI session at its last note, and a longer one saves it 5 s after that note, with no
    /// tap. On the real clock, with the timeouts shortened to 10 and 20 s and the shortest session kept to 2 s.
    @MainActor
    func testPlayingPausesAfterSilenceAndSavesItself() throws {
        let app = launch(
            at: nil, reset: true, midiNotes: "0.5,0.8,1.1,2.5,4", midiPauseSeconds: 10, midiSaveSeconds: 20,
            midiMinimumSeconds: 2)
        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 10), "The notes didn't start a session")

        let paused = app.staticTexts["practice.status"].wait(
            for: \.label, toEqual: "Paused at your last note", timeout: 30)
        XCTAssertTrue(paused, "The silence didn't pause it")
        attachScreenshot(of: app, named: "Paused at your last note")

        // Played from the first note to the last, 3.5 s; the 5 s after the last note were a pause.
        XCTAssertTrue(app.staticTexts["practice.last-session"].appears(within: 90), "It didn't save itself")
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
        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 10), "The notes didn't start a session")
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
        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 10), "The notes didn't start a session")
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
        XCTAssertTrue(app.staticTexts["practice.last-session"].appears(within: 5), "No last session")
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 1:01")
        openHistory(app)
        let session = element(app, "history.session")
        XCTAssertTrue(session.appears(within: 5), "History doesn't have it")
        XCTAssertEqual(session.value as? String, "1 minute, 1 second")
    }

    /// HIS-1, HIS-2, SES-5: a session across midnight shows on both days with each day's minutes, and in the week once.
    /// Its editor shows all of it and says why, and deleting either row takes both.
    @MainActor
    func testASessionAcrossMidnightShowsOnBothDays() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: start))
        let midnight = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today)).timeIntervalSince1970
        var app = launch(at: midnight - 10 * 60, reset: true)
        tap(app, "practice.start")
        kill(app)

        app = launch(at: midnight + 20 * 60, undoSeconds: 60)
        tap(app, "practice.stop")
        openHistory(app)
        func match(_ format: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        }
        let todayRow = match("identifier == 'history.session' AND value == '20 minutes'")
        let yesterdayRow = match("identifier == 'history.session' AND value == '10 minutes'")
        XCTAssertTrue(todayRow.appears(within: 5), "No row with today's minutes")
        XCTAssertEqual(element(app, "history.week").value as? String, "30 minutes")
        XCTAssertTrue(match("identifier == 'history.day' AND label == 'Today' AND value == '20 minutes'").exists)
        // On a small screen the week can push the second day off, and a list doesn't build rows off screen.
        if !yesterdayRow.appears(within: 2) { app.swipeUp() }
        XCTAssertTrue(yesterdayRow.appears(within: 5), "No row with yesterday's minutes")
        XCTAssertTrue(match("identifier == 'history.day' AND label == 'Yesterday' AND value == '10 minutes'").exists)
        attachScreenshot(of: app, named: "History, a session across midnight")

        todayRow.tap()
        XCTAssertTrue(app.navigationBars["Edit session"].appears(within: 5), "The editor didn't open")
        XCTAssertTrue(match("label == 'Practice time' AND value == '30 minutes'").exists, "It isn't all of the time")
        XCTAssertTrue(element(app, "editor.spans-days").appears(within: 5), "The editor doesn't say why")
        attachScreenshot(of: app, named: "Editor, a session across midnight")
        tap(app, "editor.cancel")
        XCTAssertTrue(app.navigationBars["Edit session"].disappears(within: 5), "Cancel asked to discard")

        revealSwipeActions(yesterdayRow)
        tap(app, "history.delete")
        XCTAssertTrue(app.staticTexts["It's listed on two days. Both go."].appears(within: 5), "No note")
        confirmDelete(app)
        XCTAssertTrue(yesterdayRow.disappears(within: 5), "Yesterday's row is still there")
        XCTAssertFalse(todayRow.exists, "Today's row is still there")
        tap(app, "history.undo")
        XCTAssertTrue(todayRow.appears(within: 5), "Undo didn't bring today's row back")
        if !yesterdayRow.appears(within: 2) { app.swipeUp() }
        XCTAssertTrue(yesterdayRow.appears(within: 5), "Undo didn't bring yesterday's row back")
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
        XCTAssertTrue(app.navigationBars["Edit session"].appears(within: 5), "The editor didn't open")
        attachScreenshot(of: app, named: "Editing the session the cap stopped")
        tap(app, "editor.cancel")
        XCTAssertTrue(app.navigationBars["History"].appears(within: 5))
        XCTAssertEqual(element(app, "history.session").value as? String, "4 hours")

        openPractice(app)
        XCTAssertTrue(app.staticTexts["practice.last-session"].appears(within: 5))
        XCTAssertEqual(text(app, "practice.last-session"), "Last session: 4:00:00")
        XCTAssertFalse(app.staticTexts["practice.capped"].exists, "Edit should hide the banner")
    }

    /// SET-1: the nudge and the cap come from Settings. Set to 30 minutes and 1 hour there, a session asks at 30
    /// minutes and stops at 1 hour. The cap can't change while the session runs, and once it's stopped, a new cap
    /// leaves the banner naming the one that stopped it.
    @MainActor
    func testTheNudgeAndCapComeFromSettings() throws {
        var app = launch(at: start, reset: true)
        openSettings(app)
        XCTAssertEqual(chosen(app, "settings.nudge"), "1 hour, 30 minutes")
        XCTAssertEqual(chosen(app, "settings.cap"), "4 hours")
        choose(app, "settings.nudge", "30 minutes")
        choose(app, "settings.cap", "1 hour")
        attachScreenshot(of: app, named: "Settings, 30 minutes and 1 hour")
        openPractice(app)
        tap(app, "practice.start")
        openSettings(app)
        XCTAssertFalse(element(app, "settings.cap").isEnabled, "The cap could change with a session running")
        attachScreenshot(of: app, named: "Settings, a session running")
        kill(app)

        app = launch(at: start + 35 * 60)
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].appears(within: 5), "It didn't ask")
        kill(app)

        app = launch(at: start + 3 * 60 * 60)
        let stopped = "Pianism stopped your session at 1 hour of practice, in case the timer was left running."
        XCTAssertEqual(text(app, "practice.capped"), stopped)
        openSettings(app)
        XCTAssertEqual(chosen(app, "settings.nudge"), "30 minutes")
        choose(app, "settings.cap", "2 hours")
        openPractice(app)
        XCTAssertEqual(text(app, "practice.capped"), stopped, "The banner should name the cap that stopped it")
    }

    /// SET-1, MIDI-1: how a piano starts, pauses and saves a session comes from Settings. Set to 1 note there, one
    /// note starts a session after a relaunch, and the silences set are kept across it. The model tests check that the
    /// silences reach the detector.
    @MainActor
    func testOneNoteStartsASessionWhenSettingsSaySo() throws {
        var app = launch(at: start, reset: true)
        openSettings(app)
        XCTAssertEqual(chosen(app, "settings.startNotes"), "3")
        XCTAssertEqual(chosen(app, "settings.pauseAfter"), "1 minute")
        XCTAssertEqual(chosen(app, "settings.saveAfter"), "10 minutes")
        choose(app, "settings.startNotes", "1")
        choose(app, "settings.pauseAfter", "30 seconds")
        choose(app, "settings.saveAfter", "5 minutes")
        attachScreenshot(of: app, named: "Settings, 1 note, 30 seconds and 5 minutes")
        kill(app)

        app = launch(at: start + 60, midiNotes: "0")

        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 10), "One note didn't start a session")
        openSettings(app)
        XCTAssertEqual(chosen(app, "settings.pauseAfter"), "30 seconds")
        XCTAssertEqual(chosen(app, "settings.saveAfter"), "5 minutes")
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
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].appears(within: 5), "It didn't ask")
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

        XCTAssertTrue(app.staticTexts["practice.capped"].appears(within: 30), "It didn't stop at the cap")
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
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].appears(within: 5), "It didn't ask")
        attachScreenshot(of: app, named: "Still practicing?")
        XCTAssertEqual(app.buttons["practice.stopped-earlier"].label, "I stopped earlier")
        tap(app, "practice.stopped-earlier")
        XCTAssertTrue(app.datePickers["practice.stopped-at"].appears(within: 5), "No end to pick")
        XCTAssertEqual(app.buttons["practice.stop-at"].label, "Stop at this time")
        XCTAssertEqual(app.buttons["practice.still-practicing-yes"].label, "Still practicing")
        tap(app, "practice.still-practicing-yes")
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].disappears(within: 5))
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
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].appears(within: 5), "It didn't ask")
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
        XCTAssertTrue(app.buttons["practice.remind-me"].appears(within: 20), "It didn't offer it")
        XCTAssertEqual(
            app.buttons["practice.still-practicing-yes"].frame.minY, app.buttons["practice.stopped-earlier"].frame.minY,
            accuracy: 1, "The answers stacked")
    }

    /// SET-1: the daily reminder is off until it's turned on, which shows its time, 6:00 PM unless changed, and stays on
    /// after a relaunch. The notification itself is device row R1, as it comes at a time of day.
    @MainActor
    func testTheDailyReminderIsOffUntilTurnedOn() throws {
        var app = launch(at: nil, reset: true)
        openSettings(app)
        let reminder = app.switches["settings.daily-reminder"]
        // Below the fold on a shorter screen, as the overlap warning is.
        if !reminder.appears(within: 2) { app.swipeUp() }
        XCTAssertTrue(reminder.appears(within: 5), "No daily reminder in Settings")
        XCTAssertEqual(reminder.value as? String, "0", "The daily reminder isn't off by default")
        XCTAssertFalse(element(app, "settings.daily-reminder-time").exists, "A time shows with the reminder off")

        setNotificationSwitch(app, "settings.daily-reminder", on: true)
        XCTAssertTrue(element(app, "settings.daily-reminder-time").appears(within: 5), "No time")
        attachScreenshot(of: app, named: "Daily reminder, on")

        app.terminate()
        app = launch(at: nil, reset: false)
        openSettings(app)
        let kept = app.switches["settings.daily-reminder"]
        if !kept.appears(within: 2) { app.swipeUp() }
        XCTAssertTrue(kept.appears(within: 5))
        XCTAssertTrue(
            app.switches.matching(NSPredicate(format: "identifier == 'settings.daily-reminder' AND value == '1'"))
                .firstMatch.appears(within: 5), "The daily reminder wasn't kept")
    }

    /// SET-1: tapping the daily reminder opens Practice, though the app was left on Settings. On the real clock, as the
    /// system fires it, so this takes about two minutes.
    @MainActor
    func testTappingAReminderOpensPractice() throws {
        // Permission first, as the system asks once per install, and a banner needs it.
        var app = launch(at: nil, reset: true)
        openSettings(app)
        if !app.switches["settings.daily-reminder"].appears(within: 2) { app.swipeUp() }
        setNotificationSwitch(app, "settings.daily-reminder", on: true)
        app.terminate()

        // Reminders come on the minute. At least a minute away, as the app has to be away by then: the system shows
        // no banner for the app in front.
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = (try XCTUnwrap(now.hour) * 60 + XCTUnwrap(now.minute) + 2) % (24 * 60)
        app = launch(at: nil, reset: false, reminderMinute: minute)
        openSettings(app)
        goHome()

        let reminder = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Your piano'")).firstMatch
        XCTAssertTrue(reminder.appears(within: 180), "No reminder")
        reminder.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The reminder didn't open the app")
        XCTAssertTrue(app.buttons["practice.start"].appears(within: 10), "It didn't open Practice")
        XCTAssertFalse(app.navigationBars["Settings"].exists, "It stayed on Settings")
    }

    /// SET-1, SES-3: with "Notify me when I'm away" off in Settings, a session past the nudge sends no notification, and
    /// with it back on, the next one does. On the real clock, with a nudge of 20 s, as the notification test explains.
    @MainActor
    func testTheNudgeNotificationCanBeTurnedOff() throws {
        let app = launch(at: nil, reset: true, nudgeSeconds: 20)
        openSettings(app)
        let toggle = app.switches["settings.notifications"]
        XCTAssertTrue(toggle.appears(within: 5), "No switch in Settings")
        func set(_ on: Bool) { setNotificationSwitch(app, "settings.notifications", on: on) }
        set(true)
        attachScreenshot(of: app, named: "Notify me when I'm away, on")
        set(false)

        openPractice(app)
        tap(app, "practice.start")
        goHome()
        XCTAssertFalse(notification.appears(within: 30), "It notified with the switch off")
        app.activate()
        tap(app, "practice.stop")

        openSettings(app)
        set(true)
        openPractice(app)
        tap(app, "practice.start")
        answerNotification(with: "Still practicing")
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
        XCTAssertTrue(app.staticTexts["practice.still-practicing"].appears(within: 30), "It didn't ask")
        // The system asks once per install, so a retry on the same simulator finds the notification allowed.
        let remind = app.buttons["practice.remind-me"]
        if remind.appears(within: 3) {
            attachScreenshot(of: app, named: "Still practicing? with Remind me")
            remind.tap()
            let allow = springboard.alerts.buttons["Allow"]
            XCTAssertTrue(allow.appears(within: 10), "The system didn't ask")
            allow.tap()
            XCTAssertTrue(remind.disappears(within: 5), "It offered the notification again")
        }
        tap(app, "practice.still-practicing-yes")

        tap(app, "practice.stop")
        tap(app, "practice.start")
        tap(app, "practice.pause")
        goHome()
        XCTAssertFalse(notification.appears(within: 30), "It nudged a paused session")
        app.activate()
        tap(app, "practice.resume")
        answerNotification(with: "Still practicing")
        app.activate()
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        XCTAssertFalse(
            app.staticTexts["practice.still-practicing"].appears(within: 3), "The answer was lost")

        tap(app, "practice.stop")
        tap(app, "practice.start")
        // Left on History, so the notification has to bring Practice back.
        openHistory(app)
        answerNotification(with: "I stopped earlier")
        XCTAssertTrue(app.datePickers["practice.stopped-at"].appears(within: 10), "No end to pick")
        attachScreenshot(of: app, named: "Opened from the notification's I stopped earlier")
        tap(app, "practice.stop-at")
        XCTAssertEqual(text(app, "practice.status"), "Ready to practice")

        tap(app, "practice.start")
        openHistory(app)
        // Real time has to pass the nudge, with nothing in History to wait for.
        Thread.sleep(forTimeInterval: 22)
        openPractice(app)
        XCTAssertTrue(
            app.staticTexts["practice.still-practicing"].appears(within: 3), "It didn't ask on Practice")
        // A new banner asks the system again, which says it's allowed.
        XCTAssertFalse(
            app.buttons["practice.remind-me"].appears(within: 3), "It offered the notification again")
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
        XCTAssertTrue(picker.appears(within: 5), "No end to pick")
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
        XCTAssertTrue(app.datePickers["practice.stopped-at"].appears(within: 5), "No end to pick")
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

        XCTAssertTrue(app.staticTexts["practice.still-practicing"].appears(within: 30), "It didn't ask")
        XCTAssertTrue(app.staticTexts["practice.capped"].appears(within: 90), "It didn't stop at the cap")
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
        XCTAssertTrue(element(app, "history.empty").appears(within: 5))
        attachScreenshot(of: app, named: "History, empty")
        openPractice(app)
        tap(app, "practice.stop")
        openHistory(app)
        let day = element(app, "history.day")
        XCTAssertTrue(day.appears(within: 5))
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
        XCTAssertTrue(app.navigationBars["Edit session"].appears(within: 5), "The editor didn't open")
        setEndMinute(app, to: nil, title: "Edit session")
        tap(app, "editor.cancel")
        let editor = app.navigationBars["Edit session"]
        XCTAssertTrue(editor.disappears(within: 5), "Cancel asked to discard a change")
        XCTAssertEqual(session.value as? String, "25 minutes, 3 seconds")
        kill(app)

        app = launch(at: start + 60 * 60)
        openHistory(app)
        let relaunched = element(app, "history.day")
        XCTAssertTrue(relaunched.appears(within: 5))
        XCTAssertEqual(relaunched.value as? String, "25 minutes, 3 seconds")
    }

    /// HIS-3: under the chart, how many days of the week counted and how many weeks met the goal, following the goal
    /// and the daily minimum in Settings. The model tests count the weeks.
    @MainActor
    func testTheWeekSaysHowConsistentPracticeIs() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        kill(app)
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")

        // One day in a week is short of the goal of three, and nothing is said about weeks until one meets it.
        openHistory(app)
        XCTAssertEqual(text(app, "history.week-days"), "Practiced 1 of 7 days")
        let weeksMet = app.staticTexts["history.weeks-met"]
        XCTAssertFalse(weeksMet.exists, "It reported weeks before any met the goal")
        attachScreenshot(of: app, named: "The week, with no week yet meeting the goal")

        func setGoal(_ identifier: String, _ choice: String) {
            openSettings(app)
            // Below the fold on a shorter screen.
            if !element(app, identifier).appears(within: 2) { app.swipeUp() }
            choose(app, identifier, choice)
            attachScreenshot(of: app, named: "Settings, \(choice)")
            openHistory(app)
        }
        setGoal("settings.goal-days", "1 day")
        XCTAssertEqual(text(app, "history.weeks-met"), "1 week met your goal in the past year")

        // The 25 minutes fall short of a 30-minute day, then clear a 15-minute one.
        setGoal("settings.daily-minimum", "30 minutes")
        XCTAssertEqual(
            text(app, "history.week-days"), "Practiced 30 minutes or more on 0\u{00A0}of\u{00A0}7\u{00A0}days")
        XCTAssertFalse(weeksMet.exists, "A day short of the minimum met the goal")
        setGoal("settings.daily-minimum", "15 minutes")
        XCTAssertEqual(
            text(app, "history.week-days"), "Practiced 15 minutes or more on 1\u{00A0}of\u{00A0}7\u{00A0}days")
        XCTAssertEqual(text(app, "history.weeks-met"), "1 week met your goal in the past year")
        attachScreenshot(of: app, named: "The week with a daily minimum, its line across the chart")

        // Kept across a relaunch, and at the largest text size.
        kill(app)
        app = launch(at: start + 26 * 60, textSize: "AccessibilityXXXL")
        openHistory(app)
        // Below the fold there on a shorter screen, under the chart.
        for _ in 0..<3 where !app.staticTexts["history.week-days"].isHittable { app.swipeUp() }
        XCTAssertEqual(
            text(app, "history.week-days"), "Practiced 15 minutes or more on 1\u{00A0}of\u{00A0}7\u{00A0}days")
        attachScreenshot(of: app, named: "The week at the largest text")
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
        XCTAssertTrue(shown.appears(within: 5))
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

        // A tap on its day's bar scrolls to its session, unless it's on screen already, as on an iPad. The day depends
        // on the time zone: Thursday in California, Friday on CI, which runs in UTC.
        let session = app.descendants(matching: .any).matching(identifier: "history.session")
            .matching(NSPredicate(format: "value == '25 minutes'")).firstMatch
        let wasShown = session.exists && session.isHittable
        let day = Date(timeIntervalSince1970: start).formatted(.dateTime.weekday(.wide))
        element(app, "history.week-chart").descendants(matching: .any)[day].tap()
        if !wasShown {
            XCTAssertTrue(session.appears(within: 5))
            XCTAssertTrue(session.wait(for: \.isHittable, toEqual: true, timeout: 5), "The tap didn't show \(day)")
        }
        attachScreenshot(of: app, named: "History, a tapped day")
    }

    /// HIS-2: a tapped day scrolls up to its date, one row below the bar, with the row above it on top: the last session
    /// of the day above, or Time per piece and skill's row for the newest day. Not to its first session, with the date hidden
    /// under the bar. At the largest text, where the week fills the screen. The sample practice is `Showcase`'s.
    @MainActor
    func testATappedDayShowsItsDate() throws {
        // Given the App Store screenshots' four weeks of sample practice, seen on a Friday afternoon wherever the test
        // runs (California, or UTC on CI), at the largest text
        let now = start + 20 * 60 * 60
        let app = launch(at: now, reset: true, showcase: true, textSize: "AccessibilityXXXL")
        openHistory(app)
        let chart = element(app, "history.week-chart")
        /// Below the fold on an iPhone at this size: the tap scrolls the bar into view first.
        func tapBar(_ date: TimeInterval) {
            XCTAssertTrue(chart.appears(within: 5))
            let weekday = Date(timeIntervalSince1970: date).formatted(.dateTime.weekday(.wide))
            chart.descendants(matching: .any)[weekday].tap()
        }
        func date(_ title: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "history.day")
                .matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        }
        /// The tapped day's date rises from below and what's above the row before it scrolls away. Then the date
        /// stays clear of the bar, where the scroll used to carry it on under. After the first check, these go by
        /// the frame: on CI's iOS 26, asking again whether the date was hittable failed the test, "Activation point
        /// invalid", rather than answering (#215).
        func showsUnderTheBar(_ tapped: XCUIElement, scrolledAway: XCUIElement) {
            XCTAssertTrue(tapped.wait(for: \.isHittable, toEqual: true, timeout: 5), "The tap didn't show the day")
            let bar = app.navigationBars.firstMatch.frame.maxY
            let gone = scrolledAway.wait(for: \.[above: bar], toEqual: true, timeout: 5)
            XCTAssertTrue(gone, "It didn't scroll far enough")
            XCTAssertFalse(tapped.wait(for: \.[below: bar], toEqual: false, timeout: 2), "The date went under the bar")
        }

        // When Yesterday's bar is tapped
        tapBar(now - 24 * 60 * 60)

        // Then Yesterday's date shows, under Today's session, with Today's date scrolled away
        showsUnderTheBar(date("Yesterday"), scrolledAway: date("Today"))
        attachScreenshot(of: app, named: "History, Yesterday tapped, at the largest text")

        // When Today's bar is tapped, from the top
        app.buttons["History"].firstMatch.tap()
        tapBar(now)

        // Then Today's date shows, under Time per piece and skill's row, with the week scrolled away
        showsUnderTheBar(date("Today"), scrolledAway: chart)
        XCTAssertTrue(app.buttons["history.piece-stats"].isHittable, "Time per piece and skill's row isn't on top")
        attachScreenshot(of: app, named: "History, Today tapped, at the largest text")
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
        XCTAssertTrue(search.appears(within: 5))
        search.tap()
        search.typeText("Ballade No. 1")
        tap(app, "tags.add-piece")
        XCTAssertTrue(app.keyboards.firstMatch.disappears(within: 5), "Adding should put the keyboard away")
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
        XCTAssertTrue(element(app, "history.week").appears(within: 5))
        let tagRows = app.descendants(matching: .any).matching(identifier: "history.week-tag")
        XCTAssertEqual(tagRows.count, 0)
        XCTAssertTrue(element(app, "history.session").isHittable, "The week pushed the sessions off the screen")
        tap(app, "history.week-by-tag")
        // The tagged session counts toward both of its tags, each marked as a piece or a skill.
        XCTAssertTrue(tagRows.firstMatch.appears(within: 5))
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
        XCTAssertTrue(tagRows.firstMatch.appears(within: 5), "The breakdown closed after a relaunch")
        XCTAssertEqual(shownRows(), expected)
        // Open, it pushes the sessions further down.
        app.swipeUp()
        XCTAssertTrue(element(app, "history.day").appears(within: 5))
        let sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.matching(NSPredicate(format: "label ENDSWITH 'Ballade No. 1, Scales'")).count, 1)
        XCTAssertEqual(sessions.matching(NSPredicate(format: "label ENDSWITH 'Untagged'")).count, 1)
        attachScreenshot(of: app, named: "History, tagged and untagged")
    }

    /// TAG-1, #132: an archived piece a newer version wrote is found by part of its name, but dimmed with the reason,
    /// and tapping it neither tags the session nor shows an error (the owner's pick 2026-11-11).
    @MainActor
    func testAnArchivedPieceFromANewerVersionCantBeChosen() throws {
        // Given an archived piece a newer version wrote, and a running session
        let app = launch(at: start, reset: true, newerArchivedPiece: "Étude in E")
        tap(app, "practice.start")
        tap(app, "practice.tags")

        // When part of its name is searched for
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 5))
        search.tap()
        search.typeText("tude")
        XCTAssertTrue(app.keyboards.firstMatch.appears(within: 5))

        // Then it's found, dimmed, with the reason
        let row = app.buttons.matching(identifier: "tags.tag")
            .matching(NSPredicate(format: "label BEGINSWITH 'Étude in E'")).firstMatch
        XCTAssertTrue(row.appears(within: 5), "Part of its name didn't find it")
        XCTAssertFalse(row.isEnabled, "It can be chosen")
        XCTAssertTrue(row.label.contains("Archived by a newer version of Pianism. Update to use it."), row.label)
        attachScreenshot(of: app, named: "Tag picker, archived by a newer version")

        // When it's tapped, then nothing is tagged and no error shows
        row.tap()
        XCTAssertFalse(app.alerts.firstMatch.appears(within: 2), "An error showed")
        XCTAssertFalse(row.isSelected, "It was chosen")
        tap(app, "tags.done")
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Untagged")
    }

    /// TAG-1: part of an archived piece's name finds it, marked Archived, above the button that would add a
    /// near-duplicate.
    @MainActor
    func testAnArchivedPieceIsFoundByPartOfItsName() throws {
        let app = launch(at: start, reset: true)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 5))
        search.tap()
        search.typeText("Ballade No. 1")
        tap(app, "tags.add-piece")
        // Untagged, so archiving takes it off the list.
        XCTAssertTrue(app.keyboards.firstMatch.disappears(within: 5))
        tap(app, "Ballade No. 1")
        XCTAssertTrue(
            app.buttons["Ballade No. 1"].wait(for: \.isSelected, toEqual: false, timeout: 5), "It stayed tagged")
        revealSwipeActions(app.buttons["Ballade No. 1"])
        tap(app, "Archive")
        XCTAssertTrue(app.buttons["Ballade No. 1"].disappears(within: 5), "Archiving didn't hide it")

        search.tap()
        search.typeText("Ballade")
        let archived = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Ballade No. 1' AND label CONTAINS 'Archived'")
        )
        .firstMatch
        XCTAssertTrue(archived.appears(within: 5), "Part of its name didn't find it")
        XCTAssertLessThan(archived.frame.midY, element(app, "tags.add-piece").frame.midY, "It wasn't above Add")
        attachScreenshot(of: app, named: "Tag picker, archived piece found")
    }

    /// TAG-4: a duplicate piece is merged into the one to keep. A session tagged with both counts once toward the
    /// kept piece, in History too, and undoing the merge after a relaunch brings both back as they were.
    @MainActor
    func testMergingAPieceAndUndoingIt() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 5))
        for name in ["Ballade", "Ballade No. 1"] {
            search.tap()
            search.typeText(name)
            tap(app, "tags.add-piece")
            XCTAssertTrue(app.keyboards.firstMatch.disappears(within: 5))
        }
        revealSwipeActions(app.buttons["Ballade"])
        attachScreenshot(of: app, named: "Tag picker, piece swiped")
        tap(app, "tags.merge")
        attachScreenshot(of: app, named: "Merge, choosing the piece to keep")
        // By ID: the picker under the sheet has a button with the same name.
        let target = app.buttons["merge.target"]
        XCTAssertTrue(target.appears(within: 5), "Merge didn't open")
        XCTAssertEqual(target.label, "Ballade No. 1")
        target.tap()
        XCTAssertTrue(app.buttons["Ballade"].disappears(within: 5), "The merged piece is still offered")
        let mergedRow = app.staticTexts["Merged into Ballade No. 1"]
        XCTAssertTrue(mergedRow.appears(within: 5), "The merge can't be undone")
        attachScreenshot(of: app, named: "Tag picker, piece merged")
        tap(app, "tags.done")
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Ballade No. 1")
        kill(app)

        app = launch(at: start + 25 * 60)
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Ballade No. 1")
        tap(app, "practice.stop")
        openHistory(app)
        tap(app, "history.week-by-tag")
        let tagRows = app.descendants(matching: .any).matching(identifier: "history.week-tag")
        XCTAssertTrue(tagRows.firstMatch.appears(within: 5))
        XCTAssertEqual(tagRows.count, 1, "It counted toward more than the kept piece")
        XCTAssertEqual(tagRows.firstMatch.value as? String, "25 minutes")
        let session = element(app, "history.session")
        XCTAssertTrue(session.label.hasSuffix(", Ballade No. 1"), session.label)
        XCTAssertFalse(session.label.contains("Ballade, "), session.label)
        attachScreenshot(of: app, named: "History, merged")

        session.tap()
        tap(app, "editor.tags")
        tap(app, "tags.undo-merge")
        XCTAssertTrue(app.buttons["Ballade"].appears(within: 5), "Undo didn't bring it back")
        XCTAssertTrue(app.buttons["Ballade"].isSelected, "The session lost its tag")
        XCTAssertFalse(mergedRow.exists, "It's still listed as merged")
        attachScreenshot(of: app, named: "Tag picker, merge undone")
        tap(app, "tags.done")
        tap(app, "editor.cancel")
        XCTAssertTrue(app.buttons["editor.cancel"].disappears(within: 5))
        let bothTags = app.descendants(matching: .any).matching(identifier: "history.session")
            .matching(NSPredicate(format: "label ENDSWITH 'Ballade, Ballade No. 1'"))
        XCTAssertTrue(bothTags.firstMatch.appears(within: 5), session.label)
        XCTAssertEqual(tagRows.count, 2, "Each tag should count the session again")
        attachScreenshot(of: app, named: "History, merge undone")
    }

    /// TAG-3: a piece is given a composer and a target tempo from the tag picker, which shows them under its
    /// name. A tempo out of range can't be saved, and the details are still there after a relaunch.
    @MainActor
    func testPieceDetails() throws {
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 5))
        search.tap()
        search.typeText("Ballade No. 1")
        tap(app, "tags.add-piece")
        attachScreenshot(of: app, named: "Tag picker, piece added")
        revealSwipeActions(app.buttons["Ballade No. 1"])
        attachScreenshot(of: app, named: "Tag picker, piece swiped")
        tap(app, "tags.details")
        let composer = app.textFields["details.composer"]
        XCTAssertTrue(composer.appears(within: 5), "The details didn't open")
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
        XCTAssertTrue(composer.disappears(within: 5), "The details didn't close")
        let withDetails = NSPredicate(format: "label BEGINSWITH 'Ballade No. 1' AND label CONTAINS 'Chopin, 72 BPM'")
        var ballade = app.buttons.matching(withDetails).firstMatch
        XCTAssertTrue(ballade.appears(within: 5), "No details under the name")
        attachScreenshot(of: app, named: "Tag picker, piece with details")
        kill(app)

        app = launch(at: start + 60)
        tap(app, "practice.tags")
        ballade = app.buttons.matching(withDetails).firstMatch
        XCTAssertTrue(ballade.appears(within: 5), "No details after a relaunch")
        revealSwipeActions(ballade)
        tap(app, "tags.details")
        XCTAssertTrue(app.textFields["details.composer"].appears(within: 5), "The details didn't open")
        XCTAssertEqual(app.textFields["details.composer"].value as? String, "Chopin")
        XCTAssertEqual(app.textFields["details.tempo"].value as? String, "72")
    }

    /// TAG-5: a skill is added inside the built-in Scales from a swipe, and another from the row ending Scales's open
    /// fold, where a name already inside Scales can't be added twice. The session reads "Scales › D minor" on Practice
    /// and in History. Reopened with nothing inside chosen, Scales is folded, and tapping its name tags Scales itself.
    /// A piece with a piece inside it can't be archived, and the alert says how many are inside (D1, D3, D4, D5).
    @MainActor
    func testAddingASkillInsideScales() throws {
        // Given a running session, and Scales with nothing inside it
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        XCTAssertTrue(app.searchFields.firstMatch.appears(within: 5))

        // When "D minor" is added inside Scales from a swipe right
        revealSwipeActions(tagRow(app, "Scales"), fromLeadingEdge: true)
        attachScreenshot(of: app, named: "Tag picker, Scales swiped right")
        tap(app, "tags.add-inside-swipe")
        XCTAssertTrue(app.alerts["New skill inside Scales"].appears(within: 5), "Add Inside didn't ask")
        let name = app.alerts.textFields.firstMatch
        name.tap()
        name.typeText("D minor")
        attachScreenshot(of: app, named: "Add inside, naming")
        app.alerts.buttons["Add"].tap()

        // Then it tags the session, inside an open Scales
        let dMinor = tagRow(app, "D minor")
        XCTAssertTrue(dMinor.appears(within: 5), "It isn't under Scales")
        XCTAssertTrue(dMinor.isSelected, "It didn't tag the session")

        // When the row ending Scales adds "d minor", then "G major", which is then untagged. Add is checked on just
        // before the last letter, so its turning off is down to the name already inside, not an empty field.
        tap(app, "tags.add-inside")
        XCTAssertTrue(name.appears(within: 5), "The row didn't ask")
        name.tap()
        name.typeText("d mino")
        let add = app.alerts.buttons["Add"]
        XCTAssertTrue(add.wait(for: \.isEnabled, toEqual: true, timeout: 5), "A new name couldn't be added")
        name.typeText("r")
        XCTAssertTrue(add.wait(for: \.isEnabled, toEqual: false, timeout: 5), "A name already inside could be added")
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + "G major")
        add.tap()
        let gMajor = tagRow(app, "G major")
        XCTAssertTrue(gMajor.appears(within: 5), "The second skill isn't under Scales")
        attachScreenshot(of: app, named: "Tag picker, two skills inside Scales")
        gMajor.tap()
        XCTAssertTrue(gMajor.wait(for: \.isSelected, toEqual: false, timeout: 5), "It stayed tagged")
        tap(app, "tags.done")

        // Then Practice names the skill with its parent
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Scales › D minor")
        attachScreenshot(of: app, named: "Practicing, tagged inside Scales")
        kill(app)

        // When the session is stopped and History opens
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        openHistory(app)

        // Then its row names the skill with its parent too
        let session = element(app, "history.session")
        XCTAssertTrue(session.appears(within: 5))
        XCTAssertTrue(session.label.hasSuffix(", Scales › D minor"), session.label)
        attachScreenshot(of: app, named: "History, tagged inside Scales")

        // When its tags open, D minor is untagged and Scales's name is tapped
        session.tap()
        tap(app, "editor.tags")
        XCTAssertTrue(dMinor.appears(within: 5), "Scales opened folded with a skill inside it chosen")
        dMinor.tap()
        XCTAssertTrue(dMinor.wait(for: \.isSelected, toEqual: false, timeout: 5), "It stayed tagged")
        let scales = tagRow(app, "Scales")
        scales.tap()

        // Then Scales itself is tagged, and opens folded next time, with nothing inside it chosen
        XCTAssertTrue(scales.wait(for: \.isSelected, toEqual: true, timeout: 5), "Scales isn't tagged")
        tap(app, "tags.done")
        tap(app, "editor.tags")
        XCTAssertTrue(scales.appears(within: 5))
        XCTAssertTrue(scales.isSelected, "Scales lost its tag")
        XCTAssertFalse(dMinor.exists, "Scales opened unfolded")
        attachScreenshot(of: app, named: "Tag picker, Scales folded")

        // When a piece gets a piece inside it, then is archived
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Suite")
        tap(app, "tags.add-piece")
        XCTAssertTrue(app.keyboards.firstMatch.disappears(within: 5))
        revealSwipeActions(tagRow(app, "Suite"), fromLeadingEdge: true)
        tap(app, "tags.add-inside-swipe")
        XCTAssertTrue(app.alerts["New piece inside Suite"].appears(within: 5), "Add Inside didn't ask")
        name.tap()
        name.typeText("Prelude")
        app.alerts.buttons["Add"].tap()
        XCTAssertTrue(tagRow(app, "Prelude").appears(within: 5), "It isn't under Suite")
        revealSwipeActions(tagRow(app, "Suite"))
        tap(app, "Archive")

        // Then it says what's inside goes first, and the piece stays
        let blocked = app.alerts["Archive the 1 piece inside “Suite” first."]
        XCTAssertTrue(blocked.appears(within: 5), "Archiving wasn't blocked")
        attachScreenshot(of: app, named: "Tag picker, archive blocked")
        blocked.buttons.firstMatch.tap()
        XCTAssertTrue(tagRow(app, "Suite").exists, "It was archived anyway")
    }

    /// HIS-2, TAG-5: in the week's "By piece and skill", Scales holds the time with a skill inside it, folded at first;
    /// unfolded, the skill shows under it by its own name, with its own time (the owner's pick 2026-11-11).
    @MainActor
    func testTheWeekUnfoldsWhatsInsideAPiece() throws {
        // Given a 25-minute session tagged with a skill added inside Scales
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        revealSwipeActions(tagRow(app, "Scales"), fromLeadingEdge: true)
        tap(app, "tags.add-inside-swipe")
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.appears(within: 5), "Add Inside didn't ask")
        name.tap()
        name.typeText("Arpeggios")
        app.alerts.buttons["Add"].tap()
        tap(app, "tags.done")
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Scales › Arpeggios")
        kill(app)
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")

        // When the week's breakdown opens
        openHistory(app)
        tap(app, "history.week-by-tag")

        // Then Scales has the session's time, and the skill inside it isn't listed yet. By label: a fold's arrow carries
        // its row's identifier too.
        let tagRows = app.descendants(matching: .any).matching(identifier: "history.week-tag")
        let scales = tagRows.matching(NSPredicate(format: "label == 'Scales, Skill'")).firstMatch
        let arpeggios = tagRows.matching(NSPredicate(format: "label == 'Arpeggios, Skill'")).firstMatch
        XCTAssertTrue(scales.appears(within: 5), "Scales isn't listed")
        XCTAssertEqual(scales.value as? String, "25 minutes")
        XCTAssertFalse(arpeggios.exists, "What's inside Scales showed before it unfolded")
        attachScreenshot(of: app, named: "History, this week by tag, folded")

        // When Scales unfolds
        scales.tap()

        // Then the skill shows under it, by its own name, with its own time
        XCTAssertTrue(arpeggios.appears(within: 5), "Scales didn't unfold")
        XCTAssertEqual(arpeggios.value as? String, "25 minutes")
        XCTAssertGreaterThan(arpeggios.frame.minY, scales.frame.maxY - 1, "It isn't under Scales")
        attachScreenshot(of: app, named: "History, this week by tag, Scales unfolded")
    }

    /// TAG-5: a skill moves inside Scales from a swipe right and shows under it, unfolded, and the session tagged with it
    /// reads "Scales › Pedalling" without being changed. Moved back to the top level, it reads "Pedalling" again. A
    /// move into a list that has its name, whatever the case, is refused with the reason (D4, Q1).
    @MainActor
    func testMovingASkillInsideScalesAndBack() throws {
        // Given a running session tagged with a new top-level skill
        let app = launch(at: start, reset: true)
        tap(app, "practice.start")
        tap(app, "practice.tags")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 5))
        search.tap()
        search.typeText("Pedalling")
        tap(app, "tags.add-skill")
        XCTAssertTrue(app.keyboards.firstMatch.disappears(within: 5))
        let pedalling = tagRow(app, "Pedalling")
        let scales = app.buttons.matching(identifier: "move.target").matching(NSPredicate(format: "label == 'Scales'"))
            .firstMatch
        let moveBar = app.navigationBars["Move “Pedalling”"]

        // When it's moved inside Scales from a swipe right
        revealSwipeActions(pedalling, fromLeadingEdge: true)
        attachScreenshot(of: app, named: "Tag picker, a skill swiped right")
        tap(app, "tags.move")
        XCTAssertTrue(moveBar.appears(within: 5), "Move didn't open")
        XCTAssertTrue(app.buttons["move.top-level"].isSelected, "Where it is isn't checked")
        attachScreenshot(of: app, named: "Move, from the top level")
        XCTAssertTrue(scales.appears(within: 5), "Scales isn't offered")
        scales.tap()
        XCTAssertTrue(moveBar.disappears(within: 5), "Move didn't close")

        // Then it's under an unfolded Scales, and the session reads with its parent
        XCTAssertTrue(app.buttons["tags.add-inside"].appears(within: 5), "Scales didn't unfold")
        XCTAssertTrue(pedalling.exists && pedalling[below: tagRow(app, "Scales").frame.maxY], "It isn't under Scales")
        attachScreenshot(of: app, named: "Tag picker, moved inside Scales")
        tap(app, "tags.done")
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Scales › Pedalling")

        // When the picker opens again, unfolded at the chosen skill, and it's moved back to the top level
        tap(app, "practice.tags")
        revealSwipeActions(pedalling, fromLeadingEdge: true)
        tap(app, "tags.move")
        XCTAssertTrue(scales.appears(within: 5), "Move didn't open")
        XCTAssertTrue(scales.isSelected, "Where it is isn't checked")
        attachScreenshot(of: app, named: "Move, from inside Scales")
        tap(app, "move.top-level")
        XCTAssertTrue(moveBar.disappears(within: 5), "Move didn't close")
        tap(app, "tags.done")

        // Then the session reads it alone again
        XCTAssertEqual(element(app, "practice.tags").value as? String, "Pedalling")

        // When "pedalling" is added inside Scales, and Pedalling is moved there
        tap(app, "practice.tags")
        revealSwipeActions(tagRow(app, "Scales"), fromLeadingEdge: true)
        tap(app, "tags.add-inside-swipe")
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.appears(within: 5), "Add Inside didn't ask")
        name.tap()
        name.typeText("pedalling")
        let add = app.alerts.buttons["Add"]
        XCTAssertTrue(
            add.wait(for: \.isEnabled, toEqual: true, timeout: 5), "The top-level name blocked it inside Scales")
        add.tap()
        XCTAssertTrue(tagRow(app, "pedalling").appears(within: 5), "It isn't under Scales")
        revealSwipeActions(pedalling, fromLeadingEdge: true)
        tap(app, "tags.move")
        XCTAssertTrue(scales.appears(within: 5), "Move didn't open")
        scales.tap()

        // Then the move is refused with the reason, and it stays at the top level
        let refused = app.alerts["A skill named “Pedalling” is already inside “Scales”. Rename one first."]
        XCTAssertTrue(refused.appears(within: 5), "The clash wasn't refused")
        attachScreenshot(of: app, named: "Move, refused for a name inside Scales")
        refused.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["move.top-level"].isSelected, "It moved anyway")

        // When the place it's in is chosen
        tap(app, "move.top-level")

        // Then the sheet closes, and it's still at the top level
        XCTAssertTrue(moveBar.disappears(within: 5), "Move didn't close")
        XCTAssertTrue(pedalling.exists, "It left the top level")
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
        XCTAssertTrue(app.buttons["tags.done"].appears(within: 5))
        XCTAssertFalse(app.buttons["Synced piece"].exists, "The piece arrived before the picker opened")
        XCTAssertTrue(app.buttons["Synced piece"].appears(within: 45), "The piece didn't show")
    }

    /// SYN-1: a session iCloud brings from another device, tagged with a piece that came before it, shows in the
    /// open History. The same switch saves the piece after 20 seconds and the session after 40, so History opens
    /// first with nothing to wait for but the launch. Its own launch, so a slow tag picker can't use up the time.
    @MainActor
    func testASessionFromAnotherDeviceShowsWhileOpen() throws {
        let app = launch(at: start, reset: true, syncArrivesSeconds: 20)
        openHistory(app)
        let synced = app.descendants(matching: .any).matching(identifier: "history.session")
            .matching(NSPredicate(format: "label CONTAINS 'Synced piece'")).firstMatch
        XCTAssertFalse(synced.exists, "The session arrived before History opened")
        XCTAssertTrue(synced.appears(within: 60), "The session didn't show")
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
        XCTAssertTrue(session.appears(within: 5))
        session.tap()
        let note = element(app, "editor.note")
        note.tap()
        note.typeText("Coda")

        let deleted = XCTDarwinNotificationExpectation(
            notificationName: "com.edkarabinus.Pianism.delete-elsewhere-done")
        notify_post("com.edkarabinus.Pianism.delete-elsewhere")
        wait(for: [deleted], timeout: 30)
        tap(app, "editor.save")
        XCTAssertTrue(app.alerts.firstMatch.appears(within: 5), "Saving didn't say it failed")
        XCTAssertTrue(app.alerts.staticTexts["This session was deleted on another device."].exists, "It didn't say why")
        attachScreenshot(of: app, named: "Saving a session deleted on another device")
        app.alerts.buttons.firstMatch.tap()
        XCTAssertTrue(element(app, "editor.refusal").appears(within: 5), "The editor didn't stay open")
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
        XCTAssertTrue(session.appears(within: 5))
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
        XCTAssertTrue(app.buttons["editor.save"].disappears(within: 5))
        let tagged = app.descendants(matching: .any).matching(identifier: "history.session")
            .matching(NSPredicate(format: "label ENDSWITH 'Scales'"))
        XCTAssertTrue(tagged.firstMatch.appears(within: 5), session.label)
        XCTAssertEqual(tagged.firstMatch.value as? String, "20 minutes")
        attachScreenshot(of: app, named: "History, edited")
        kill(app)

        app = launch(at: start + 60 * 60)
        openHistory(app)
        let relaunched = element(app, "history.session")
        XCTAssertTrue(relaunched.appears(within: 5))
        XCTAssertTrue(relaunched.label.hasSuffix("Scales"), relaunched.label)
        XCTAssertEqual(relaunched.value as? String, "20 minutes")
        relaunched.tap()
        let savedNote = element(app, "editor.note")
        XCTAssertTrue(savedNote.appears(within: 5))
        XCTAssertEqual(savedNote.value as? String, "Coda, slowly")
    }

    /// SES-5: a session is added after the fact from History. It starts 30 minutes long, and History
    /// shows it once it's saved.
    @MainActor
    func testAddASessionAfterTheFact() throws {
        let app = launch(at: start, reset: true)
        openHistory(app)
        tap(app, "history.add")
        XCTAssertTrue(app.navigationBars["Add session"].appears(within: 5))
        attachScreenshot(of: app, named: "Add session")

        tap(app, "editor.save")
        XCTAssertTrue(app.buttons["editor.save"].disappears(within: 5))
        let session = element(app, "history.session")
        XCTAssertTrue(session.appears(within: 5))
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
        XCTAssertTrue(editor.appears(within: 5))
        tap(app, "editor.cancel")
        XCTAssertTrue(editor.disappears(within: 5))

        tap(app, "history.add")
        let note = element(app, "editor.note")
        XCTAssertTrue(note.appears(within: 5))
        note.tap()
        note.typeText("Scales, slowly")
        // Drags the editor by its title to the bottom of the screen, which closes a sheet that allows it.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)))
        XCTAssertFalse(editor.disappears(within: 3), "The editor was swiped away with a change")
        tap(app, "editor.cancel")
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.appears(within: 5))
        attachScreenshot(of: app, named: "Discard changes")
        discard.tap()
        XCTAssertTrue(editor.disappears(within: 5))
        XCTAssertTrue(element(app, "history.empty").appears(within: 5))
    }

    /// ONB-1: the first launch with no practice says what Pianism does, and Start closes it and starts a session.
    @MainActor
    func testWelcomeStartsTheFirstSession() throws {
        let app = launch(at: start, reset: true, welcome: true)
        XCTAssertTrue(element(app, "welcome.start").appears(within: 10))
        attachScreenshot(of: app, named: "Welcome")
        tap(app, "welcome.start")
        XCTAssertTrue(element(app, "practice.stop").appears(within: 5))
        XCTAssertFalse(element(app, "welcome.start").exists)
    }

    /// ADR 0008, step 2: before a CloudKit deploy, PIANISM_CLEAR_DEBUG_DATA=1 empties Debug's history but keeps the
    /// settings and the running session, which a Release build on the same device shares (Ed, 2026-11-10).
    @MainActor
    func testClearingDebugDataKeepsSettingsAndTheRunningSession() throws {
        // Given sample history and its running session, and a setting changed: sharing usage turned off
        var app = launch(at: start, reset: true, showcase: true)
        XCTAssertTrue(element(app, "practice.stop").appears(within: 5))
        let sharing = sharingSwitch(in: app)
        let off = app.switches.matching(NSPredicate(format: "identifier == 'settings.shares-usage' AND value == '0'"))
            .firstMatch
        sharing.tap()
        if !off.appears(within: 3) { sharing.switches.firstMatch.tap() }
        XCTAssertTrue(off.appears(within: 5), "The switch didn't turn off")
        kill(app)

        // When it opens again with Debug's data cleared
        app = launch(at: start + 60, clearDebugData: true)

        // Then the setting stays, the session still runs, and the history is empty
        XCTAssertEqual(sharingSwitch(in: app).value as? String, "0", "The settings were cleared")
        openPractice(app)
        XCTAssertTrue(element(app, "practice.stop").appears(within: 10), "The running session was cleared")
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").appears(within: 5), "Debug's history was kept")
    }

    /// ONB-1: the welcome closes without starting anything, and it shows once.
    @MainActor
    func testWelcomeClosesForGood() throws {
        var app = launch(at: start, reset: true, welcome: true)
        // PRO-2 (#53): it says playing starts a session, only while Pianism is open, and that it's Pro after 5 free.
        let words = element(app, "welcome.words")
        XCTAssertTrue(words.appears(within: 10))
        XCTAssertTrue(words.label.contains("to start a session by playing while Pianism is open"), words.label)
        XCTAssertTrue(words.label.contains("Your first 5 are free. After that, it's part of Pro."), words.label)
        tap(app, "welcome.close")
        XCTAssertTrue(element(app, "practice.start").appears(within: 5))
        XCTAssertFalse(element(app, "welcome.start").exists)
        kill(app)

        app = launch(at: start + 60, welcome: true)
        XCTAssertTrue(element(app, "practice.start").appears(within: 10))
        XCTAssertFalse(element(app, "welcome.start").exists)
    }

    /// ONB-1: at the largest text, the welcome scrolls down to its buttons, and its words never run under them. Its link
    /// opens Connect a piano.
    @MainActor
    func testWelcomeFitsAtTheLargestText() throws {
        let app = launch(at: start, reset: true, textSize: "AccessibilityXXXL", welcome: true)
        let startButton = element(app, "welcome.start")
        let connect = element(app, "welcome.connect")
        XCTAssertTrue(startButton.appears(within: 10))
        attachScreenshot(of: app, named: "Welcome, largest text")
        app.swipeUp()
        app.swipeUp()
        attachScreenshot(of: app, named: "Welcome, largest text, scrolled")
        XCTAssertTrue(startButton.isHittable)
        XCTAssertLessThanOrEqual(element(app, "welcome.words").frame.maxY, startButton.frame.minY)
        connect.tap()
        XCTAssertTrue(app.navigationBars["Connect a piano"].appears(within: 5))
    }

    /// EXP-1: without Pro, Export opens the Pro screen; after buying, it opens the share sheet with the file.
    @MainActor
    func testExportOpensOnlyWithPro() throws {
        let app = launch(at: start, reset: true, syncArrivesSeconds: 1)
        openSettings(app)
        proRow("settings.export", in: app).tap()
        let buy = app.buttons["paywall.buy"]
        XCTAssertTrue(buy.appears(within: 5), "The locked row didn't open the Pro screen")
        buy.tap()
        XCTAssertTrue(app.staticTexts["paywall.unlocked"].appears(within: 10), "Buying didn't unlock Pro")
        app.buttons["paywall.close"].tap()

        proRow("settings.export", in: app).tap()
        // The sheet's header shows the file's title, which also says the file was handed over; the system's own name
        // for the sheet only as a fallback, as it's private and could change.
        let title = app.staticTexts["Pianism sessions"]
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(title.appears(within: 10) || sheet.exists, "The share sheet didn't open")
        attachScreenshot(of: app, named: "Export, share sheet")
    }

    /// Scrolls to a row of Settings, such as Pro's in the last section, which a Form may not have built yet (PRO-1).
    @MainActor
    private func proRow(_ id: String, in app: XCUIApplication) -> XCUIElement {
        scrolledTo(app.descendants(matching: .any)[id].firstMatch, in: app)
    }

    /// The most swipes up to reach a row: Settings is shorter than this, so a row that never shows fails the test
    /// instead of swiping on.
    private static let mostSwipesToARow = 8

    /// Swipes up until `row`, which a Form builds only near the screen, exists and can be tapped.
    @MainActor
    private func scrolledTo(_ row: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<Self.mostSwipesToARow where !(row.exists && row.isHittable) { app.swipeUp() }
        return row
    }

    /// PRO-1: with a scripted store, on every simulator. Pro stays through an empty answer at the next launch, and only
    /// a refund takes it away, so someone who paid never sees it disappear (ADR 0012).
    @MainActor
    func testRestoreUnlocksProWhichStaysUntilARefund() throws {
        var app = launch(at: start, reset: true, restoreFinds: true)
        openSettings(app)
        attachScreenshot(of: app, named: "Settings, Pro not unlocked")
        proRow("settings.restore", in: app).tap()
        XCTAssertTrue(proRow("settings.pro", in: app).appears(within: 10), "Restoring didn't unlock Pro")
        attachScreenshot(of: app, named: "Settings, Pro unlocked")
        kill(app)

        app = launch(at: start)
        openSettings(app)
        let pro = proRow("settings.pro", in: app)
        XCTAssertTrue(pro.appears(within: 5), "Pro went away when the store said nothing")

        notify_post("com.edkarabinus.Pianism.pro-refunded")
        XCTAssertTrue(pro.disappears(within: 10), "A refund left Pro on")
        XCTAssertTrue(proRow("settings.restore", in: app).appears(within: 5), "No way to restore after one")
    }

    /// PRO-1: a restore that finds nothing says so, and leaves the button there to try again.
    @MainActor
    func testRestoreFindingNothingSaysSo() throws {
        let app = launch(at: start, reset: true)
        openSettings(app)
        let restore = proRow("settings.restore", in: app)
        restore.tap()
        XCTAssertTrue(proRow("settings.restore-notice", in: app).appears(within: 10), "It said nothing")
        XCTAssertEqual(app.staticTexts["settings.restore-notice"].label, "No purchase found.")
        attachScreenshot(of: app, named: "Settings, no purchase found")
        XCTAssertTrue(restore.exists, "The button should still be there")
    }

    /// A session of real StoreKit, driven from this process, with no purchases and none of the last run's settings.
    /// Ask to Buy lasts across runs on a simulator, so it's set here. On CI's iOS 26 the product never loads (#205), so
    /// these run on iOS 27, and a device checks what they can't (ADR 0012).
    @MainActor
    private func realStore() throws -> SKTestSession {
        try XCTSkipUnless(
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27, "StoreKit Testing needs iOS 27 on CI")
        let session = try SKTestSession(configurationFileNamed: "Pianism")
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = false
        addTeardownBlock { @MainActor in session.clearTransactions() }
        return session
    }

    /// PRO-1, through real StoreKit: a purchase shows at launch with nothing stored, and a refund reaches the open app.
    @MainActor
    func testRealStoreKitUnlocksProAndARefundTurnsItOff() async throws {
        let session = try realStore()
        try await session.buyProduct(identifier: "com.edkarabinus.Pianism.pro")
        let app = launch(at: start, reset: true, realStore: true)
        openSettings(app)
        let pro = proRow("settings.pro", in: app)
        XCTAssertTrue(pro.appears(within: 30), "A purchase didn't unlock Pro")

        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        XCTAssertTrue(pro.disappears(within: 60), "A refund didn't reach the app")
    }

    /// PRO-1, through real StoreKit: the restore call itself, finding nothing, with no account to sign in to.
    @MainActor
    func testRealStoreKitRestoreFindingNothingSaysSo() throws {
        _ = try realStore()
        let app = launch(at: start, reset: true, realStore: true)
        openSettings(app)
        proRow("settings.restore", in: app).tap()
        XCTAssertTrue(proRow("settings.restore-notice", in: app).appears(within: 30), "It said nothing")
        XCTAssertEqual(app.staticTexts["settings.restore-notice"].label, "No purchase found.")
    }

    /// Opens the Pro screen from Settings, its only way in until a feature is locked (PRO-3).
    @MainActor
    private func openPaywall(_ app: XCUIApplication) -> XCUIElement {
        openSettings(app)
        proRow("settings.show-pro", in: app).tap()
        let close = app.buttons["paywall.close"]
        XCTAssertTrue(close.appears(within: 5), "The Pro screen didn't open")
        return close
    }

    /// PRO-3: the Pro screen never opens by itself, only from a tap, and shows the store's price, what's included,
    /// Restore and Close.
    @MainActor
    func testThePaywallShowsOnlyWhenAProFeatureIsTapped() throws {
        let app = launch(at: start, reset: true)
        XCTAssertTrue(element(app, "practice.start").appears(within: 10))
        XCTAssertFalse(app.buttons["paywall.close"].appears(within: 3), "It opened at launch")
        let close = openPaywall(app)
        let buy = app.buttons["paywall.buy"]
        XCTAssertTrue(buy.appears(within: 5), "No price")
        XCTAssertEqual(buy.label, "Unlock Pro for $14.99")
        XCTAssertTrue(app.staticTexts["One purchase, no subscription."].exists)
        let included = app.staticTexts["Piano sessions start, pause and save themselves while Pianism is open."]
        XCTAssertTrue(included.exists, "Nothing's listed as included")
        // Each of Pro's features has its own line.
        XCTAssertTrue(app.staticTexts["Time per piece and skill, in all and over the last 30 days."].exists, "No stats")
        XCTAssertTrue(app.staticTexts["Export every session as a spreadsheet file (CSV)."].exists, "No export")
        XCTAssertTrue(app.buttons["paywall.restore"].exists, "No Restore")
        try audit(app, "Pro screen", contrast: false, stallsOnIPadIOS26: true, overASheet: true)
        close.tap()
        XCTAssertTrue(close.disappears(within: 5), "Close didn't close it")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    /// PRO-2, D6: with 4 piano sessions used and no Pro, Practice says 1 is left, and the piano starts the 5th, which
    /// saves itself. Then Practice says starting by itself is part of Pro, with a way to the Pro screen; the piano's
    /// next notes start nothing, and Start and History work as before.
    @MainActor
    func testTheFifthPianoSessionStartsAndTheSixthOffersPro() throws {
        executionTimeAllowance = 5 * 60  // a stalled audit then costs 5 min, not the default 15
        var app = launch(at: nil, reset: true, midiPiano: "MIDI KEYBOARD", autoLogged: 4)
        let left = app.staticTexts["practice.free-left"]
        XCTAssertTrue(left.appears(within: 10), "Practice doesn't say how many are left")
        XCTAssertEqual(left.label, "1 free piano session left")

        // The 5th plays about 1.5 s, pauses after 2 s of silence and saves after 4. The 6th's notes come at 14 s.
        app = launch(
            at: nil, midiNotes: "1,1.3,1.6,2.5,14,14.3,14.6", midiPauseSeconds: 2, midiSaveSeconds: 4,
            midiMinimumSeconds: 1, midiPiano: "MIDI KEYBOARD")
        let launched = Date.now
        // The 5th is over by about 7 s, often before the launch ends, so its saving shows it started.
        let used = app.staticTexts["practice.free-used"]
        XCTAssertTrue(used.appears(within: 15), "The 5th didn't start and save, or Practice didn't say so")
        XCTAssertTrue(app.staticTexts["practice.last-session"].exists, "No last session")
        XCTAssertEqual(used.label, "Sessions that start themselves are part of Pro.")
        attachScreenshot(of: app, named: "Free piano sessions used")

        // Inverted, as a wait for an element that never comes collects minutes of debug information on an iPhone. It
        // lasts until a 6th would have ended, at about 19 s.
        let sixth = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.buttons["practice.stop"])
        sixth.isInverted = true
        sixth.expectationDescription = "The 6th piano session started"
        wait(for: [sixth], timeout: max(21 - Date.now.timeIntervalSince(launched), 1))
        // However late that wait began: the 6th's notes are too short to save, so had it started, Practice would say so
        // in place of the 5th.
        XCTAssertFalse(app.staticTexts["practice.too-short"].exists, "The 6th started")
        XCTAssertTrue(app.staticTexts["practice.last-session"].exists, "The 5th isn't the last session")
        try audit(app, "Practice, free piano sessions used")

        tap(app, "practice.show-pro")
        let close = app.buttons["paywall.close"]
        XCTAssertTrue(close.appears(within: 5), "The link didn't open the Pro screen")
        close.tap()
        XCTAssertTrue(close.disappears(within: 5))
        tap(app, "practice.start")
        XCTAssertEqual(text(app, "practice.status"), "Practicing", "Start didn't start a session")
        openHistory(app)
        XCTAssertTrue(element(app, "history.session").appears(within: 5), "History lost its sessions")
    }

    /// HIS-4: a piece's piano split sits in a card of its own under its totals, headed, so it doesn't read as a split
    /// of them: playing is part of the totals, and paused time is in none (decided with Ed, 2026-11-13).
    @MainActor
    func testThePianosSplitHasACardOfItsOwn() throws {
        executionTimeAllowance = 5 * 60  // a stalled audit then costs 5 min, not the default 15
        // Given sample practice, some of each piece's started by the piano, and Pro
        let app = launch(at: start, reset: true, showcase: true, pro: true)
        XCTAssertTrue(element(app, "practice.stop").appears(within: 10))

        // When Time per piece and skill opens
        openHistory(app)
        tap(app, "history.piece-stats")

        // Then the first piece's Playing is under the heading, below its totals, with a footer saying what counts
        let total = app.staticTexts["Total"].firstMatch
        let heading = app.staticTexts["Started by your piano, last 30 days"].firstMatch
        let playing = app.staticTexts["Playing"].firstMatch
        XCTAssertTrue(heading.appears(within: 5), "No heading over the piano's split")
        attachScreenshot(of: app, named: "Time per piece and skill, the piano's split")
        XCTAssertLessThan(total.frame.maxY, heading.frame.minY, "The heading isn't below the totals")
        XCTAssertLessThan(heading.frame.maxY, playing.frame.minY, "Playing isn't under the heading")
        XCTAssertTrue(
            app.staticTexts["Playing is part of the totals above; paused time isn't counted."].firstMatch.exists,
            "No footer under the piano's split")
        try audit(app, "Time per piece and skill, the piano's split, audited", contrast: false)
    }

    /// HIS-4, D7: without Pro, History's Time per piece and skill opens the Pro screen, with no numbers. Once Pro is
    /// bought, it lists a piece another device practiced, with its 30 minutes in all and in the last 30 days, and with
    /// the switch on Skills, Scales, which the skill it was tagged with sits inside, with the same 30 minutes and a
    /// "1 inside" row that opens the skill with its own (D6). Before that session arrives, both sides are empty, and
    /// the switch still works over the empty state. The session comes 40 s after launch, leaving a slow CI iPad time
    /// to buy.
    @MainActor
    func testTimePerPieceOpensOnlyWithPro() throws {
        executionTimeAllowance = 5 * 60  // a stalled audit then costs 5 min, not the default 15
        // An untagged session, so History shows the row
        let app = launch(at: start, reset: true, syncArrivesSeconds: 20, autoLogged: 1)
        openHistory(app)
        tap(app, "history.piece-stats")
        let buy = app.buttons["paywall.buy"]
        XCTAssertTrue(buy.appears(within: 5), "The locked row didn't open the Pro screen")
        XCTAssertFalse(app.staticTexts["Last 30 days"].exists, "Stats showed without Pro")
        buy.tap()
        XCTAssertTrue(app.staticTexts["paywall.unlocked"].appears(within: 10), "Buying didn't unlock Pro")
        app.buttons["paywall.close"].tap()

        // Given nothing tagged yet, when the switch goes to Skills over "No pieces yet"
        tap(app, "history.piece-stats")
        XCTAssertTrue(app.staticTexts["No pieces yet"].appears(within: 5), "Pieces weren't empty")
        let skills = app.segmentedControls["piece-stats.kind"].buttons["Skills"]
        skills.tap()
        // Then Skills shows, empty too
        XCTAssertTrue(app.staticTexts["No skills yet"].appears(within: 5), "The switch didn't work")
        attachScreenshot(of: app, named: "Time per piece and skill, no skills")

        // Given the session from another device, tagged with a piece and a skill
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let synced = app.descendants(matching: .any).matching(identifier: "history.session")
            .matching(NSPredicate(format: "label CONTAINS 'Synced piece'")).firstMatch
        XCTAssertTrue(synced.appears(within: 60), "The session from another device didn't arrive")
        // When the stats open again
        tap(app, "history.piece-stats")
        // Then the piece has its 30 minutes, on Pieces as before
        let tag = element(app, "piece-stats.piece")
        XCTAssertTrue(tag.appears(within: 5), "No piece is listed")
        XCTAssertEqual(tag.label, "Synced piece")
        let times = app.descendants(matching: .any).matching(
            NSPredicate(format: "label IN {'Total', 'Last 30 days'} AND value == '30 minutes'"))
        XCTAssertEqual(times.count, 2, "The piece's times are wrong")
        XCTAssertFalse(app.descendants(matching: .any)["Playing"].exists, "A timed session showed a piano's split")
        try audit(app, "Time per piece and skill")
        // And on iPhone the title is in the bar, level with the back button, not a large title under the bar's edge. An
        // iPad's title was always in the bar, a row below the back button, which sits beside the tabs.
        if UIDevice.current.userInterfaceIdiom == .phone {
            let title = app.navigationBars.staticTexts["Time per piece and skill"]
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertLessThan(
                abs(title.frame.midY - back.frame.midY), back.frame.height / 2, "The title isn't in the bar")
        }
        attachScreenshot(of: app, named: "Time per piece and skill")

        // When the switch shows skills
        skills.tap()
        // Then Scales, which the skill sits inside, has the same 30 minutes, and the piece is gone
        XCTAssertTrue(tag.wait(for: \.label, toEqual: "Scales", timeout: 5), "Scales isn't listed")
        XCTAssertEqual(times.count, 2, "Scales's times are wrong")
        attachScreenshot(of: app, named: "Time per piece and skill, skills")

        // When Scales's "1 inside" row opens
        let inside = element(app, "piece-stats.inside")
        XCTAssertTrue(inside.appears(within: 5), "No inside row")
        XCTAssertEqual(inside.label, "1 inside")
        inside.tap()
        // Then a screen titled Scales lists the skill with its own 30 minutes, with no switch
        XCTAssertTrue(app.navigationBars["Scales"].appears(within: 5), "The skills inside didn't open")
        XCTAssertTrue(tag.wait(for: \.label, toEqual: "Synced skill", timeout: 5), "The skill inside isn't listed")
        XCTAssertEqual(times.count, 2, "The skill's times are wrong")
        XCTAssertFalse(app.segmentedControls["piece-stats.kind"].exists, "The switch showed inside Scales")
        attachScreenshot(of: app, named: "Time per piece and skill, inside Scales")
    }

    /// PRO-3: buying from the Pro screen unlocks Pro at once, there and in Settings.
    @MainActor
    func testBuyingProFromTheProScreen() throws {
        let app = launch(at: start, reset: true)
        let close = openPaywall(app)
        let buy = app.buttons["paywall.buy"]
        XCTAssertTrue(buy.appears(within: 5))
        buy.tap()
        XCTAssertTrue(app.staticTexts["paywall.unlocked"].appears(within: 10), "Buying didn't unlock Pro")
        XCTAssertFalse(app.buttons["paywall.restore"].exists, "Restore is still offered")
        attachScreenshot(of: app, named: "Pro screen, unlocked")
        close.tap()
        XCTAssertTrue(proRow("settings.pro", in: app).appears(within: 5), "Settings doesn't say so")
    }

    /// PRO-3: a purchase waiting for approval, as with Ask to Buy, says so, and the approval unlocks Pro in the open
    /// Pro screen.
    @MainActor
    func testAPurchaseWaitingForApprovalUnlocksProOnceApproved() throws {
        let app = launch(at: start, reset: true, buying: "pending")
        _ = openPaywall(app)
        let buy = app.buttons["paywall.buy"]
        XCTAssertTrue(buy.appears(within: 5))
        buy.tap()
        let notice = app.staticTexts["paywall.notice"]
        XCTAssertTrue(notice.appears(within: 10), "It said nothing")
        XCTAssertEqual(notice.label, "Waiting for approval. Pro unlocks once it's approved.")
        attachScreenshot(of: app, named: "Pro screen, waiting for approval")
        notify_post("com.edkarabinus.Pianism.pro-approved")
        XCTAssertTrue(
            app.staticTexts["paywall.unlocked"].appears(within: 10), "The approval didn't unlock Pro")
    }

    /// PRO-3: with the App Store out of reach, the Pro screen shows no price rather than a made-up one, and Try Again,
    /// Restore and Close are there. Try Again staying put only shows the store's still out of reach: the model tests
    /// cover what it asks.
    @MainActor
    func testTheProScreenWithoutTheAppStore() throws {
        let app = launch(at: start, reset: true, noOffer: true)
        let close = openPaywall(app)
        XCTAssertTrue(app.buttons["paywall.retry"].appears(within: 5), "No way to try again")
        XCTAssertTrue(app.staticTexts["The price isn't available right now."].exists)
        XCTAssertFalse(app.buttons["paywall.buy"].exists, "A price showed with no store")
        attachScreenshot(of: app, named: "Pro screen, no App Store")
        app.buttons["paywall.retry"].tap()
        XCTAssertTrue(app.buttons["paywall.retry"].appears(within: 5))
        XCTAssertTrue(app.buttons["paywall.restore"].isEnabled)
        close.tap()
        XCTAssertTrue(close.disappears(within: 5))
    }

    /// PRO-3, through real StoreKit: the store's price, and a purchase from the Pro screen.
    @MainActor
    func testRealStoreKitBuysProFromTheProScreen() throws {
        _ = try realStore()
        let app = launch(at: start, reset: true, realStore: true)
        _ = openPaywall(app)
        let buy = app.buttons["paywall.buy"]
        XCTAssertTrue(buy.appears(within: 30), "The store's price didn't load")
        XCTAssertEqual(buy.label, "Unlock Pro for $14.99")
        buy.tap()
        XCTAssertTrue(
            app.staticTexts["paywall.unlocked"].appears(within: 30), "The purchase didn't unlock Pro")
    }

    /// PRO-3, through real StoreKit: Ask to Buy says it's waiting, and the approval unlocks Pro in the open Pro screen.
    /// The #205 probe saw one approval take over 30 s on CI's iPad, hence the minute.
    @MainActor
    func testRealStoreKitAskToBuyUnlocksProOnceApproved() throws {
        let session = try realStore()
        session.askToBuyEnabled = true
        let app = launch(at: start, reset: true, realStore: true)
        _ = openPaywall(app)
        let buy = app.buttons["paywall.buy"]
        XCTAssertTrue(buy.appears(within: 30), "The store's price didn't load")
        buy.tap()
        XCTAssertTrue(app.staticTexts["paywall.notice"].appears(within: 30), "It didn't say it's waiting")
        let pending = try XCTUnwrap(session.allTransactions().first, "No transaction waits for approval")
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        XCTAssertTrue(
            app.staticTexts["paywall.unlocked"].appears(within: 60), "The approval didn't unlock Pro")
    }

    /// ADR 0011: sharing anonymous usage is on until it's turned off in Settings, and stays as it was left. Debug builds
    /// send nothing, so the adapter's tests check what's sent and stopped, against a fake network.
    @MainActor
    func testSharingUsageIsOnUntilTurnedOff() throws {
        var app = launch(at: start, reset: true)
        var sharing = sharingSwitch(in: app)
        XCTAssertEqual(sharing.value as? String, "1", "Sharing usage isn't on by default")
        attachScreenshot(of: app, named: "Settings, sharing anonymous usage")
        let off = app.switches.matching(NSPredicate(format: "identifier == 'settings.shares-usage' AND value == '0'"))
            .firstMatch
        // As the overlap warning's switch: it sometimes takes the tap only on its own control, and waiting first means
        // a tap that took but hadn't shown yet isn't undone.
        sharing.tap()
        if !off.appears(within: 3) { sharing.switches.firstMatch.tap() }
        XCTAssertTrue(off.appears(within: 5), "The switch didn't turn off")
        kill(app)

        app = launch(at: start + 60)
        sharing = sharingSwitch(in: app)
        XCTAssertEqual(sharing.value as? String, "0", "Sharing usage came back on after a relaunch")
    }

    /// SES-5: a session that shares practice with another says so, but can still be saved. "Don't Show
    /// Again" turns the warning off, even after a relaunch, and Settings turns it back on (SET-1).
    @MainActor
    func testOverlapWarningCanBeTurnedOff() throws {
        // Midday wherever this runs, as a session across midnight would have a second row.
        let today = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: start))
        let start = today.addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
        var app = launch(at: start, reset: true)
        tap(app, "practice.start")
        kill(app)
        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        openHistory(app)
        tap(app, "history.add")
        // The added session ends where the practiced one starts, so it warns only once it ends 20 minutes in.
        XCTAssertTrue(element(app, "editor.note").appears(within: 5))
        XCTAssertFalse(element(app, "editor.overlap").exists, "The added session overlaps before any change")
        setEndMinute(app, to: "20", title: "Add session")
        XCTAssertTrue(element(app, "editor.overlap").appears(within: 5))
        attachScreenshot(of: app, named: "Add session, overlapping")
        tap(app, "editor.overlap-off")
        XCTAssertTrue(element(app, "editor.overlap").disappears(within: 5))
        tap(app, "editor.save")
        XCTAssertTrue(app.buttons["editor.save"].disappears(within: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "history.session").count, 2)
        kill(app)

        app = launch(at: start + 30 * 60)
        openHistory(app)
        tap(app, "history.add")
        // It now ends where the session added above starts, so ending at :45 shares 15 minutes with it.
        XCTAssertTrue(element(app, "editor.note").appears(within: 5))
        setEndMinute(app, to: "45", title: "Add session")
        let practiceTime = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Practice time'"))
        XCTAssertEqual(practiceTime.firstMatch.value as? String, "45 minutes")
        XCTAssertFalse(element(app, "editor.overlap").exists)

        // SET-1: Settings turns it back on, and the same session warns again.
        tap(app, "editor.cancel")
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.appears(within: 5), "Cancel didn't ask to discard the new session")
        discard.tap()
        XCTAssertTrue(app.buttons["editor.save"].disappears(within: 5))
        openSettings(app)
        let warning = app.switches["settings.overlap-warning"]
        // Below the fold on a shorter screen, like iPhone Duo's, where a Form hasn't built the row yet.
        if !warning.appears(within: 2) { app.swipeUp() }
        XCTAssertTrue(warning.appears(within: 5), "No overlap warning in Settings")
        XCTAssertEqual(warning.value as? String, "0", "Settings shows the warning on after Don't Show Again")
        let on = app.switches.matching(NSPredicate(format: "identifier == 'settings.overlap-warning' AND value == '1'"))
            .firstMatch
        warning.tap()
        // A switch in a Form sometimes takes the tap only on its own control; waiting first means a tap that took
        // but hadn't shown yet isn't undone.
        if !on.appears(within: 2) { warning.switches.firstMatch.tap() }
        XCTAssertTrue(on.appears(within: 5), "The warning didn't turn back on")
        openHistory(app)
        tap(app, "history.add")
        XCTAssertTrue(element(app, "editor.note").appears(within: 5))
        setEndMinute(app, to: "45", title: "Add session")
        XCTAssertTrue(element(app, "editor.overlap").appears(within: 5), "The warning stayed off")
    }

    /// MIDI-2, SET-1: Settings says no piano is connected and opens how to connect one, with the tip for a piano that
    /// doesn't show up over USB and Apple's Bluetooth pairing; with a piano, it names it.
    @MainActor
    func testSettingsConnectsAPiano() throws {
        var app = launch(at: start, reset: true)
        openSettings(app)
        let pianos = app.buttons["settings.pianos"]
        XCTAssertTrue(pianos.appears(within: 5), "No piano row in Settings")
        XCTAssertEqual(pianos.label, "Connect a piano")
        pianos.tap()
        XCTAssertTrue(app.buttons["pianos.pair"].appears(within: 5), "No way to pair a Bluetooth piano")
        XCTAssertEqual(
            text(app, "pianos.replug"),
            "If your piano doesn't show up, unplug the cable at the piano's end and plug it back in.")
        attachScreenshot(of: app, named: "Connect a piano")
        kill(app)

        app = launch(at: start, midiPiano: "MIDI KEYBOARD")
        XCTAssertEqual(text(app, "practice.pianos"), "MIDI KEYBOARD connected")
        openSettings(app)
        XCTAssertTrue(app.buttons["settings.pianos"].appears(within: 5))
        XCTAssertEqual(app.buttons["settings.pianos"].label, "MIDI KEYBOARD connected")
        attachScreenshot(of: app, named: "Settings, a piano connected")
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
        XCTAssertTrue(session.appears(within: 5))

        session.tap()
        tap(app, "editor.delete")
        XCTAssertTrue(app.staticTexts["Delete this session?"].appears(within: 5))
        attachScreenshot(of: app, named: "Delete this session")
        confirmDelete(app)
        XCTAssertTrue(session.disappears(within: 5))
        tap(app, "history.undo")
        XCTAssertTrue(session.appears(within: 5))
        kill(app)

        // The real 5 seconds.
        app = launch(at: start + 30 * 60)
        openHistory(app)
        deleteBySwipe(app)
        XCTAssertTrue(app.buttons["history.undo"].disappears(within: 15), "Undo outlasted its 5 seconds")
        kill(app)

        app = launch(at: start + 31 * 60)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").appears(within: 5))
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
        XCTAssertTrue(sessions.element(boundBy: 1).appears(within: 5), "A kill didn't keep the session")
        deleteBySwipe(app)
        openPractice(app)
        kill(app)

        app = launch(at: start + 52 * 60, undoSeconds: 60)
        openHistory(app)
        sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertTrue(sessions.firstMatch.appears(within: 5))
        XCTAssertEqual(sessions.count, 1, "Leaving History didn't save the deletion")
        deleteBySwipe(app)
        goHome()
        kill(app)

        app = launch(at: start + 53 * 60)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").appears(within: 5), "Leaving the app didn't save it")
    }

    /// SYN-1: on a simulator signed out of iCloud, as every test simulator must be, History says its history isn't
    /// syncing, whether it's empty or has practice. This checks that test simulators stay signed out
    /// (docs/device-checklist.md).
    @MainActor
    func testHistorySaysWhenICloudIsntSyncing() throws {
        var app = launch(at: start, reset: true)
        openHistory(app)
        XCTAssertTrue(element(app, "history.empty").appears(within: 5))
        let notice = element(app, "history.not-syncing")
        XCTAssertTrue(
            notice.appears(within: 10),
            "No notice: is this simulator signed into iCloud? Test simulators must stay signed out (docs/device-checklist.md)."
        )
        XCTAssertTrue(
            notice.label.contains(
                "Your history isn't syncing. In the Settings app, sign in to iCloud and turn it on for Pianism."),
            "It said \(notice.label)")
        attachScreenshot(of: app, named: "History, not syncing")

        openPractice(app)
        tap(app, "practice.start")
        kill(app)

        // A minute later, so the session is long enough to keep (SES-1).
        app = launch(at: start + 60)
        tap(app, "practice.stop")
        openHistory(app)
        XCTAssertTrue(element(app, "history.session").appears(within: 5))
        XCTAssertTrue(
            element(app, "history.not-syncing").appears(within: 10), "The notice went once there was practice"
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
        XCTAssertTrue(notice.appears(within: 10), "No notice")
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
        XCTAssertTrue(notice.appears(within: 5), "It didn't count them")
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
        XCTAssertTrue(element(app, "history.unavailable").appears(within: 5))
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
        XCTAssertTrue(app.buttons["practice.start"].appears(within: 5))
        XCTAssertEqual(text(app, "practice.waiting"), "2 sessions waiting to be saved")
        attachScreenshot(of: app, named: "Practice, sessions waiting")
        openHistory(app)
        XCTAssertTrue(element(app, "history.unavailable").appears(within: 5))
        let notSavedYet = NSPredicate(format: "label CONTAINS 'not saved yet'")
        let waiting = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertEqual(waiting.count, 2)
        XCTAssertEqual(waiting.matching(notSavedYet).count, 2)
        attachScreenshot(of: app, named: "History, sessions waiting")
        kill(app)

        app = launch(at: start + 60 * 60)
        XCTAssertFalse(app.staticTexts["practice.waiting"].exists)
        openHistory(app)
        XCTAssertTrue(element(app, "history.day").appears(within: 5))
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
        XCTAssertTrue(activityShows(), "No activity on the Home Screen")
        XCTAssertEqual(liveActivities.count, 1)
        attachScreenshot(of: springboard, named: "The Live Activity in the island")
        kill(app)
        XCTAssertTrue(activityShows(), "The activity went with the app")

        app = launch(at: nil)
        goHome()
        XCTAssertTrue(activityShows(), "The activity went at the relaunch")
        XCTAssertEqual(liveActivities.count, 1, "The relaunch started another activity")
        app.activate()
        tap(app, "practice.stop")
        goHome()
        assertNoLiveActivity("The activity stayed after Stop")
        kill(app)

        app = launch(at: nil, midiNotes: "0,0,0")
        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 10), "The notes didn't start a session")
        goHome()
        XCTAssertTrue(activityShows(), "No activity for a MIDI session")
        app.activate()
        tap(app, "practice.stop")
        goHome()
        assertNoLiveActivity("The activity stayed after Stop")
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
        XCTAssertTrue(activityShows(), "No activity on the Home Screen")
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
        assertNoLiveActivity("The activity stayed past the cap")
    }

    /// GLN-1, MIDI-1: once the app leaves the screen, a piano session's island stops its clock at the last note, as
    /// nothing hears the piano then (decided with Ed, 2026-11-03). The notes are a chord at the start, so it stops at
    /// 0:00; the title and "Open Pianism to keep counting." show only on the Lock Screen and expanded, device row L9.
    @MainActor
    func testAPianoSessionsIslandStopsAtItsLastNote() throws {
        try skipWithoutAnIsland()
        let app = launch(at: nil, reset: true, midiNotes: "0,0,0")
        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 10), "The notes didn't start a session")
        goHome()
        XCTAssertTrue(activityShows(), "No activity on the Home Screen")
        let clock = liveActivities.firstMatch.staticTexts.firstMatch
        XCTAssertTrue(
            clock.wait(for: \.label, toEqual: "0:00", timeout: 10),
            "The clock didn't stop at the last note: \(clock.label)")
        // A second read, to show it stays stopped.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(clock.label, "0:00", "The island counted with nobody hearing the piano")
        attachScreenshot(of: springboard, named: "The island stopped at the last note")
    }

    /// MIDI-1, MIDI-2: a piano the system announces is heard through the app's own CoreMIDI adapter, not the test
    /// script: Practice names it, three notes start a session, and the name goes with the piano (device rows M1, M3
    /// and P1, with a piano in software).
    @MainActor
    func testAPianoTheSystemAnnouncesIsHeard() throws {
        try skipUnlessSoaking("it needs the simulator's MIDI server")
        let piano = try VirtualPiano(named: "Test piano")
        // A failure stops the test before any deinit, so the piano goes in teardown, or the retry would hear it.
        addTeardownBlock { @MainActor in piano.remove() }
        let app = launch(at: start, reset: true)
        let pianos = app.staticTexts["practice.pianos"]
        XCTAssertTrue(
            pianos.wait(for: \.label, toEqual: "Test piano connected", timeout: 10), "Practice says \(pianos.label)")
        piano.send([0x2090_3C40, 0x2090_3E40, 0x2090_4040])  // three notes in one packet
        XCTAssertTrue(app.buttons["practice.stop"].appears(within: 5), "The notes didn't start a session")
        XCTAssertEqual(text(app, "practice.status"), "Practicing")
        attachScreenshot(of: app, named: "Practicing from a piano the system announced")

        piano.remove()
        XCTAssertTrue(pianos.disappears(within: 10), "Practice still names the piano that went")
    }

    /// MIDI-2: with no piano connected, Practice offers to reconnect the Bluetooth piano paired last, as iOS doesn't after
    /// it restarts. Reconnect opens Apple's pairing screen, and Done closes it. Connect a piano offers it too, until it's
    /// forgotten there (device check P5, the owner's picks 2026-11-11).
    @MainActor
    func testPracticeOffersToReconnectTheBluetoothPiano() {
        // Given a Bluetooth piano paired in Pianism, now switched off
        let app = launch(at: start, reset: true, bluetoothPiano: "CA59 Bluetooth")

        // Then Practice says so, with Reconnect
        XCTAssertEqual(text(app, "practice.piano-missing"), "CA59 Bluetooth isn't connected")
        XCTAssertFalse(element(app, "practice.pianos").exists, "It reads as connected")
        attachScreenshot(of: app, named: "Practice, the Bluetooth piano gone")

        // When Reconnect is tapped, then Apple's pairing screen opens, and Done closes it
        tap(app, "practice.reconnect")
        XCTAssertTrue(app.navigationBars["Bluetooth"].appears(within: 10), "The pairing screen didn't open")
        attachScreenshot(of: app, named: "Reconnecting from Practice")
        tap(app, "pairing.done")
        XCTAssertTrue(app.navigationBars["Bluetooth"].disappears(within: 5), "Done didn't close it")

        // When Connect a piano opens, then it offers Reconnect too
        openSettings(app)
        tap(app, "settings.pianos")
        XCTAssertEqual(text(app, "pianos.missing"), "CA59 Bluetooth isn't connected")
        XCTAssertTrue(app.buttons["pianos.reconnect"].exists, "Connect a piano has no Reconnect")
        attachScreenshot(of: app, named: "Connect a piano, the Bluetooth piano gone")

        // When it's forgotten, then neither screen offers it
        tap(app, "pianos.forget")
        XCTAssertTrue(app.staticTexts["No piano connected"].appears(within: 5), "It wasn't forgotten")
        XCTAssertFalse(element(app, "pianos.missing").exists)
        openPractice(app)
        XCTAssertTrue(element(app, "practice.start").appears(within: 5))
        XCTAssertFalse(element(app, "practice.piano-missing").exists, "Practice still offers it")
    }

    /// MIDI-2: Reconnect's pairing screen closes by itself once the piano is back, and Practice says it's connected
    /// (the owner's picks 2026-11-11).
    @MainActor
    func testReconnectClosesOnceThePianoIsBack() {
        // Given the Bluetooth piano paired in Pianism, switched off, coming back 10 s after launch
        let app = launch(
            at: start, reset: true, midiPiano: "CA59 Bluetooth", bluetoothPiano: "CA59 Bluetooth",
            midiPianoArrives: 10)

        // When Reconnect opens Apple's pairing screen
        tap(app, "practice.reconnect")
        XCTAssertTrue(app.navigationBars["Bluetooth"].appears(within: 5), "The pairing screen didn't open")

        // Then it closes by itself as the piano connects, and Practice says so
        XCTAssertTrue(app.navigationBars["Bluetooth"].disappears(within: 20), "It didn't close by itself")
        XCTAssertEqual(text(app, "practice.pianos"), "CA59 Bluetooth connected")
        XCTAssertFalse(element(app, "practice.piano-missing").exists)
    }

    /// MIDI-2: Apple's pairing screen crashed the app on opening on iOS 27.0, found on a device by check P4.
    @MainActor
    func testPairingABluetoothPianoOpensApplesScreen() {
        let app = launch(at: start, reset: true)
        openSettings(app)
        let pianos = app.buttons["settings.pianos"]
        XCTAssertTrue(pianos.appears(within: 5), "No piano row in Settings")
        pianos.tap()
        let pair = app.buttons["pianos.pair"]
        XCTAssertTrue(pair.appears(within: 5), "Connect a piano didn't open")
        pair.tap()
        XCTAssertTrue(
            app.navigationBars["Bluetooth"].appears(within: 10), "The pairing screen crashed or didn't open")
        attachScreenshot(of: app, named: "Pairing a Bluetooth piano")
    }

    /// NFR-3: XCTest's accessibility audit finds nothing to report on Practice, ready, running and paused, on
    /// History with a session, on Settings and on Connect a piano: every element described and detected, with its traits, targets
    /// big enough to hit, and, on Practice, enough contrast.
    @MainActor
    func testTheScreensPassTheAccessibilityAudit() throws {
        continueAfterFailure = true  // every screen reports, not just the first with an issue
        executionTimeAllowance = 5 * 60  // about 80 s on CI; a stalled audit then costs 5 min, not the default 15
        var app = launch(at: start, reset: true)
        try audit(app, "Practice, ready")
        tap(app, "practice.start")
        try audit(app, "Practice, running")
        tap(app, "practice.pause")
        try audit(app, "Practice, paused")
        tap(app, "practice.resume")
        kill(app)

        app = launch(at: start + 25 * 60)
        tap(app, "practice.stop")
        openHistory(app)
        XCTAssertTrue(element(app, "history.session").appears(within: 5), "No session in History")
        try audit(app, "History", stallsOnIPadIOS26: true)
        openSettings(app)
        // Contrast only noted: the system draws these forms' grey headers, footers and values (#165).
        try audit(app, "Settings", contrast: false, stallsOnIPadIOS26: true)
        tap(app, "settings.pianos")
        XCTAssertTrue(app.buttons["pianos.pair"].appears(within: 5), "Connect a piano didn't open")
        try audit(app, "Connect a piano", contrast: false, stallsOnIPadIOS26: true)
    }

    // Only Xcode 27's SDK (Swift 6.4) has the VoiceOver service; Xcode 26.6 (Swift 6.3) builds the iOS 26 jobs.
    #if compiler(>=6.4)
        /// MIDI-1, NFR-3: when a silence pauses a piano session, VoiceOver says so with the time, unasked, as the drop
        /// back is otherwise only seen (device row M5's VoiceOver half). The service is new in iOS 27, so iOS 26 skips.
        @MainActor
        func testVoiceOverSaysTheSilencePause() throws {
            try skipUnlessSoaking("VoiceOver's service is new in iOS 27")
            guard #available(iOS 27, *) else { throw XCTSkip("VoiceOver can't be driven before iOS 27") }
            let voiceOver = XCUIDevice.shared.voiceOverService
            try voiceOver.enable()
            // Off in teardown, which runs after a failure too, or every later test would run under VoiceOver.
            addTeardownBlock { @MainActor in try? voiceOver.disable() }
            let app = launch(
                at: nil, reset: true, midiNotes: "0.5,0.8,1.1,2.5,4", midiPauseSeconds: 10, midiSaveSeconds: 60,
                midiMinimumSeconds: 2)
            XCTAssertTrue(app.buttons["practice.stop"].appears(within: 20), "No session from the notes")
            // Played from the first note to the last, 3.5 s. Apple documents currentSpeech() as the focused element's
            // speech, but it also reports an announcement while it's being said (the test fails without the line, tried
            // 2026-11-04). So it's asked often, and this stays nightly, should that change.
            let line = "Paused at your last note, 3 seconds"
            var said: [String] = []
            let deadline = Date.now + 40
            while !said.contains(line), Date.now < deadline {
                if let speech = try? voiceOver.currentSpeech().utterance, said.last != speech { said.append(speech) }
                RunLoop.current.run(until: Date.now + 0.25)
            }
            XCTAssertTrue(said.contains(line), "VoiceOver said \(said)")
        }

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
    /// the types that hold today: every element described and detected, with its traits, big enough to hit, and,
    /// unless `contrast` is false, with enough contrast (#165). Settings and Connect a piano pass `contrast: false`,
    /// as the system's gray secondary text there nearly fails it. So does the piano's split on Time per piece and
    /// skill, whose second piece's footer, under the tab bar's glass, failed contrast on an iPhone with iOS 27 in CI
    /// with no element to tie it to (#258, 2026-11-14). Dynamic Type and clipping are noted in the results instead,
    /// as what the audit finds there is a design call (#165). A screen that
    /// `stallsOnIPadIOS26` is skipped there, with the reason in the results. A screen `overASheet` notes, rather than
    /// fails, text the audit can't tie to an element: on an iPad, the dimmed screen around a sheet, which VoiceOver
    /// rightly can't reach.
    @MainActor
    private func audit(
        _ app: XCUIApplication, _ name: String, contrast: Bool = true, stallsOnIPadIOS26: Bool = false,
        overASheet: Bool = false
    ) throws {
        attachScreenshot(of: app, named: name)
        if stallsOnIPadIOS26, UIDevice.current.userInterfaceIdiom == .pad {
            if #unavailable(iOS 27) {
                // The audit of the settings forms stalled on an iPad with iOS 26 (#136): the piano sheet in two of
                // five CI runs, and Settings once since. History's stalled too, twice in a row on #240's CI
                // (2026-11-12), with nothing new on the screen, and never locally (4 runs), so it's the same stall:
                // every List screen has had it, Practice never. Never on another simulator, and a stalled test isn't
                // retried, so there the other three simulators cover these screens.
                XCTContext.runActivity(named: "\(name), not audited: the audit stalls on an iPad with iOS 26") { _ in }
                return
            }
        }
        var failing: XCUIAccessibilityAuditType = [
            .hitRegion, .sufficientElementDescription, .elementDetection, .trait,
        ]
        if contrast { failing.insert(.contrast) }
        var found: [String] = []
        var noted: [String] = []
        try XCTContext.runActivity(named: "Audit \(name)") { _ in
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' \($0.frame)" } ?? "?"
                let line = "\(issue.compactDescription): \(element)"
                let behindTheSheet = overASheet && issue.auditType == .elementDetection && issue.element == nil
                if failing.contains(issue.auditType), !behindTheSheet {
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

    /// The session's Live Activities as the Dynamic Island shows them on the Home Screen, by their container. The
    /// Home Screen only sometimes combines the piano symbol and the clock into one label, "Piano, 0:12", and can switch
    /// for one activity, so a label can't find them. The clock is the only text under the container.
    @MainActor private var liveActivities: XCUIElementQuery {
        springboard.descendants(matching: .any).matching(
            NSPredicate(
                format:
                    "identifier BEGINSWITH 'jindo-container-view' AND identifier CONTAINS 'WidgetRenderer-Activities'"))
    }

    /// How long an activity can take to reach the Home Screen's tree: over 10 s on CI (#398).
    private let activityWait: TimeInterval = 20

    @MainActor
    private func activityShows() -> Bool {
        liveActivities.firstMatch.appears(within: activityWait)
    }

    /// That no activity shows. An ending one takes a moment to go, and a lasting one can take `activityWait` to show,
    /// so it looks once, after that. Real time, like the rest of these tests: nothing says when nothing has happened.
    /// Call it after `activityShows()` has matched in the same test, which proves the query still finds an activity.
    @MainActor
    private func assertNoLiveActivity(_ message: String) {
        Thread.sleep(forTimeInterval: activityWait)
        XCTAssertFalse(liveActivities.firstMatch.exists, message)
    }

    /// Goes to the Home Screen and checks the app left the screen. iPhone swipes up from the bottom edge, as a person
    /// does: on the iPhone Duo simulator (iOS 27.1), XCUIDevice's Home button press takes 5 s and leaves the app in
    /// front. iPad presses Home, as a swipe there can open the app switcher instead. The swipe assumes a Face ID
    /// iPhone: on one with a Home button, it would open Control Center. A busy CI simulator can take over 5 s to
    /// report the app in the background, or miss the gesture, so it waits 10 s and tries once more. A simulator can also
    /// keep saying the app is in front with the Home Screen showing, so Safari being reachable in the Dock counts.
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
            if app.wait(for: .runningBackground, timeout: 10) || springboard.icons["Safari"].firstMatch.isHittable {
                return
            }
        }
        XCTFail("The app stayed in front after leaving it twice")
    }

    /// Leaves the app and answers its "Still practicing?" notification with the button titled `answer`. The system
    /// shows no notification for the app in front, and takes up to about 20 s to show it after the nudge.
    @MainActor
    private func answerNotification(with answer: String) {
        goHome()
        XCTAssertTrue(notification.appears(within: 40), "No notification")
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
                _ = button.appears(within: 3)
            }
        } else {
            notification.press(forDuration: 1.5)
        }
        XCTAssertTrue(button.appears(within: 5), "No \(answer) button")
        button.tap()
    }

    /// Asserts Stop is below the button `identifier` names, or beside it at the same height, as a name broken onto a
    /// second line makes its button taller, and that both are above the tab bar.
    @MainActor
    private func assertCommandsFit(_ app: XCUIApplication, beside identifier: String, at size: String) {
        XCTAssertTrue(element(app, identifier).appears(within: 5), "No \(identifier) at \(size)")
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

    /// Settings' switch for sharing anonymous usage (ADR 0011).
    @MainActor
    private func sharingSwitch(in app: XCUIApplication) -> XCUIElement {
        openSettings(app)
        // The last section, below the fold.
        let sharing = scrolledTo(app.switches["settings.shares-usage"], in: app)
        XCTAssertTrue(sharing.appears(within: 5), "No switch for sharing usage in Settings")
        return sharing
    }

    /// Launches the app with its clock fixed at `now`, or on the real clock if `nil`.
    @MainActor
    private func launch(
        at now: TimeInterval?, reset: Bool = false, showcase: Bool = false, breakHistory: Bool = false,
        unshowableSessions: Int? = nil,
        undoSeconds: Int? = nil, nudgeSeconds: Int? = nil, capSeconds: Int? = nil, offerNudges: Bool = false,
        textSize: String? = nil, syncArrivesSeconds: Int? = nil, midiNotes: String? = nil, midiPauseSeconds: Int? = nil,
        midiSaveSeconds: Int? = nil, midiMinimumSeconds: Int? = nil, midiPiano: String? = nil, intent: String? = nil,
        reminderMinute: Int? = nil, welcome: Bool = false, realStore: Bool = false, restoreFinds: Bool = false,
        buying: String? = nil, noOffer: Bool = false, autoLogged: Int? = nil, clearDebugData: Bool = false,
        bluetoothPiano: String? = nil, midiPianoArrives: Int? = nil, newerArchivedPiece: String? = nil,
        pro: Bool = false
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
        // As launch arguments, these override the stored settings without any test code in the app. The minute is typed
        // as an integer, as a plain number would arrive as a string, which the app wouldn't read as a time.
        if let reminderMinute {
            app.launchArguments += [
                "-remindsDaily", "YES", "-dailyReminderMinute", "<integer>\(reminderMinute)</integer>",
            ]
        }
        // The piano paired last on Apple's screen, which a simulator can't pair.
        if let bluetoothPiano {
            app.launchArguments += ["-bluetoothPiano", bluetoothPiano]
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
        if clearDebugData {
            app.launchEnvironment["PIANISM_CLEAR_DEBUG_DATA"] = "1"
        }
        if !realStore {
            app.launchEnvironment["PIANISM_STORE"] = "free"
        }
        if restoreFinds {
            app.launchEnvironment["PIANISM_RESTORE_FINDS"] = "1"
        }
        // Pro from the start, with the scripted store.
        if pro {
            app.launchEnvironment["PIANISM_PRO"] = "1"
        }
        if let buying {
            app.launchEnvironment["PIANISM_BUY"] = buying
        }
        if noOffer {
            app.launchEnvironment["PIANISM_NO_OFFER"] = "1"
        }
        if !welcome {
            app.launchEnvironment["PIANISM_SKIP_WELCOME"] = "1"
        }
        if breakHistory {
            app.launchEnvironment["PIANISM_BREAK_HISTORY"] = "1"
        }
        if let syncArrivesSeconds {
            app.launchEnvironment["PIANISM_SYNC_ARRIVES_SECONDS"] = String(syncArrivesSeconds)
        }
        if showcase { app.launchEnvironment["PIANISM_SHOWCASE"] = "1" }
        if let unshowableSessions {
            app.launchEnvironment["PIANISM_UNSHOWABLE_SESSIONS"] = String(unshowableSessions)
        }
        if let midiNotes {
            app.launchEnvironment["PIANISM_MIDI_NOTES"] = midiNotes
        }
        app.launchEnvironment["PIANISM_NEWER_ARCHIVED_PIECE"] = newerArchivedPiece
        if let midiPiano {
            app.launchEnvironment["PIANISM_MIDI_PIANO"] = midiPiano
            app.launchEnvironment["PIANISM_MIDI_PIANO_ARRIVES"] = midiPianoArrives.map(String.init)
        }
        if let autoLogged {
            app.launchEnvironment["PIANISM_AUTO_LOGGED"] = String(autoLogged)
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
        XCTAssertTrue(app.staticTexts["practice.status"].appears(within: 10))
        return app
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.appears(within: 5), "No \(identifier) button")
        button.tap()
    }

    /// Opens the History tab. On iOS 26 a tap can land while the tab bar is still animating and not switch
    /// tabs, so it taps once more if History doesn't appear.
    @MainActor
    private func openHistory(_ app: XCUIApplication) {
        let tab = app.buttons["History"].firstMatch
        let history = app.navigationBars["History"]
        tab.tap()
        if !history.appears(within: 3) { tab.tap() }
        XCTAssertTrue(history.appears(within: 5), "History didn't open")
    }

    /// Turns a notification switch in Settings on or off, tapping Allow if the system asks. It asks once per install, so
    /// a retry on the same simulator finds notifications allowed.
    @MainActor
    private func setNotificationSwitch(_ app: XCUIApplication, _ identifier: String, on: Bool) {
        let toggle = app.switches[identifier]
        let wanted = app.switches.matching(
            NSPredicate(format: "identifier == %@ AND value == %@", identifier, on ? "1" : "0")
        ).firstMatch
        guard !wanted.appears(within: 2) else { return }
        // The system asks after whichever tap turned the switch on.
        func allowIfAsked() {
            let allow = springboard.alerts.buttons["Allow"]
            if on, allow.appears(within: 3) { allow.tap() }
        }
        toggle.tap()
        allowIfAsked()
        // As with the overlap warning's switch, a tap in a Form sometimes lands only on its own control.
        if !wanted.appears(within: 2) {
            toggle.switches.firstMatch.tap()
            allowIfAsked()
        }
        XCTAssertTrue(wanted.appears(within: 5), "The switch didn't turn \(on ? "on" : "off")")
    }

    /// Opens Settings, tapping again if the tab bar swallowed the tap, as with History.
    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let tab = app.buttons["Settings"].firstMatch
        let settings = app.navigationBars["Settings"]
        tab.tap()
        if !settings.appears(within: 3) { tab.tap() }
        XCTAssertTrue(settings.appears(within: 5), "Settings didn't open")
    }

    /// Opens Practice from History, tapping again if the tab bar swallowed the tap, as iOS 26's sometimes does
    /// (#80): before a kill, a swallowed tap lost the deletion that leaving History saves.
    @MainActor
    private func openPractice(_ app: XCUIApplication) {
        let tab = app.buttons["Practice"].firstMatch
        let history = app.navigationBars["History"]
        tab.tap()
        if !history.disappears(within: 3) { tab.tap() }
        XCTAssertTrue(app.staticTexts["practice.status"].appears(within: 5), "Practice didn't open")
    }

    /// Picks `choice` from the menu of the picker `identifier`, and checks the picker shows it.
    @MainActor
    private func choose(_ app: XCUIApplication, _ identifier: String, _ choice: String) {
        tap(app, identifier)
        let item = app.buttons[choice].firstMatch
        XCTAssertTrue(item.appears(within: 5), "\(identifier) doesn't offer \(choice)")
        item.tap()
        XCTAssertEqual(chosen(app, identifier), choice)
    }

    /// What the picker `identifier` shows, which a menu picker puts after its label and a comma. Its label has none,
    /// but the choice may ("1 hour, 30 minutes").
    @MainActor
    private func chosen(_ app: XCUIApplication, _ identifier: String) -> String? {
        element(app, identifier).label.components(separatedBy: ", ").dropFirst().joined(separator: ", ")
    }

    /// Taps Delete session in the confirmation, which iOS nests in a button with the same frame and identifier.
    @MainActor
    private func confirmDelete(_ app: XCUIApplication) {
        let confirm = app.buttons["delete.confirm"].firstMatch
        XCTAssertTrue(confirm.appears(within: 5), "No delete.confirm button")
        confirm.tap()
    }

    /// Deletes History's first session with a swipe, confirmed, and checks the list lost one.
    @MainActor
    private func deleteBySwipe(_ app: XCUIApplication) {
        let sessions = app.descendants(matching: .any).matching(identifier: "history.session")
        XCTAssertTrue(sessions.firstMatch.appears(within: 5), "No session to delete")
        let count = sessions.count
        revealSwipeActions(sessions.firstMatch)
        tap(app, "history.delete")
        confirmDelete(app)
        XCTAssertTrue(sessions.element(boundBy: count - 1).disappears(within: 5))
    }

    /// The tag picker's row for the tag `name` reads as. A parent's fold can show its name twice, once as the
    /// disclosure's own label, so this asks for the row's button by its identifier too.
    @MainActor
    private func tagRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "tags.tag").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Shows `row`'s swipe actions, its leading ones if `fromLeadingEdge`, with a press, then a drag halfway across,
    /// rather than a full swipe. A busy
    /// simulator can read swipeLeft as a tap, which would open or toggle the row instead.
    @MainActor
    private func revealSwipeActions(_ row: XCUIElement, fromLeadingEdge: Bool = false) {
        XCTAssertTrue(row.appears(within: 5), "No row to swipe")
        row.coordinate(withNormalizedOffset: CGVector(dx: fromLeadingEdge ? 0.1 : 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
    }

    /// Sets the editor's end minute with the end picker's wheels: hours, then minutes. With no minute, it opens
    /// the wheels and closes them without turning them.
    @MainActor
    private func setEndMinute(_ app: XCUIApplication, to minute: String?, title: String) {
        app.datePickers["editor.end"].buttons.matching(NSPredicate(format: "label CONTAINS ':'")).firstMatch.tap()
        let minutes = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(minutes.appears(within: 5), "The wheels didn't open")
        if let minute { minutes.adjust(toPickerWheelValue: minute) }
        // Closes the wheels with a tap on the editor's title, which does nothing if the tap gets through.
        // Elsewhere a tap can land on the wheels or the Tags row, and the status bar doesn't reach the app.
        let frame = app.navigationBars.staticTexts[title].frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.buttons["PopoverDismissRegion"].disappears(within: 5))
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

extension XCUIElement {
    /// Whether it's wholly above a height on screen, such as the bottom of the navigation bar, to the point. One that
    /// doesn't exist has an empty frame at the top, so it counts as above.
    fileprivate subscript(above y: CGFloat) -> Bool { frame.maxY <= y + 1 }

    /// Whether it's wholly below a height on screen, to the point.
    fileprivate subscript(below y: CGFloat) -> Bool { frame.minY >= y - 1 }
}
