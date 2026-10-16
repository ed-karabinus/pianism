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
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else {
                sessions.append(session)
            }
        }
    }
}

/// Also an outbox, for previews and tests: adding is saving.
extension InMemorySessionHistory: SessionOutbox {
    public func add(_ session: PracticeSession) {
        save(session)
    }

    public func remove(id: UUID) {
        saved.withLock { $0.removeAll { $0.id == id } }
    }
}
