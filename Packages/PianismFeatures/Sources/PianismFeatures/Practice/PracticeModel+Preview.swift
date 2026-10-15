import Foundation
import PianismCore
import Synchronization

// Not limited to Debug builds: `#Preview` bodies compile in Release too. Unused, this is stripped.
extension PracticeModel {
    enum PreviewState {
        case ready, running, paused
    }

    /// A model over an in-memory store, 25 minutes into a session, for previews.
    static func preview(_ state: PreviewState) -> PracticeModel {
        let startedAt = Date(timeIntervalSince1970: 1_798_761_600)
        let store = PreviewStore(state == .ready ? nil : PracticeSession(startedAt: startedAt))
        let clock = PreviewClock(now: startedAt.addingTimeInterval(25 * 60 + 3))
        let model = PracticeModel(store: store, history: PreviewHistory(), clock: clock)
        model.refresh()
        if state == .paused {
            model.pause()
        }
        return model
    }
}

private struct PreviewClock: WallClock {
    let now: Date
}

private final class PreviewStore: RunningSessionStore {
    private let stored: Mutex<PracticeSession?>

    init(_ session: PracticeSession?) {
        stored = Mutex(session)
    }

    func current() -> PracticeSession? {
        stored.withLock { $0 }
    }

    func update<Value: Sendable>(_ change: (inout PracticeSession?) throws -> Value) throws -> Value {
        try stored.withLock { stored in
            var session = stored
            let value = try change(&session)
            stored = session
            return value
        }
    }
}

private struct PreviewHistory: SessionHistory {
    func save(_ session: PracticeSession) {}
}
