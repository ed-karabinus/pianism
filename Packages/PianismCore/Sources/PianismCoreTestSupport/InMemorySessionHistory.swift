import PianismCore
import Synchronization

/// A ``SessionHistory`` that keeps finished sessions in memory, in the order first saved.
public final class InMemorySessionHistory: SessionHistory {
    private let saved = Mutex<[PracticeSession]>([])

    public init() {}

    /// Every saved session.
    public var sessions: [PracticeSession] {
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
