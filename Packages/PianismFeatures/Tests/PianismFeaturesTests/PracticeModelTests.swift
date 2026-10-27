import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
@Suite(.serialized)  // The tests share the stand-in for the device's settings.
struct PracticeModelTests {
    let clock = ManualClock()
    let nudges = InMemoryNudges()
    /// Stands in for the device's settings, emptied before each test.
    let defaults = UserDefaults(suiteName: "PracticeModelTests") ?? .standard

    init() {
        defaults.removePersistentDomain(forName: "PracticeModelTests")
    }

    @Test("ADR 0007: Practice counts the sessions waiting to be saved, until history takes them")
    func countsWaitingSessions() {
        let history = FlakyHistory()
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, defaults: defaults, nudge: 90 * 60, cap: 4 * 60 * 60)
        model.start()
        clock.advance(by: 600)

        model.stop()

        #expect(model.waitingCount == 1)
        #expect(!model.isShowingStorageError)

        history.heal()
        model.refresh()

        #expect(model.waitingCount == 0)
        #expect(history.saved.sessions().map(\.id) == [model.lastSession?.id])
    }

    @Test("SES-4: a session left running ends at the cap when the app next opens, and a banner says so until Start")
    func capEndsASessionLeftRunning() {
        let store = InMemoryRunningSessionStore()
        let history = InMemorySessionHistory()
        let start = clock.now
        PracticeModel(
            store: store, history: history, outbox: InMemorySessionHistory(), clock: clock, nudges: nudges,
            defaults: defaults, nudge: 90 * 60, cap: 600
        ).start()
        clock.advance(by: 36_000)

        let reopened = PracticeModel(
            store: store, history: history, outbox: InMemorySessionHistory(), clock: clock, nudges: nudges,
            defaults: defaults, nudge: 90 * 60, cap: 600)

        #expect(reopened.session == nil)
        #expect(history.sessions().map(\.endedAt) == [start + 600])
        #expect(reopened.lastSession?.endedAt == start + 600)
        #expect(reopened.lastSessionReachedCap)

        reopened.start()

        #expect(!reopened.lastSessionReachedCap)
    }

    @Test("SES-4: a session stopped before the cap shows no banner, and Edit hides the banner but not the session")
    func capBannerOnlyForCappedSessions() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, defaults: defaults, nudge: 90 * 60, cap: 600)
        #expect(!model.lastSessionReachedCap)
        model.start()
        clock.advance(by: 599)
        model.stop()

        #expect(model.lastSession != nil)
        #expect(!model.lastSessionReachedCap)

        model.start()
        clock.advance(by: 600)
        model.refresh()
        #expect(model.lastSessionReachedCap)

        model.dismissCapBanner()

        #expect(!model.lastSessionReachedCap)
        #expect(model.lastSession?.endedAt == clock.now)
    }

    @Test("SES-3: Practice asks once a running session's practice passes the nudge, and not while it's paused")
    func asksPastTheNudge() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, defaults: defaults, nudge: 600, cap: 3_600)
        model.start()
        clock.advance(by: 599)
        model.refresh()

        #expect(!model.isPastNudge)

        clock.advance(by: 1)
        model.refresh()

        #expect(model.isPastNudge)

        model.pause()

        #expect(!model.isPastNudge)
    }

    @Test(
        "SES-3, SES-4: Practice next refreshes when the session reaches the nudge, then the cap, and not while paused")
    func nextRefreshIsTheNudgeThenTheCap() {
        let start = clock.now
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, defaults: defaults, nudge: 600, cap: 3_600)
        #expect(model.nextRefresh == nil)
        model.start()

        #expect(model.nextRefresh == start + 600)

        clock.advance(by: 600)

        #expect(model.nextRefresh == start + 3_600)

        model.pause()

        #expect(model.nextRefresh == nil)
    }

    @Test(
        "SES-3: \"I stopped earlier\" ends in the picked minute at the start's seconds: 2:00 to 3:00 lasts an hour",
        arguments: [17, 33, 50.25] as [TimeInterval])
    func stopAtThePickedTime(startSeconds: TimeInterval) {
        let minute = clock.now
        clock.advance(by: startSeconds)
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, defaults: defaults, nudge: 600, cap: 14_400)
        model.start()
        clock.advance(by: 5_400)  // 90 minutes in

        model.stop(at: minute + 3_641)  // the wheels' minute an hour in, at whatever seconds they kept

        #expect(model.session == nil)
        #expect(model.lastSession?.endedAt == minute + 3_600 + startSeconds)
        #expect(model.lastSession?.elapsed(at: .distantPast) == 3_600)
    }

    @Test("SES-3: a picked end in the current minute never goes past now")
    func stopAtThePickedTimeNotPastNow() {
        let minute = clock.now
        clock.advance(by: 50)
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, defaults: defaults, nudge: 600, cap: 3_600)
        model.start()
        clock.advance(by: 1_950)  // now is 33:20 past the minute

        model.stop(at: minute + 1_990)  // 33:10; at the start's seconds it would be 33:50, after now

        #expect(model.lastSession?.endedAt == minute + 2_000)
    }

    @Test("SES-3: a picked time before the last resume, or in the minute it falls in, ends the session at the resume")
    func stopAtThePickedTimeKeepsTheResume() {
        let start = clock.now
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, defaults: defaults, nudge: 600, cap: 3_600)
        model.start()
        clock.advance(by: 100)
        model.pause()
        clock.advance(by: 300)
        model.resume()  // 6:40 in
        clock.advance(by: 2_000)

        model.stop(at: start + 390)  // 6:30 in, before the resume, as when the clock steps back

        #expect(model.session == nil)
        #expect(model.lastSession?.endedAt == start + 400)
    }

    @Test("SES-3: after a pause, a picked time takes the start's seconds, not the resume's")
    func stopAtThePickedTimeAfterAPause() {
        let start = clock.now
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, defaults: defaults, nudge: 600, cap: 3_600)
        model.start()
        clock.advance(by: 100)
        model.pause()
        clock.advance(by: 300)
        model.resume()  // 6:40 in
        clock.advance(by: 2_000)

        model.stop(at: start + 1_210)  // the wheels' 20th minute

        #expect(model.lastSession?.endedAt == start + 1_200)
        #expect(model.lastSession?.elapsed(at: .distantPast) == 900)
    }

    @Test("SES-3: the notification waits for the running session's practice to reach the nudge")
    func notificationWaitsForTheNudge() throws {
        let model = makeModel()
        model.start()
        let id = try #require(model.session?.id)
        #expect(nudges.pending?.delay == 5_400)
        #expect(nudges.pending?.sessionID == id)

        clock.advance(by: 600)
        model.pause()
        #expect(nudges.pending == nil)

        clock.advance(by: 300)
        model.resume()
        #expect(nudges.pending?.delay == 4_800)
        #expect(nudges.pending?.sessionID == id)

        model.stop()
        #expect(nudges.pending == nil)
    }

    @Test("SES-3: once practice passes the nudge, Practice asks and no notification waits, so it comes once")
    func notificationComesOnce() {
        let model = makeModel()
        model.start()
        clock.advance(by: 5_400)

        model.refresh()

        #expect(model.isAskingStillPracticing)
        #expect(nudges.pending == nil)
    }

    @Test("SES-3: an answer, from the banner or the notification, is kept after a relaunch")
    func answerIsKept() throws {
        let store = InMemoryRunningSessionStore()
        let model = makeModel(over: store)
        model.start()
        clock.advance(by: 5_400)
        model.refresh()

        model.answerStillPracticing(for: try #require(model.session?.id))

        #expect(!model.isAskingStillPracticing)
        #expect(!makeModel(over: store).isAskingStillPracticing)
    }

    @Test("SES-3: a Pause or Resume past the nudge answers the question, and one before it doesn't")
    func pauseAnswersPastTheNudge() {
        let model = makeModel()
        model.start()
        clock.advance(by: 5_399)
        model.pause()
        model.resume()
        #expect(model.answeredID == nil)

        clock.advance(by: 1)
        model.pause()

        #expect(model.answeredID == model.session?.id)
    }

    @Test("SES-3: a Resume past the nudge answers too, for a session paused there by a version that didn't ask")
    func resumeAnswersPastTheNudge() {
        let store = InMemoryRunningSessionStore()
        let older = makeModel(over: store)
        older.start()
        clock.advance(by: 5_400)
        older.pause()
        defaults.removeObject(forKey: "stillPracticingAnswered")

        let model = makeModel(over: store)
        model.resume()

        #expect(model.answeredID == model.session?.id)
    }

    @Test("SES-3: Practice offers the notification until it's asked for, as the system asks once")
    func notificationIsOfferedUntilAsked() async {
        let model = makeModel()
        #expect(!model.canAskForNudges, "Offered before the system says it can ask")
        await model.checkNudges()
        #expect(model.canAskForNudges)

        await model.askForNudges()
        #expect(!model.canAskForNudges)

        await model.checkNudges()
        #expect(!model.canAskForNudges)
    }

    @Test("SES-3: the notification opens Practice to the question, or with \"I stopped earlier\" to picking the end")
    func notificationOpensPractice() {
        let model = makeModel()
        let id = UUID()

        model.open(fromNudgeAbout: id, pickingEnd: true)

        #expect(model.nudgeOpened == NudgeOpening(sessionID: id, pickingEnd: true))
    }

    // MARK: MIDI-1: sessions from the piano

    @Test("MIDI-1: three notes within 10 s start a MIDI session at the first of them")
    func threeNotesStartAMIDISession() {
        let model = makeModel()
        let firstNote = clock.now
        model.noteOn(at: firstNote)
        clock.advance(by: 0.3)
        model.noteOn(at: clock.now)
        #expect(model.session == nil)

        clock.advance(by: 0.3)
        model.noteOn(at: clock.now)

        #expect(model.session?.source == .midi)
        #expect(model.session?.state == .running)
        #expect(model.session?.startedAt == firstNote)
    }

    @Test("MIDI-R4: notes during a session started by tapping don't count toward a MIDI session, then or after it")
    func notesDuringATimerSessionStartNoSecondSession() {
        let model = makeModel()
        model.start()
        clock.advance(by: 600)
        model.noteOn(at: clock.now)
        model.noteOn(at: clock.now)
        #expect(model.session?.source == .timer)

        model.stop()
        model.noteOn(at: clock.now)

        #expect(model.session == nil)
        #expect(model.lastSession?.source == .timer)
    }

    @Test(
        "MIDI-R4: Stop on a MIDI session ends it at the earlier of the tap and 5 s after its last note",
        arguments: [(tappedAfter: 2.0, endsAfter: 2.0), (30, 5)])
    func stopOnAMIDISessionEndsAtTheEarlierMoment(tappedAfter: TimeInterval, endsAfter: TimeInterval) {
        let model = makeModel()
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        // Notes under a minute apart, so no silence pauses the session first.
        for _ in 1...2 {
            clock.advance(by: 35)
            model.noteOn(at: clock.now)
        }
        clock.advance(by: tappedAfter)

        model.stop()

        #expect(model.session == nil)
        #expect(model.lastSession?.endedAt == start + 70 + endsAfter)
        #expect(model.lastSession?.elapsed(at: clock.now) == 70)
        #expect(!model.lastRunWasTooShort)
    }

    @Test("MIDI-1: a Stop with under a minute of played time discards the MIDI session, and Practice says so")
    func aShortMIDIStopSaysTooShortToSave() {
        let history = InMemorySessionHistory()
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, defaults: defaults, nudge: 5_400, cap: 14_400)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 59)
        model.noteOn(at: clock.now)
        clock.advance(by: 30)

        model.stop()

        #expect(model.session == nil)
        #expect(model.lastRunWasTooShort)
        #expect(history.sessions().isEmpty)
    }

    @Test(
        "MIDI-1: \"Too short to save\" shows until the next start, by tapping or by playing", arguments: [false, true])
    func tooShortClearsOnTheNextStart(byPlaying: Bool) {
        let model = makeModel()
        for _ in 1...3 { model.noteOn(at: clock.now) }
        model.stop()
        #expect(model.lastRunWasTooShort)
        clock.advance(by: 60)

        if byPlaying {
            for _ in 1...3 { model.noteOn(at: clock.now) }
        } else {
            model.start()
        }

        #expect(model.session?.state == .running)
        #expect(!model.lastRunWasTooShort)
    }

    @Test("MIDI-1: a MIDI session that history and the outbox can't take isn't called too short; the error shows")
    func aFailedArchiveIsntTooShort() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: FlakyHistory(), outbox: UnavailableOutbox(), clock: clock,
            nudges: nudges, defaults: defaults, nudge: 5_400, cap: 14_400)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        // Notes under a minute apart, so no silence pauses the session first.
        for _ in 1...3 {
            clock.advance(by: 30)
            model.noteOn(at: clock.now)
        }

        model.stop()

        #expect(model.session?.state == .ended)
        #expect(model.isShowingStorageError)
        #expect(!model.lastRunWasTooShort)
    }

    @Test("MIDI-1: a Stop dated before the last note, as after the clock steps back, ends the session at that note")
    func aStopDatedBeforeTheLastNoteNeverThrows() {
        let model = makeModel()
        // A ManualClock can't step back, so the notes are dated later than it reads.
        let lastNote = clock.now + 100
        for _ in 1...3 { model.noteOn(at: lastNote) }
        clock.advance(by: 2)

        model.stop()

        #expect(model.session == nil)
        #expect(model.lastRunWasTooShort)
    }

    @Test("MIDI-R4: Stop after a tapped Pause ends the MIDI session at the tap, within 5 s of the pause")
    func stopAfterATappedPauseEndsAtTheTap() {
        let model = makeModel()
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        clock.advance(by: 90)
        model.pause()
        clock.advance(by: 2)

        model.stop()

        #expect(model.lastSession?.endedAt == start + 92)
        #expect(model.lastSession?.elapsed(at: clock.now) == 90)
    }

    @Test("SES-3, MIDI-R4: a note on a session started by tapping, past the nudge, answers \"Still practicing?\"")
    func aNoteOnATimerSessionPastTheNudgeAnswersStillPracticing() {
        let model = makeModel()
        model.start()
        clock.advance(by: 5_400)
        model.refresh()
        #expect(model.isAskingStillPracticing)

        model.noteOn(at: clock.now)

        #expect(!model.isAskingStillPracticing)
        #expect(model.session?.source == .timer)
    }

    @Test("SES-3: a note before the nudge leaves the question to be asked")
    func aNoteBeforeTheNudgeChangesNothing() {
        let model = makeModel()
        model.start()
        clock.advance(by: 5_399)

        model.noteOn(at: clock.now)

        #expect(model.answeredID == nil)
        clock.advance(by: 1)
        model.refresh()
        #expect(model.isAskingStillPracticing)
    }

    // MARK: MIDI-1: a silence pauses, a note resumes, a longer silence ends

    @Test(
        "MIDI-1: a minute's silence pauses the MIDI session at its last note, and Practice says so; a note resumes it")
    func aSilencePausesTheSessionAtItsLastNote() {
        let model = makeModel()
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        clock.advance(by: 20)
        model.noteOn(at: clock.now)
        #expect(model.nextRefresh == start + 80)
        clock.advance(by: 60)

        model.tick()

        #expect(model.session?.pauses.map(\.start) == [start + 20])
        #expect(model.isPausedAtLastNote)
        #expect(model.nextRefresh == start + 620)

        clock.advance(by: 10)
        model.noteOn(at: clock.now)
        #expect(model.session?.state == .running)
        #expect(model.session?.pauses.map { [$0.start, $0.end] } == [[start + 20, start + 90]])
        #expect(!model.isPausedAtLastNote)
    }

    @Test("MIDI-1: a tapped Pause says just \"Paused\", and left alone 10 minutes ends the session 5 s after the tap")
    func aTappedPauseEndsAfterTheSaveTimeout() {
        let model = makeModel()
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        for _ in 1...3 {
            clock.advance(by: 30)
            model.noteOn(at: clock.now)
        }
        clock.advance(by: 2)
        model.pause()
        #expect(!model.isPausedAtLastNote)
        clock.advance(by: 600)

        model.tick()

        #expect(model.session == nil)
        #expect(model.lastSession?.endedAt == start + 97)
        #expect(model.lastSession?.elapsed(at: clock.now) == 92)
    }

    @Test(
        "MIDI-R3: back after half an hour, a MIDI session has ended 5 s after its last note, whether a note or the tick comes first",
        arguments: [false, true])
    func aSessionLeftForHalfAnHourEndsAfterItsLastNote(noteFirst: Bool) {
        let model = makeModel()
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        for _ in 1...2 {
            clock.advance(by: 30)
            model.noteOn(at: clock.now)
        }
        clock.advance(by: 1_800)

        // A note CoreMIDI delivers before the app's own tick can't fill the absence.
        if noteFirst { model.noteOn(at: clock.now) }
        model.tick()

        #expect(model.session == nil)
        #expect(model.lastSession?.endedAt == start + 65)
        #expect(model.lastSession?.elapsed(at: clock.now) == 60)
        #expect(!model.lastRunWasTooShort)
    }

    @Test("MIDI-R3: relaunched after a silence, Practice opens with the MIDI session paused at its last change")
    func aRelaunchAppliesTheSilenceSince() {
        let store = InMemoryRunningSessionStore()
        let start = clock.now
        let before = makeModel(over: store)
        for _ in 1...3 { before.noteOn(at: start) }
        clock.advance(by: 61)

        let model = makeModel(over: store)

        #expect(model.session?.pauses.map(\.start) == [start])
        #expect(model.isPausedAtLastNote)
    }

    @Test("MIDI-1: killed while away, a MIDI session reopens paused at its last note, not at its last change")
    func aKillWhileAwayKeepsTheLastNote() {
        let store = InMemoryRunningSessionStore()
        let start = clock.now
        let before = makeModel(over: store)
        for _ in 1...3 { before.noteOn(at: start) }
        clock.advance(by: 40)
        before.noteOn(at: clock.now)
        before.leaveForeground()
        clock.advance(by: 61)

        let model = makeModel(over: store)

        #expect(model.session?.pauses.map(\.start) == [start + 40])
        #expect(model.session?.elapsed(at: clock.now) == 40)
    }

    @Test("MIDI-1: leaving the screen stores nothing for a timer session or a paused MIDI one")
    func leavingStoresNothingWithoutANoteToKeep() {
        let store = InMemoryRunningSessionStore()
        let model = makeModel(over: store)
        model.start()
        model.leaveForeground()
        #expect(store.current()?.lastNoteAt == nil)
        model.stop()

        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 60)
        model.tick()
        model.leaveForeground()

        #expect(store.current()?.state == .paused)
        #expect(store.current()?.lastNoteAt == nil)
    }

    @Test("MIDI-1: a MIDI session that a silence ends with under a minute played isn't saved, and Practice says so")
    func aShortRunEndedByTheTimeoutSaysTooShortToSave() {
        let history = InMemorySessionHistory()
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, defaults: defaults, nudge: 5_400, cap: 14_400)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 600)

        model.tick()

        #expect(model.session == nil)
        #expect(model.lastRunWasTooShort)
        #expect(history.sessions().isEmpty)
    }

    @Test("MIDI-1: the timeouts and the shortest MIDI session kept come from the settings")
    func theTimeoutsComeFromTheSettings() {
        var settings = MIDISettings()
        settings.pauseAfter = 10
        settings.saveAfter = 20
        settings.minimumPlayed = 2
        let history = InMemorySessionHistory()
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, defaults: defaults, nudge: 5_400, cap: 14_400, midi: settings)
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        clock.advance(by: 3)
        model.noteOn(at: clock.now)
        #expect(model.nextRefresh == start + 13)
        clock.advance(by: 20)

        model.tick()

        #expect(model.session == nil)
        #expect(history.sessions().map { $0.elapsed(at: clock.now) } == [3])
    }

    @Test("SES-3, SES-4: a MIDI session isn't asked \"Still practicing?\", by banner or notification, or capped")
    func aMIDISessionIsntAskedStillPracticingOrCapped() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, defaults: defaults, nudge: 100, cap: 200)
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        #expect(nudges.pending == nil)
        for _ in 1...8 {
            clock.advance(by: 30)
            model.noteOn(at: clock.now)
        }
        clock.advance(by: 10)

        model.tick()

        #expect(model.session?.state == .running)
        #expect(!model.isAskingStillPracticing)
        #expect(nudges.pending == nil)
        #expect(model.nextRefresh == start + 300)
    }

    @Test(
        "MIDI-R5 (its first half): the screen stays on while a MIDI session lasts, pauses included, and not for a timer session"
    )
    func aMIDISessionKeepsTheScreenAwakeUntilItEnds() {
        let model = makeModel()
        #expect(!model.keepsScreenAwake)
        model.start()
        #expect(!model.keepsScreenAwake)
        clock.advance(by: 60)
        model.stop()

        for _ in 1...3 { model.noteOn(at: clock.now) }
        #expect(model.keepsScreenAwake)
        clock.advance(by: 60)
        model.tick()
        #expect(model.session?.state == .paused)
        #expect(model.keepsScreenAwake)
        clock.advance(by: 600)
        model.tick()
        #expect(model.session == nil)
        #expect(!model.keepsScreenAwake)
    }

    /// A model over `store`, with the app's nudge and cap.
    private func makeModel(over store: InMemoryRunningSessionStore = InMemoryRunningSessionStore()) -> PracticeModel {
        PracticeModel(
            store: store, history: InMemorySessionHistory(), outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, defaults: defaults, nudge: 5_400, cap: 14_400)
    }
}
