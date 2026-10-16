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
            store: InMemoryRunningSessionStore(), history: history, outbox: InMemorySessionHistory(), clock: clock)
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
}
