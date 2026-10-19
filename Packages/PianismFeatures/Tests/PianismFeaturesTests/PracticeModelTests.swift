import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
struct PracticeModelTests {
    let clock = ManualClock()

    @Test("ADR 0007: Practice counts the sessions waiting to be saved, until history takes them")
    func countsWaitingSessions() {
        let history = FlakyHistory()
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock,
            nudge: 90 * 60, cap: 4 * 60 * 60)
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
            store: store, history: history, outbox: InMemorySessionHistory(), clock: clock, nudge: 90 * 60, cap: 600
        ).start()
        clock.advance(by: 36_000)

        let reopened = PracticeModel(
            store: store, history: history, outbox: InMemorySessionHistory(), clock: clock, nudge: 90 * 60, cap: 600)

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
            clock: clock, nudge: 90 * 60, cap: 600)
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
            clock: clock, nudge: 600, cap: 3_600)
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
            clock: clock, nudge: 600, cap: 3_600)
        #expect(model.nextRefresh == nil)
        model.start()

        #expect(model.nextRefresh == start + 600)

        clock.advance(by: 600)

        #expect(model.nextRefresh == start + 3_600)

        model.pause()

        #expect(model.nextRefresh == nil)
    }

    @Test("SES-3: \"I stopped earlier\" ends the session at the picked time, and it becomes the last session")
    func stopAtThePickedTime() {
        let start = clock.now
        let model = PracticeModel(
            store: InMemoryRunningSessionStore(), history: InMemorySessionHistory(), outbox: InMemorySessionHistory(),
            clock: clock, nudge: 600, cap: 3_600)
        model.start()
        clock.advance(by: 2_000)

        model.stop(at: start + 700)

        #expect(model.session == nil)
        #expect(model.lastSession?.endedAt == start + 700)
    }
}
