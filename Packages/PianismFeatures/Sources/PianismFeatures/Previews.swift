import Foundation
import PianismCore
import Synchronization

// Not limited to Debug builds: `#Preview` bodies compile in Release too. Unused, this is stripped.

/// 2027-01-01 00:00 UTC, the moment every preview is set at.
private let previewNow = Date(timeIntervalSince1970: 1_798_761_600)

extension PracticeModel {
    enum PreviewState {
        case ready, running, paused
    }

    /// A model over an in-memory store, 25 minutes into a session, for previews.
    static func preview(_ state: PreviewState) -> PracticeModel {
        let store = PreviewStore(state == .ready ? nil : PracticeSession(startedAt: previewNow))
        let clock = PreviewClock(now: previewNow.addingTimeInterval(25 * 60 + 3))
        let model = PracticeModel(store: store, history: InMemorySessionHistory(), clock: clock)
        if state == .paused {
            model.pause()
        }
        return model
    }
}

extension HistoryModel {
    /// A model with practice today, yesterday and last week, or with none, for previews.
    static func preview(empty: Bool = false) -> HistoryModel {
        let history = InMemorySessionHistory()
        let hour: TimeInterval = 60 * 60
        let sessions = empty ? [] : [(-2, 25), (-6, 40), (-26, 15), (-170, 55)]
        for (hoursAgo, minutes) in sessions {
            let start = previewNow.addingTimeInterval(Double(hoursAgo) * hour)
            var session = PracticeSession(startedAt: start)
            try? session.stop(at: start.addingTimeInterval(Double(minutes) * 60))
            history.save(session)
        }
        let model = HistoryModel(history: history, clock: PreviewClock(now: previewNow))
        model.refresh()
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
