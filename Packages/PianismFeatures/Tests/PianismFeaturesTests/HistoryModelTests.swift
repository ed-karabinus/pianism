import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
struct HistoryModelTests {
    let clock = ManualClock()
    let outbox = InMemorySessionHistory()

    @Test("ADR 0007: a session both saved and waiting shows once, as saved; one only waiting is marked")
    func savedAndWaitingShowOnce() throws {
        let history = InMemorySessionHistory()
        let both = try endedSession(startingAfter: 0)
        let waiting = try endedSession(startingAfter: 3_600)
        history.save(both)
        outbox.add(both)
        outbox.add(waiting)
        let model = HistoryModel(history: history, outbox: outbox, clock: clock)

        model.refresh()

        let shown = model.days.flatMap(\.sessions)
        #expect(shown.count == 2)
        #expect(Set(shown) == [both, waiting])
        #expect(model.waitingIDs == [waiting.id])
        #expect(!model.loadFailed)
    }

    @Test("ADR 0007: while history can't load, waiting sessions still show, and the failure clears once it loads")
    func waitingShowDuringFailure() throws {
        let history = FlakyHistory()
        let waiting = try endedSession(startingAfter: 0)
        outbox.add(waiting)
        let model = HistoryModel(history: history, outbox: outbox, clock: clock)

        model.refresh()

        #expect(model.loadFailed)
        #expect(model.days.flatMap(\.sessions) == [waiting])
        #expect(model.waitingIDs == [waiting.id])

        history.heal()
        model.refresh()

        #expect(!model.loadFailed)
    }

    @Test("HIS-1: each refresh moves today along, so a screen left open past midnight catches up")
    func refreshMovesToday() {
        let model = HistoryModel(history: InMemorySessionHistory(), outbox: outbox, clock: clock)
        clock.advance(by: 86_400)

        model.refresh()

        #expect(model.now == clock.now)
    }

    private func endedSession(startingAfter seconds: TimeInterval) throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now + seconds)
        try session.stop(at: clock.now + seconds + 600)
        return session
    }
}
