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
