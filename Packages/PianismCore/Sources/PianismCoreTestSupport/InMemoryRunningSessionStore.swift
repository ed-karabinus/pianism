import PianismCore
import Synchronization

/// A ``RunningSessionStore`` that keeps the session in memory.
///
/// Use it to test anything that takes a store. Share one instance between two objects to
/// simulate two processes, or between an object and its replacement to simulate a relaunch.
public final class InMemoryRunningSessionStore: RunningSessionStore {
    private let stored: Mutex<PracticeSession?>

    public init(_ session: PracticeSession? = nil) {
        stored = Mutex(session)
    }

    public func current() -> PracticeSession? {
        stored.withLock { $0 }
    }

    public func update<Result: Sendable>(_ change: (inout PracticeSession?) throws -> Result) throws -> Result {
        try stored.withLock { stored in
            var session = stored
            let result = try change(&session)
            stored = session
            return result
        }
    }
}
