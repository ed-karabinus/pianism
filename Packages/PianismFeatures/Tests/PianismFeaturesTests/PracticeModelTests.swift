import Foundation
import PianismCore
import PianismCoreTestSupport
import Synchronization
import Testing

@testable import PianismFeatures

@MainActor
@Suite(.serialized)  // The tests share the stand-in for the device's settings.
struct PracticeModelTests {
    let clock = ManualClock()
    let nudges = InMemoryNudges()
    let glance = InMemoryPracticeGlance()
    private let voiceOver = HeardByVoiceOver()
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
            nudges: nudges, glance: glance, defaults: defaults, nudge: 90 * 60, cap: 4 * 60 * 60)
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

    @Test("ADR 0011: a saved session reaches analytics once, even by way of the outbox; one too short to keep doesn't")
    func aSavedSessionReachesAnalyticsOnce() {
        let recording = RecordingAnalytics()
        let history = FlakyHistory()
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, glance: glance, defaults: defaults, nudge: 90 * 60, cap: 4 * 60 * 60,
            analytics: AnalyticsModel(analytics: recording, defaults: defaults, clock: clock))

        model.start()
        clock.advance(by: 5)
        model.stop()
        #expect(recording.sent == [.firstLaunch])

        model.start()
        clock.advance(by: 600)
        model.stop()
        history.heal()
        model.refresh()
        #expect(recording.sent == [.firstLaunch, .sessionSaved(.timer)])
    }

    @Test("NFR-10: only a running session is counting, so the screen needn't tick otherwise")
    func onlyARunningSessionIsCounting() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 90 * 60, cap: 4 * 60 * 60)
        #expect(!model.isCounting)

        model.start()
        #expect(model.isCounting)

        model.pause()
        #expect(!model.isCounting)

        model.resume()
        #expect(model.isCounting)

        model.stop()
        #expect(!model.isCounting)
    }

    @Test("SES-4: a session left running ends at the cap when the app next opens, and a banner says so until Start")
    func capEndsASessionLeftRunning() {
        let store = InMemoryRunningSessionStore()
        let history = InMemorySessionHistory()
        let start = clock.now
        PracticeModel(
            store: store, history: history, outbox: InMemorySessionHistory(), clock: clock, nudges: nudges,
            glance: glance, defaults: defaults, nudge: 90 * 60, cap: 600
        ).start()
        clock.advance(by: 36_000)

        let reopened = PracticeModel(
            store: store, history: history, outbox: InMemorySessionHistory(), clock: clock, nudges: nudges,
            glance: glance, defaults: defaults, nudge: 90 * 60, cap: 600)

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
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 90 * 60, cap: 600)
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

    @Test("GLN-2: each refresh shows the stored session outside the app, and nothing once it's archived or dropped")
    func showsTheStoredSessionOutsideTheApp() throws {
        let model = makeModel()
        #expect(glance.shownSessions == [nil])

        model.start()
        let session = try #require(model.session)
        #expect(glance.shownSessions.suffix(1) == [session])

        clock.advance(by: 600)
        model.pause()
        let paused = try #require(model.session)
        #expect(paused.state == .paused && paused.id == session.id)
        #expect(glance.shownSessions.suffix(1) == [paused])

        model.resume()
        clock.advance(by: 600)
        model.stop()
        #expect(glance.shownSessions.suffix(1) == [nil])
        #expect(model.lastSession?.id == session.id)

        // Under 10 s of practice is dropped rather than archived (SES-1); it's gone from the widget all the same.
        model.start()
        model.stop()
        #expect(glance.shownSessions.suffix(1) == [nil])
        #expect(model.lastSession == nil)
    }

    @Test("GLN-1, MIDI-1: a MIDI session shows outside the app stopped at the last note heard as the app leaves")
    func aMIDISessionShowsStoppedAtItsLastNoteOnceTheAppLeaves() {
        let model = makeModel()
        let first = clock.now
        for _ in 1...3 { model.noteOn(at: first) }
        model.noteOn(at: first + 20)
        clock.advance(by: 25)

        model.leaveForeground()

        let shown = glance.shownSessions.last??.pausedAwayAt
        #expect(shown == first + 20)
        #expect(glance.shownSaveAfter == 600)

        model.saveAfter = 300

        #expect(glance.shownSaveAfter == 300, "The Live Activity goes stale when the new save would end it")
    }

    @Test("GLN-1: the glance learns whether the app is on screen, which it isn't until it comes to the front")
    func theGlanceLearnsWhetherTheAppIsOnScreen() {
        let model = makeModel()
        model.tick()
        #expect(glance.shownOnScreen == false, "A Live Activity's button can launch the app in the background")

        model.cameToFront()
        #expect(glance.shownOnScreen == true)

        model.leaveForeground()
        #expect(glance.shownOnScreen == false, "Shown again as the app leaves, with no note to store")
    }

    @Test("GLN-1, MIDI-1: a silence-paused MIDI session resumed from the Lock Screen shows stopped at the resume")
    func aMIDISessionResumedWhileAwayShowsStoppedAtTheResume() throws {
        let model = makeModel()
        let first = clock.now
        for _ in 1...3 { model.noteOn(at: first) }
        model.noteOn(at: first + 30)
        clock.advance(by: 90)
        model.tick()
        #expect(model.session?.state == .paused, "A minute's silence pauses it")
        // Paused, so the app stores no note as it leaves.
        model.leaveForeground()
        clock.advance(by: 100)

        model.resume()

        let shown = try #require(glance.shownSessions.last ?? nil)
        #expect(glance.shownOnScreen == false)
        #expect(shown.countsOnlyInApp)
        #expect(shown.pausedAwayAt == first + 190)
        #expect(shown.endsByItself(cap: nil, saveAfter: 600, appOnScreen: false) == first + 790)
    }

    @Test(
        "SES-4, GLN-1: a Pause, Stop or tag change after the cap ends the session at the cap instead, dropping the tag",
        arguments: ["pause", "stop", "setTags"])
    func aLateCommandCapsTheSession(command: String) {
        let history = InMemorySessionHistory()
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, glance: glance, defaults: defaults, nudge: 90 * 60, cap: 600)
        model.start()
        let start = clock.now
        clock.advance(by: 1_000)

        switch command {
        case "pause": model.pause()
        case "stop": model.stop()
        default: model.setTags(["late"])
        }

        #expect(model.session == nil)
        #expect(history.sessions().map(\.endedAt) == [start + 600])
        #expect(history.sessions().map(\.tagIDs) == [[]])
        #expect(model.lastSessionReachedCap)
        #expect(glance.shownSessions.suffix(1) == [nil])
    }

    @Test("GLN-1: a timer session is shown with the cap, so its clock stops there, and a MIDI session with none")
    func aMIDISessionIsShownWithNoCap() {
        let model = makeModel()
        model.start()
        #expect(glance.shownCaps.suffix(1) == [14_400])
        clock.advance(by: 600)
        model.stop()

        for _ in 1...3 { model.noteOn(at: clock.now) }

        #expect(model.session?.source == .midi)
        #expect(glance.shownSessions.suffix(1) == [model.session])
        #expect(glance.shownCaps.suffix(1) == [nil])
    }

    @Test("GLN-1: the shown session is nil once the cap ends it")
    func nothingIsShownOnceTheCapEndsTheSession() {
        let store = InMemoryRunningSessionStore()
        let model = makeModel(over: store)
        model.start()
        #expect(glance.shownSessions.suffix(1) == [model.session])

        clock.advance(by: 20_000)
        model.refresh()

        #expect(model.lastSessionReachedCap)
        #expect(glance.shownSessions.suffix(1) == [nil])
        #expect(store.current() == nil)
    }

    @Test("SES-3: Practice asks once a running session's practice passes the nudge, and not while it's paused")
    func asksPastTheNudge() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 600, cap: 3_600)
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
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 600, cap: 3_600)
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
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 600, cap: 14_400)
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
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 600, cap: 3_600)
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
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 600, cap: 3_600)
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
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 600, cap: 3_600)
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
        nudges.setPermission(.allowed)
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

    @Test("SET-1: Practice stops offering the notification after a Don't Allow, and Settings can say why")
    func aDenialIsKnown() async {
        let denying = InMemoryNudges(answer: .denied)
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: denying, glance: glance, defaults: defaults, nudge: 5_400, cap: 14_400)

        await model.askForNudges()

        #expect(model.notificationPermission == .denied)
        #expect(!model.canAskForNudges)
        #expect(!model.notifiesWhenAway)
    }

    @Test("SET-1, SES-3: with the notification off, no nudge waits and the banner doesn't offer it")
    func theSwitchOffMeansNoNudge() async {
        nudges.setPermission(.allowed)
        let model = makeModel()
        await model.checkNudges()
        model.start()
        #expect(nudges.pending != nil)

        model.notifiesWhenAway = false

        #expect(nudges.pending == nil)
        #expect(defaults.object(forKey: SettingsKey.notifiesStillPracticing) as? Bool == false)
        // Practice still asks in the app past the nudge.
        clock.advance(by: 5_400)
        model.refresh()
        #expect(model.isAskingStillPracticing)

        // Offered with the system yet to ask (`notificationIsOfferedUntilAsked`), but not with the switch off.
        nudges.setPermission(.notAsked)
        await model.checkNudges()
        #expect(!model.canAskForNudges)
        let reopened = makeModel()
        await reopened.checkNudges()
        #expect(!reopened.canAskForNudges, "The setting wasn't kept")
    }

    @Test("SET-1: the switch reads on only while the system allows notifications, and turns on again with it")
    func theSwitchFollowsTheSystem() async {
        let model = makeModel()
        #expect(!model.notifiesWhenAway)

        nudges.setPermission(.allowed)
        await model.checkNudges()
        #expect(model.notifiesWhenAway)

        nudges.setPermission(.denied)
        await model.checkNudges()
        #expect(!model.notifiesWhenAway)

        nudges.setPermission(.allowed)
        await model.checkNudges()
        #expect(model.notifiesWhenAway)
    }

    @Test("SET-1: turning the switch on asks the system if it hasn't asked, and adds the running session's nudge")
    func turningOnAsks() async throws {
        let model = makeModel()
        model.notifiesWhenAway = false
        model.start()

        model.notifiesWhenAway = true

        // The setter asks in a task of its own. The fake, like the system, refuses the nudge until it's allowed.
        let deadline = ContinuousClock.now + .seconds(10)
        while nudges.pending == nil {
            try #require(ContinuousClock.now < deadline, "The running session's nudge wasn't added")
            await Task.yield()
        }
        #expect(nudges.permission() == .allowed)
        #expect(model.notifiesWhenAway)
    }

    @Test("SET-1: the daily reminder is off by default and adds nothing, even with notifications allowed")
    func theReminderIsOffByDefault() async {
        nudges.setPermission(.allowed)
        let model = makeModel()
        await model.checkNudges()

        #expect(!model.remindsDaily)
        #expect(nudges.waitingReminders.isEmpty)
    }

    @Test("SET-1: turning the reminder on asks if the system hasn't, then adds 14 days at 6:00 PM; off takes them away")
    func turningTheReminderOnAndOff() async throws {
        let model = makeModel()
        model.remindsDaily = true

        // The setter asks in a task of its own, as `turningOnAsks` explains.
        let deadline = ContinuousClock.now + .seconds(10)
        while nudges.waitingReminders.isEmpty {
            try #require(ContinuousClock.now < deadline, "The reminders weren't added")
            await Task.yield()
        }
        #expect(nudges.permission() == .allowed)
        #expect(model.remindsDaily)
        #expect(nudges.waitingReminders.count == 14)
        #expect(nudges.waitingReminders.allSatisfy { $0.hour == 18 && $0.minute == 0 })

        model.remindsDaily = false

        #expect(nudges.waitingReminders.isEmpty)
        #expect(!model.remindsDaily)
    }

    @Test("SET-1: a new time moves the reminders at once and is kept, as is the switch")
    func theReminderTimeMovesAndIsKept() async throws {
        nudges.setPermission(.allowed)
        let model = makeModel()
        await model.checkNudges()
        model.remindsDaily = true
        let calendar = Calendar.autoupdatingCurrent

        model.dailyReminderTime = try #require(calendar.date(bySettingHour: 7, minute: 45, second: 0, of: clock.now))

        #expect(nudges.waitingReminders.allSatisfy { $0.hour == 7 && $0.minute == 45 })
        #expect(calendar.component(.hour, from: model.dailyReminderTime) == 7)
        #expect(calendar.component(.minute, from: model.dailyReminderTime) == 45)

        let reopened = makeModel()
        await reopened.checkNudges()
        #expect(reopened.remindsDaily)
        #expect(calendar.component(.minute, from: reopened.dailyReminderTime) == 45)
    }

    @Test("SET-1: the reminder reads off and adds nothing without the system's permission, and comes back with it")
    func theReminderFollowsTheSystem() async {
        nudges.setPermission(.denied)
        let model = makeModel()
        await model.checkNudges()
        model.remindsDaily = true
        await model.checkNudges()

        #expect(!model.remindsDaily)
        #expect(nudges.waitingReminders.isEmpty)

        nudges.setPermission(.allowed)
        await model.checkNudges()

        #expect(model.remindsDaily)
        #expect(nudges.waitingReminders.count == 14)
    }

    @Test("SET-1: coming to the front tops the reminders up from today, so they run out only if the app stays closed")
    func comingToTheFrontTopsUpTheReminders() async throws {
        nudges.setPermission(.allowed)
        defaults.set(true, forKey: SettingsKey.remindsDaily)
        let model = makeModel()
        await model.checkNudges()
        let first = try #require(nudges.waitingReminders.first)

        clock.advance(by: 3 * 24 * 60 * 60)
        model.cameToFront()

        let deadline = ContinuousClock.now + .seconds(10)
        while nudges.waitingReminders.first == first {
            try #require(ContinuousClock.now < deadline, "The reminders weren't topped up")
            await Task.yield()
        }
        #expect(nudges.waitingReminders.count == 14)
        #expect(
            nudges.waitingReminders.first
                == DailyReminder.dates(
                    atMinute: 18 * 60, after: clock.now, skippingToday: false, in: .autoupdatingCurrent
                ).first)
    }

    /// The first reminder if today counts as practiced or not. The clock starts before 6:00 PM in every time zone.
    private func firstReminder(skippingToday: Bool) -> DateComponents? {
        DailyReminder.dates(
            atMinute: 18 * 60, after: clock.now, skippingToday: skippingToday, in: .autoupdatingCurrent
        ).first
    }

    private func secondsToMidnight() throws -> TimeInterval {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: clock.now)
        return try #require(calendar.date(byAdding: .day, value: 1, to: today)).timeIntervalSince(clock.now)
    }

    /// A model with the reminder on, and its reminders planned.
    private func modelReminding(
        history: any SessionHistory = InMemorySessionHistory(),
        outbox: any SessionOutbox = InMemorySessionHistory()
    ) async -> PracticeModel {
        nudges.setPermission(.allowed)
        defaults.set(true, forKey: SettingsKey.remindsDaily)
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: outbox, clock: clock, nudges: nudges,
            glance: glance, defaults: defaults, nudge: 90 * 60, cap: 4 * 60 * 60)
        await model.checkNudges()
        return model
    }

    @Test("SET-1: today's reminder goes as the app leaves with a session going, and stays gone once it's saved")
    func practicingTodayMovesTheReminderToTomorrow() async {
        let model = await modelReminding()
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: false))

        model.start()
        clock.advance(by: 60)
        model.leaveForeground()
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
        #expect(nudges.waitingReminders.count == 14)

        model.cameToFront()
        model.stop()
        model.leaveForeground()
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
    }

    @Test("SET-1: a session running since before midnight counts as practice today")
    func aSessionRunningPastMidnightCountsAsPractice() async throws {
        let model = await modelReminding()
        clock.advance(by: try secondsToMidnight() - 60)
        model.start()

        clock.advance(by: 120)
        model.leaveForeground()

        #expect(model.session?.state == .running)
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
    }

    @Test("SET-1: a session stopped this morning that started last night counts as practice today")
    func aSessionStoppedThisMorningCountsAsPractice() async throws {
        let model = await modelReminding()
        clock.advance(by: try secondsToMidnight() - 60)
        model.start()

        clock.advance(by: 120)
        model.stop()
        model.leaveForeground()

        #expect(model.session == nil)
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
    }

    @Test("SET-1: a few seconds past midnight count as practice today, as History lists them (decided with Ed)")
    func aFewSecondsPastMidnightCountAsPractice() async throws {
        let model = await modelReminding()
        clock.advance(by: try secondsToMidnight() - 60)
        model.start()

        clock.advance(by: 65)
        model.stop()
        model.leaveForeground()

        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
    }

    @Test("SET-1: a session paused this morning after starting last night counts as practice today")
    func aSessionPausedThisMorningCountsAsPractice() async throws {
        let model = await modelReminding()
        clock.advance(by: try secondsToMidnight() - 60)
        model.start()

        clock.advance(by: 120)
        model.pause()
        model.leaveForeground()

        #expect(model.session?.state == .paused)
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
    }

    @Test("SET-1: a session paused through midnight counts only once it has been played again")
    func aSessionPausedThroughMidnightCountsOnceResumed() async throws {
        let model = await modelReminding()
        clock.advance(by: try secondsToMidnight() - 120)
        model.start()
        clock.advance(by: 60)
        model.pause()

        clock.advance(by: 120)
        model.leaveForeground()
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: false))

        model.cameToFront()
        model.resume()
        clock.advance(by: 60)
        model.leaveForeground()
        #expect(model.session?.state == .running)
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
    }

    @Test("SET-1: a session paused on an earlier day doesn't silence today's reminder, as nothing ends it")
    func aSessionPausedYesterdayIsNotPractice() async {
        let model = await modelReminding()
        model.start()
        clock.advance(by: 60)
        model.pause()

        clock.advance(by: 24 * 60 * 60)
        model.leaveForeground()

        #expect(model.session?.state == .paused)
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: false))
    }

    @Test("SET-1: a session stuck after storage failed counts for the day it was played, not the days after")
    func aStuckSessionCountsOnlyForItsDay() async {
        let model = await modelReminding(history: FlakyHistory(), outbox: UnavailableOutbox())
        model.start()
        clock.advance(by: 60)
        model.stop()
        model.leaveForeground()
        #expect(model.session?.state == .ended)
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))

        clock.advance(by: 24 * 60 * 60)
        model.leaveForeground()

        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: false))
    }

    @Test("SET-1: a session paused today counts as practice today")
    func aPausedSessionCountsAsPractice() async {
        let model = await modelReminding()

        model.start()
        clock.advance(by: 60)
        model.pause()
        model.leaveForeground()

        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
    }

    @Test("SET-1: a session that was too short to keep leaves today's reminder alone")
    func aSessionTooShortToKeepIsNoPractice() async {
        let model = await modelReminding()

        model.start()
        clock.advance(by: 5)
        model.stop()
        model.leaveForeground()

        #expect(model.lastSession == nil)
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: false))
    }

    @Test("SET-1: yesterday's practice leaves today's reminder alone")
    func yesterdaysPracticeIsNotToday() async {
        let model = await modelReminding()
        model.start()
        clock.advance(by: 60)
        model.stop()

        clock.advance(by: 24 * 60 * 60)
        model.leaveForeground()

        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: false))
    }

    @Test("SET-1: a session waiting in the outbox counts as practice today, as History shows it")
    func aSessionInTheOutboxCountsAsPractice() async {
        let outbox = InMemorySessionHistory()
        let model = await modelReminding(history: FlakyHistory(), outbox: outbox)
        model.start()
        clock.advance(by: 60)
        model.stop()
        #expect(outbox.sessions().count == 1)

        model.leaveForeground()

        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))
    }

    @Test("SET-1: leaving before the system has answered keeps the reminders, as when a button launches the app")
    func aBackgroundLaunchKeepsTheReminders() async {
        _ = await modelReminding()
        let waiting = nudges.waitingReminders

        // The app's next launch, in the background: it never came to the front, so nothing has asked the system yet.
        makeModel().leaveForeground()

        #expect(nudges.waitingReminders == waiting)
        #expect(waiting.count == 14)
    }

    @Test("SET-1: turning the reminder off before the system has answered still cancels what's waiting")
    func turningItOffNeedsNoAnswer() async {
        _ = await modelReminding()
        #expect(nudges.waitingReminders.count == 14)

        let relaunched = makeModel()
        relaunched.remindsDaily = false

        #expect(nudges.waitingReminders.isEmpty)
    }

    @Test("SET-1: deleting today's only session brings today's reminder back")
    func deletingTodaysPracticeBringsTheReminderBack() async throws {
        let history = InMemorySessionHistory()
        let model = await modelReminding(history: history)
        model.start()
        clock.advance(by: 60)
        model.stop()
        model.leaveForeground()
        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: true))

        let saved = try #require(history.sessions().first)
        try history.delete(id: saved.id)
        model.leaveForeground()

        #expect(nudges.waitingReminders.first == firstReminder(skippingToday: false))
    }

    @Test("SES-3: the notification opens Practice to the question, or with \"I stopped earlier\" to picking the end")
    func notificationOpensPractice() {
        let model = makeModel()
        let id = UUID()

        model.open(fromNudgeAbout: id, pickingEnd: true)

        #expect(model.nudgeOpened == NudgeOpening(sessionID: id, pickingEnd: true))
    }

    @Test("SET-1: tapping the daily reminder opens Practice, with no session's question or end picked")
    func tappingAReminderOpensPractice() {
        let model = makeModel()

        model.openFromReminder()

        #expect(model.nudgeOpened == NudgeOpening(sessionID: nil, pickingEnd: false))
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
        #expect(model.notSaved == nil)
    }

    @Test("MIDI-1: a Stop with under a minute of played time discards the MIDI session, and Practice says so")
    func aShortMIDIStopSaysTooShortToSave() {
        let history = InMemorySessionHistory()
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, glance: glance, defaults: defaults, nudge: 5_400, cap: 14_400)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 59)
        model.noteOn(at: clock.now)
        clock.advance(by: 30)

        model.stop()

        #expect(model.session == nil)
        #expect(model.notSaved == .underAMinuteOfPlaying)
        #expect(history.sessions().isEmpty)
    }

    @Test(
        "MIDI-1: \"Not saved\" shows until the next start, by tapping or by playing", arguments: [false, true])
    func tooShortClearsOnTheNextStart(byPlaying: Bool) {
        let model = makeModel()
        for _ in 1...3 { model.noteOn(at: clock.now) }
        model.stop()
        #expect(model.notSaved == .underAMinuteOfPlaying)
        clock.advance(by: 60)

        if byPlaying {
            for _ in 1...3 { model.noteOn(at: clock.now) }
        } else {
            model.start()
        }

        #expect(model.session?.state == .running)
        #expect(model.notSaved == nil)
    }

    @Test("SES-1: a tapped session under 10 s isn't saved, and Practice says so, to VoiceOver too")
    func aShortTappedSessionSaysNotSaved() {
        // Given a session started by tapping
        let model = makeModel()
        model.start()
        clock.advance(by: 9)

        // When it's stopped before 10 s
        model.stop()

        // Then nothing was kept, and Practice and VoiceOver say why
        #expect(model.session == nil && model.lastSession == nil)
        #expect(model.notSaved == .underTenSeconds)
        #expect(model.notSavedCount == 1)
        #expect(voiceOver.lines == ["Not saved: under 10 seconds"])
    }

    @Test("SES-1, MIDI-1: each session not saved counts, so its pop-up shows again; one that's saved says nothing")
    func eachSessionNotSavedCounts() {
        // Given a tapped session not saved, then a piano's
        let model = makeModel()
        model.start()
        model.stop()
        for _ in 1...3 { model.noteOn(at: clock.now) }
        model.stop()
        #expect(model.notSaved == .underAMinuteOfPlaying)
        #expect(model.notSavedCount == 2)

        // When a session long enough to save ends
        model.start()
        clock.advance(by: 600)
        model.stop()

        // Then it's saved, and nothing says otherwise
        #expect(model.lastSession != nil)
        #expect(model.notSaved == nil)
        #expect(model.notSavedCount == 2)
        #expect(voiceOver.lines == ["Not saved: under 10 seconds", "Not saved: under a minute of playing"])
    }

    @Test("MIDI-1: a MIDI session that history and the outbox can't take isn't called too short; the error shows")
    func aFailedArchiveIsntTooShort() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: FlakyHistory(), outbox: UnavailableOutbox(), clock: clock,
            nudges: nudges, glance: glance, defaults: defaults, nudge: 5_400, cap: 14_400)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        // Notes under a minute apart, so no silence pauses the session first.
        for _ in 1...3 {
            clock.advance(by: 30)
            model.noteOn(at: clock.now)
        }

        model.stop()

        #expect(model.session?.state == .ended)
        #expect(model.isShowingStorageError)
        #expect(model.notSaved == nil)
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
        #expect(model.notSaved == .underAMinuteOfPlaying)
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
        #expect(model.isPausedAtLastNote(at: clock.now))
        #expect(model.nextRefresh == start + 620)

        clock.advance(by: 10)
        model.noteOn(at: clock.now)
        #expect(model.session?.state == .running)
        #expect(model.session?.pauses.map { [$0.start, $0.end] } == [[start + 20, start + 90]])
        #expect(!model.isPausedAtLastNote(at: clock.now))
    }

    @Test("MIDI-1: VoiceOver hears once that a silence paused the session, with the time, and again at the next one")
    func aSilencePauseIsAnnouncedOnce() {
        let model = makeModel()
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        clock.advance(by: 20)
        model.noteOn(at: clock.now)
        #expect(voiceOver.lines.isEmpty)
        clock.advance(by: 60)

        model.tick()
        model.tick()

        #expect(voiceOver.lines == ["Paused at your last note, 20 seconds"])

        clock.advance(by: 10)
        model.noteOn(at: clock.now)
        clock.advance(by: 5)
        model.noteOn(at: clock.now)
        clock.advance(by: 60)
        model.tick()

        #expect(voiceOver.lines.last == "Paused at your last note, 25 seconds")
        #expect(voiceOver.lines.count == 2)
    }

    @Test(
        "MIDI-1: VoiceOver hears nothing of a tapped Pause, a silence that ends the session, or a late note, but that a session wasn't saved"
    )
    func onlyASilencePauseThatStandsIsAnnounced() {
        let tapped = makeModel()
        for _ in 1...3 { tapped.noteOn(at: clock.now) }
        tapped.pause()
        tapped.stop()

        let ended = makeModel()
        for _ in 1...3 { ended.noteOn(at: clock.now) }
        clock.advance(by: 600)
        ended.tick()
        #expect(ended.session == nil)

        // The note shows the silence paused it, and resumes it in the same change.
        let late = makeModel()
        for _ in 1...3 { late.noteOn(at: clock.now) }
        clock.advance(by: 61)
        late.noteOn(at: clock.now)
        #expect(late.session?.state == .running)

        // The first two had under a minute played, so each wasn't saved, which is said (SES-1).
        #expect(voiceOver.lines == Array(repeating: "Not saved: under a minute of playing", count: 2))
    }

    @Test("MIDI-1: VoiceOver hears of a silence that paused the session while away, back in the app")
    func aPauseWhileAwayIsAnnouncedOnReturn() {
        let model = makeModel()
        for _ in 1...3 { model.noteOn(at: clock.now) }
        model.leaveForeground()
        clock.advance(by: 90)

        model.cameToFront()

        #expect(voiceOver.lines == ["Paused at your last note, 0 seconds"])
    }

    @Test("MIDI-1: VoiceOver hears of a silence pause only once the store has taken it")
    func aRefusedPauseIsNotAnnounced() {
        let store = RefusingStore()
        let model = makeModel(over: store)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 60)
        store.refuse(true)

        model.tick()

        #expect(model.session?.state == .running)
        #expect(voiceOver.lines.isEmpty)

        store.refuse(false)
        model.tick()

        #expect(voiceOver.lines == ["Paused at your last note, 0 seconds"])
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
        #expect(!model.isPausedAtLastNote(at: clock.now))
        clock.advance(by: 600)
        #expect(!model.isPausedAtLastNote(at: clock.now))
        #expect(model.elapsed(at: clock.now) == 92)

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
        #expect(model.notSaved == nil)
    }

    @Test(
        "MIDI-1: back on screen before the tick, as from the lock screen, Practice already shows the time and label the tick stores",
        arguments: [60.0, 131, 1_800])
    func aFrameBeforeTheTickShowsWhatTheTickStores(silence: TimeInterval) {
        let store = InMemoryRunningSessionStore()
        let model = makeModel(over: store)
        let start = clock.now
        for _ in 1...3 { model.noteOn(at: start) }
        // A minute played, so the session the longest silence ends is kept.
        for _ in 1...2 {
            clock.advance(by: 30)
            model.noteOn(at: clock.now)
        }
        clock.advance(by: silence)

        #expect(model.elapsed(at: clock.now) == 60)
        #expect(model.isPausedAtLastNote(at: clock.now))
        #expect(store.current()?.state == .running)

        model.tick()

        #expect((model.session ?? model.lastSession)?.elapsed(at: clock.now) == 60)
    }

    @Test("MIDI-1, SES-4: Practice counts through a silence until it pauses, and a timer session until the cap")
    func theShownTimeCountsUntilTheTickWouldStopIt() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 90 * 60, cap: 600)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 18)
        model.noteOn(at: clock.now)
        clock.advance(by: 59)
        #expect(model.elapsed(at: clock.now) == 77)
        #expect(!model.isPausedAtLastNote(at: clock.now))
        model.stop()

        model.start()
        clock.advance(by: 599)
        #expect(model.elapsed(at: clock.now) == 599)
        clock.advance(by: 3_600)
        #expect(model.elapsed(at: clock.now) == 600)
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
        #expect(model.isPausedAtLastNote(at: clock.now))
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
            nudges: nudges, glance: glance, defaults: defaults, nudge: 5_400, cap: 14_400)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 600)

        model.tick()

        #expect(model.session == nil)
        #expect(model.notSaved == .underAMinuteOfPlaying)
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
            nudges: nudges, glance: glance, defaults: defaults, nudge: 5_400, cap: 14_400, midi: settings)
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
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 100, cap: 200)
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
        "MIDI-R5: the screen stays on while a MIDI session lasts, pauses included, and while Practice shows with a piano connected; a timer session alone doesn't"
    )
    func aMIDISessionKeepsTheScreenAwakeUntilItEnds() {
        let model = makeModel()
        #expect(!model.keepsScreenAwake(showingPractice: true))
        model.start()
        #expect(!model.keepsScreenAwake(showingPractice: true))
        clock.advance(by: 60)
        model.stop()

        for _ in 1...3 { model.noteOn(at: clock.now) }
        #expect(model.keepsScreenAwake(showingPractice: true))
        #expect(model.keepsScreenAwake(showingPractice: false))
        clock.advance(by: 60)
        model.tick()
        #expect(model.session?.state == .paused)
        #expect(model.keepsScreenAwake(showingPractice: true))
        clock.advance(by: 600)
        model.tick()
        #expect(model.session == nil)
        #expect(!model.keepsScreenAwake(showingPractice: true))

        model.connectedPianos = ["MIDI KEYBOARD"]
        #expect(model.keepsScreenAwake(showingPractice: true))
        #expect(!model.keepsScreenAwake(showingPractice: false))
    }

    @Test(
        "MIDI-R5 (decided with Ed, 2026-10-28): with a piano connected and no session, Practice keeps the screen on for 15 minutes after the last note, the piano connecting or the app coming to the front"
    )
    func aConnectedPianoKeepsTheScreenOnFifteenMinutes() {
        let model = makeModel()
        clock.advance(by: 3_600)
        model.connectedPianos = ["MIDI KEYBOARD"]
        clock.advance(by: 600)
        model.noteOn(at: clock.now)
        clock.advance(by: 899)
        model.tick()
        #expect(model.keepsScreenAwake(showingPractice: true))

        clock.advance(by: 1)
        model.tick()
        #expect(model.session == nil)
        #expect(!model.keepsScreenAwake(showingPractice: true))

        model.cameToFront()
        #expect(model.keepsScreenAwake(showingPractice: true))
        clock.advance(by: 900)
        model.tick()
        model.connectedPianos = ["MIDI KEYBOARD", "CA59 Bluetooth"]
        #expect(model.keepsScreenAwake(showingPractice: true))

        // After a MIDI session, from its last note.
        clock.advance(by: 10)
        for _ in 1...3 { model.noteOn(at: clock.now) }
        clock.advance(by: 30)
        model.noteOn(at: clock.now)
        clock.advance(by: 660)
        model.tick()
        #expect(model.session == nil)
        clock.advance(by: 239)
        model.tick()
        #expect(model.keepsScreenAwake(showingPractice: true))
        clock.advance(by: 1)
        model.tick()
        #expect(!model.keepsScreenAwake(showingPractice: true))
    }

    @Test("NFR-10: while the screen is kept on, Practice warns of a battery at 20 % or less, unless it's plugged in")
    func aLowBatteryIsShownWhileTheScreenIsKeptOn() {
        let model = makeModel()
        let low = BatteryReading(level: 0.19, isPluggedIn: false)
        model.battery = low
        #expect(!model.showsLowBattery)
        model.start()
        #expect(!model.showsLowBattery)
        model.stop()

        for _ in 1...3 { model.noteOn(at: clock.now) }
        #expect(model.showsLowBattery)
        model.battery = BatteryReading(level: 0.19, isPluggedIn: true)
        #expect(!model.showsLowBattery)
        // As iOS reports them: Floats, in 5 % steps.
        model.battery = BatteryReading(level: Double(Float(0.2)), isPluggedIn: false)
        #expect(model.showsLowBattery)
        model.battery = BatteryReading(level: Double(Float(0.21)), isPluggedIn: false)
        #expect(!model.showsLowBattery)
        model.battery = BatteryReading(level: Double(Float(0.25)), isPluggedIn: false)
        #expect(!model.showsLowBattery)
        model.battery = nil
        #expect(!model.showsLowBattery)

        clock.advance(by: 660)
        model.tick()
        #expect(model.session == nil)
        model.battery = low
        #expect(!model.showsLowBattery)
        model.connectedPianos = ["MIDI KEYBOARD"]
        #expect(model.showsLowBattery)
    }

    @Test("SET-1: nothing stored reads as 90 minutes and 4 hours, and a nudge and cap set in Settings are kept")
    func nudgeAndCapAreKept() {
        #expect(PracticeModel.storedNudge(in: defaults) == 5_400)
        #expect(PracticeModel.storedCap(in: defaults) == 14_400)
        let model = makeModel()

        model.nudge = 1_800
        model.cap = 3_600

        #expect(PracticeModel.storedNudge(in: defaults) == 1_800)
        #expect(PracticeModel.storedCap(in: defaults) == 3_600)
    }

    @Test("SET-1, SES-3: a new nudge reschedules the running session's notification, or asks at once if past it")
    func newNudgeAppliesAtOnce() {
        // Typed, as #expect compares an optional with a bare literal as unequal.
        let quarterHour: TimeInterval = 15 * 60
        nudges.setPermission(.allowed)
        let model = makeModel()
        let start = clock.now
        model.start()
        clock.advance(by: 45 * 60)

        model.nudge = 60 * 60

        #expect(nudges.pending?.delay == quarterHour)
        #expect(model.nextRefresh == clock.now + quarterHour)
        #expect(!model.isAskingStillPracticing)

        model.nudge = 30 * 60

        #expect(nudges.pending == nil)
        #expect(model.isAskingStillPracticing)
        // The wake-up keys on the passed nudge, so it doesn't start over as a deadline passes.
        #expect(model.firstDeadline == start + 30 * 60)
    }

    @Test(
        "SET-1: the nudges offered stop below the cap, the caps start above the nudge, and a running timer locks the cap"
    )
    func choicesKeepTheNudgeBelowTheCap() {
        let model = makeModel()

        #expect(model.nudgeChoices == stride(from: 1_800, through: 12_600, by: 1_800).map(TimeInterval.init))
        #expect(model.capChoices == stride(from: 7_200, through: 28_800, by: 3_600).map(TimeInterval.init))
        #expect(model.canChangeCap)

        model.start()
        #expect(!model.canChangeCap)

        model.pause()
        #expect(!model.canChangeCap, "A paused timer session still runs into the cap once resumed")

        model.stop()
        #expect(model.canChangeCap)

        for _ in 1...3 { model.noteOn(at: clock.now) }
        #expect(model.session?.source == .midi)
        #expect(model.canChangeCap, "A MIDI session isn't capped")
    }

    @Test("SET-1: a nudge and cap a test launches with are offered, so Settings shows them")
    func launchedValuesAreOffered() {
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudges: nudges, glance: glance, defaults: defaults, nudge: 3, cap: 20)

        #expect(model.nudgeChoices == [3])
        #expect(model.capChoices == [20] + stride(from: 3_600, through: 28_800, by: 3_600).map(TimeInterval.init))
    }

    @Test("SET-1: nothing stored reads as 3 notes, 1 minute and 10 minutes; what Settings sets is kept and played by")
    func midiSettingsAreKept() {
        let stored = PracticeModel.storedMIDI(in: defaults)
        #expect((stored.startNotes, stored.pauseAfter, stored.saveAfter) == (3, 60, 600))
        let model = makeModel()

        model.startNotes = 1
        model.pauseAfter = 30
        model.saveAfter = 300

        let kept = PracticeModel.storedMIDI(in: defaults)
        #expect((kept.startNotes, kept.pauseAfter, kept.saveAfter) == (1, 30, 300))
        model.noteOn(at: clock.now)
        #expect(model.session?.source == .midi, "One note starts a session when set to 1")
    }

    @Test("SET-1, MIDI-1: a pause changed while playing moves the wake-up, or pauses at the last note if already past")
    func newPauseAppliesAtOnce() {
        let model = makeModel()
        let lastNote = clock.now
        for _ in 1...3 { model.noteOn(at: lastNote) }
        clock.advance(by: 20)
        let wakeUpMoved = Mutex(false)
        withObservationTracking {
            _ = model.firstDeadline
        } onChange: {
            wakeUpMoved.withLock { $0 = true }
        }

        model.pauseAfter = 30

        #expect(wakeUpMoved.withLock { $0 }, "RootView's wake-up keys on firstDeadline")
        #expect(model.firstDeadline == lastNote + 30)
        #expect(model.session?.state == .running)

        model.pauseAfter = 15

        #expect(model.session?.state == .paused)
        #expect(model.isPausedAtLastNote(at: clock.now))
    }

    @Test("SET-1, MIDI-1: a shorter save ends a session paused by a silence already that long, and saves it")
    func newSaveAppliesAtOnce() {
        let model = makeModel()
        let first = clock.now
        // Played for 100 s, over the minute a MIDI session needs to be kept.
        for _ in 1...3 { model.noteOn(at: first) }
        model.noteOn(at: first + 50)
        model.noteOn(at: first + 100)
        clock.advance(by: 230)
        model.tick()
        #expect(model.session?.state == .paused)
        #expect(model.firstDeadline == first + 100 + 600)

        model.saveAfter = 120

        #expect(model.session == nil)
        #expect(model.lastSession?.endedAt == first + 105, "Ended and saved 5 s after its last note")
    }

    @Test("SET-1: the pauses offered stay below the save, and the saves above the pause")
    func choicesKeepThePauseBelowTheSave() {
        let model = makeModel()

        #expect(model.pauseChoices == [15, 30, 45, 60, 120, 180, 300])
        #expect(model.saveChoices == [120, 300, 600, 900, 1_200, 1_800, 2_700, 3_600])

        model.pauseAfter = 300
        model.saveAfter = 600

        #expect(model.pauseChoices == [15, 30, 45, 60, 120, 180, 300])
        #expect(model.saveChoices == [600, 900, 1_200, 1_800, 2_700, 3_600])

        model.pauseAfter = 60
        model.saveAfter = 120

        #expect(model.pauseChoices == [15, 30, 45, 60])
    }

    /// A model over `store`, with the app's nudge and cap.
    private func makeModel(over store: any RunningSessionStore = InMemoryRunningSessionStore()) -> PracticeModel {
        PracticeModel(
            store: store, history: InMemorySessionHistory(), outbox: InMemorySessionHistory(), clock: clock,
            nudges: nudges, glance: glance, defaults: defaults, nudge: 5_400, cap: 14_400,
            announce: { [voiceOver] in voiceOver.lines.append($0) })
    }
}

/// A store that refuses changes when told to, as a full disk does.
private final class RefusingStore: RunningSessionStore {
    private struct Refused: Error {}

    private let stored = InMemoryRunningSessionStore()
    private let refuses = Mutex(false)

    func refuse(_ refuse: Bool) {
        refuses.withLock { $0 = refuse }
    }

    func current() -> PracticeSession? {
        stored.current()
    }

    func update<Result: Sendable>(_ change: (inout PracticeSession?) throws -> Result) throws -> Result {
        if refuses.withLock({ $0 }) { throw Refused() }
        return try stored.update(change)
    }
}

/// What the model has said to VoiceOver.
@MainActor
private final class HeardByVoiceOver {
    var lines: [String] = []
}
