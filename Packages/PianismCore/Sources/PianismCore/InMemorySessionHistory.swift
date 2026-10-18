import Foundation
import Synchronization

/// A ``SessionHistory`` kept in memory, for previews and tests.
public final class InMemorySessionHistory: SessionHistory {
    private let saved = Mutex<[PracticeSession]>([])
    private let readOnlyIDs: Set<UUID>

    /// An empty history, in which sessions saved with `readOnlyIDs` act as if a newer version wrote them.
    public init(readOnlyIDs: Set<UUID> = []) {
        self.readOnlyIDs = readOnlyIDs
    }

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

    public func canEdit(id: UUID) -> Bool {
        !readOnlyIDs.contains(id) && saved.withLock { $0.contains { $0.id == id } }
    }

    public func edit(_ session: PracticeSession) throws {
        guard !readOnlyIDs.contains(session.id) else { throw RecordFromNewerVersion() }
        saved.withLock { sessions in
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
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
