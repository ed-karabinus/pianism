import Foundation
import PianismCore
import Synchronization

// Not limited to Debug builds: `#Preview` bodies compile in Release too. Unused, this is stripped.

/// 2027-01-01 00:00 UTC, the moment the Practice previews are set at.
private let previewNow = Date(timeIntervalSince1970: 1_798_761_600)

extension PracticeModel {
    enum PreviewState {
        case ready, running, paused
    }

    /// A model over an in-memory store, 25 minutes into a session, for previews.
    static func preview(_ state: PreviewState) -> PracticeModel {
        let store = PreviewStore(state == .ready ? nil : PracticeSession(startedAt: previewNow))
        let clock = PreviewClock(now: previewNow.addingTimeInterval(25 * 60 + 3))
        let model = PracticeModel(
            store: store, history: InMemorySessionHistory(), outbox: InMemorySessionHistory(), clock: clock)
        if state == .paused {
            model.pause()
        }
        return model
    }
}

extension HistoryModel {
    /// A model with practice today, yesterday and last week, or with none, for previews. Times are
    /// local, so "Today" holds in any time zone. `waiting` puts the sessions in the outbox and makes
    /// history fail to load, as during an outage (ADR 0007).
    static func preview(empty: Bool = false, waiting: Bool = false) -> HistoryModel {
        let sessions = InMemorySessionHistory()
        let midnight = Calendar.autoupdatingCurrent.startOfDay(for: previewNow)
        let hour: TimeInterval = 60 * 60
        // (Hours after this midnight, minutes of practice.)
        let practice = empty ? [] : [(18, 25), (8, 40), (-5, 15), (-150, 55)]
        for (hours, minutes) in practice {
            let start = midnight.addingTimeInterval(Double(hours) * hour)
            var session = PracticeSession(startedAt: start)
            try? session.stop(at: start.addingTimeInterval(Double(minutes) * 60))
            sessions.save(session)
        }
        let history: any SessionHistory = waiting ? PreviewUnavailableHistory() : sessions
        let outbox = waiting ? sessions : InMemorySessionHistory()
        return HistoryModel(
            history: history, outbox: outbox, clock: PreviewClock(now: midnight.addingTimeInterval(20 * hour)))
    }
}

private struct PreviewUnavailableHistory: SessionHistory {
    struct Unavailable: Error {}

    func sessions() throws -> [PracticeSession] { throw Unavailable() }
    func save(_: PracticeSession) throws { throw Unavailable() }
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
