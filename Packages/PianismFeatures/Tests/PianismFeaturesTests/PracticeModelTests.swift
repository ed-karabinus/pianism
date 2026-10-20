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

    /// A model over `store`, with the app's nudge and cap.
    private func makeModel(over store: InMemoryRunningSessionStore = InMemoryRunningSessionStore()) -> PracticeModel {
        PracticeModel(
            store: store, history: InMemorySessionHistory(), outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, defaults: defaults, nudge: 5_400, cap: 14_400)
    }
}
