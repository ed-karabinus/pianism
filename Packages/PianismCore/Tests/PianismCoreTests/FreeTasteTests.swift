import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

struct FreeTasteTests {
    let clock = ManualClock()

    @Test("PRO-2: 5 piano sessions are free, then none, never fewer")
    func leftAfterUsing() {
        #expect(FreeTaste.sessions == 5)
        #expect([0, 4, 5, 6].map(FreeTaste.left(afterUsing:)) == [5, 1, 0, 0])
    }

    @Test("PRO-2, ADR 0012: the used ones are the piano's sessions, saved, deleted or waiting, each once, and no other")
    func usedCountsPianoSessionsOnce() throws {
        let history = InMemorySessionHistory()
        let outbox = InMemorySessionHistory()
        let saved = try ended(.midi)
        let deleted = try ended(.midi)
        for session in [saved, deleted, try ended(.timer), try ended(.manual)] { history.save(session) }
        try history.delete(id: deleted.id)
        // One waiting, and one in both, as between saving to history and leaving the outbox. Two that aren't the
        // piano's, so counting only those would come to 4, not 3.
        for session in [try ended(.midi), saved, try ended(.timer), try ended(.manual)] { outbox.add(session) }

        #expect(try FreeTaste.used(history: history, outbox: outbox) == 3)
    }

    @Test("PRO-2: a history that can't be reached can't say how many are used")
    func usedFailsWithHistory() {
        #expect(throws: FlakyHistory.Failure.self) {
            try FreeTaste.used(history: FlakyHistory(), outbox: InMemorySessionHistory())
        }
    }

    private func ended(_ source: PracticeSession.Source) throws -> PracticeSession {
        var session = PracticeSession(startedAt: clock.now, source: source)
        try session.stop(at: clock.now + 600)
        return session
    }
}
