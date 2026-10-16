import Synchronization

/// A ``SessionHistory`` kept in memory: the app's history until the synced store lands (HIS-1,
/// ADR 0004), and the one previews and tests use.
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
