import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

/// The ``RunningSessionStore`` contract, checked on the fake that core tests rely on.
struct InMemoryRunningSessionStoreTests {
    let clock = ManualClock()

    @Test("An update stores the changed session and returns what the change returns")
    func updateStoresChange() throws {
        let store = InMemoryRunningSessionStore()
        let session = PracticeSession(startedAt: clock.now)

        let result = try store.update { stored in
            stored = session
            return "done"
        }

        #expect(result == "done")
        #expect(store.current() == session)
    }

    @Test("An update whose change throws stores nothing, even if it changed the session first")
    func failedUpdateStoresNothing() throws {
        let original = PracticeSession(startedAt: clock.now)
        let store = InMemoryRunningSessionStore(original)
        clock.advance(by: 60)

        #expect(throws: SessionError.alreadyPaused) {
            try store.update { stored in
                try stored?.pause(at: clock.now)
                try stored?.pause(at: clock.now)
            }
        }
        #expect(store.current() == original)
    }
}
