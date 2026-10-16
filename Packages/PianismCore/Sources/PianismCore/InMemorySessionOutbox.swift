import Foundation
import Synchronization

/// A ``SessionOutbox`` kept in memory, for previews and tests.
public final class InMemorySessionOutbox: SessionOutbox {
    private let waiting = Mutex<[UUID: PracticeSession]>([:])

    public init() {}

    public func sessions() -> [PracticeSession] {
        waiting.withLock { Array($0.values) }
    }

    public func add(_ session: PracticeSession) {
        waiting.withLock { $0[session.id] = session }
    }

    public func remove(id: UUID) {
        waiting.withLock { $0[id] = nil }
    }
}
