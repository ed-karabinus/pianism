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
            cap: 4 * 60 * 60)
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
        PracticeModel(store: store, history: history, outbox: InMemorySessionHistory(), clock: clock, cap: 600).start()
        clock.advance(by: 36_000)

        let reopened = PracticeModel(
            store: store, history: history, outbox: InMemorySessionHistory(), clock: clock, cap: 600)

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
            clock: clock, cap: 600)
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
}
