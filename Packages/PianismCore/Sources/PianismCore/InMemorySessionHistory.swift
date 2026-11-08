import Foundation
import Synchronization

/// A ``SessionHistory`` kept in memory, for previews and tests.
public final class InMemorySessionHistory: SessionHistory {
    private let saved = Mutex<[PracticeSession]>([])
    private let deletedIDs = Mutex<Set<UUID>>([])
    private let readOnlyIDs = Mutex<Set<UUID>>([])
    private let unshowable: Int

    /// An empty history, which says it holds `unshowable` sessions it can't show.
    public init(unshowable: Int = 0) {
        self.unshowable = unshowable
    }

    public func sessions() -> [PracticeSession] {
        saved.withLock { $0 }
    }

    public func unshowableCount() -> Int {
        unshowable
    }

    public func save(_ session: PracticeSession) {
        saved.withLock { sessions in
            if !sessions.contains(where: { $0.id == session.id }), !deletedIDs.withLock({ $0.contains(session.id) }) {
                sessions.append(session)
            }
        }
    }

    /// From now on, `id` acts as if a newer version wrote it, as when its copy from such a device syncs in.
    public func markWrittenByNewerVersion(id: UUID) {
        readOnlyIDs.withLock { _ = $0.insert(id) }
    }

    public func canEdit(id: UUID) -> Bool {
        !readOnlyIDs.withLock { $0.contains(id) } && saved.withLock { $0.contains { $0.id == id } }
    }

    public func edit(_ session: PracticeSession) throws {
        guard !readOnlyIDs.withLock({ $0.contains(session.id) }) else { throw RecordFromNewerVersion() }
        guard !deletedIDs.withLock({ $0.contains(session.id) }) else { throw SessionDeleted() }
        saved.withLock { sessions in
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            }
        }
    }

    public func delete(id: UUID) throws {
        try saved.withLock { sessions in
            guard sessions.contains(where: { $0.id == id }) else { return }
            guard !readOnlyIDs.withLock({ $0.contains(id) }) else { throw RecordFromNewerVersion() }
            sessions.removeAll { $0.id == id }
            deletedIDs.withLock { _ = $0.insert(id) }
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
