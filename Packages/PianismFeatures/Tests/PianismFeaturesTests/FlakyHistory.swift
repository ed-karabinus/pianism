import PianismCore
import Synchronization

/// A history that can't be reached until it heals, as when its store fails to open and later opens.
final class FlakyHistory: SessionHistory {
    struct Failure: Error {}

    let saved = InMemorySessionHistory()
    private let isFailing = Mutex(true)

    func heal() {
        isFailing.withLock { $0 = false }
    }

    func sessions() throws -> [PracticeSession] {
        try failIfUnreachable()
        return saved.sessions()
    }

    func save(_ session: PracticeSession) throws {
        try failIfUnreachable()
        saved.save(session)
    }

    private func failIfUnreachable() throws {
        if isFailing.withLock({ $0 }) { throw Failure() }
    }
}
