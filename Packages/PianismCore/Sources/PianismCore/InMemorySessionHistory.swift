import Foundation
import Synchronization

/// A ``SessionHistory`` kept in memory, for previews and tests.
public final class InMemorySessionHistory: SessionHistory {
    private let saved = Mutex<[PracticeSession]>([])

    public init() {}

    public func sessions() -> [PracticeSession] {
        saved.withLock { $0 }
    }

    public func save(_ session: PracticeSession) {
        saved.withLock { sessions in
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.append(session)
            }
        }
    }
}

/// Also an outbox, for previews and tests: a waiting session is a saved one.
extension InMemorySessionHistory: SessionOutbox {
    public func add(_ session: PracticeSession) {
        remove(id: session.id)
        save(session)
    }

    public func remove(id: UUID) {
        saved.withLock { $0.removeAll { $0.id == id } }
    }
}
