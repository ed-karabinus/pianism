import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

/// The ``SessionHistory`` and ``SessionOutbox`` contracts, checked on the fake that core tests rely on.
struct InMemorySessionHistoryTests {
    let clock = ManualClock()

    @Test("As history, saving keeps the first copy of a session; as an outbox, adding replaces it")
    func savingKeepsAddingReplaces() throws {
        var first = PracticeSession(startedAt: clock.now)
        try first.stop(at: clock.now + 600)
        var second = PracticeSession(id: first.id, startedAt: clock.now)
        try second.stop(at: clock.now + 300)
        let history = InMemorySessionHistory()

        history.save(first)
        history.save(second)
        #expect(history.sessions() == [first])

        history.add(second)
        #expect(history.sessions() == [second])
    }
}
