#if DEBUG
    import Foundation
    import PianismCore
    import Synchronization

    extension PracticeModel {
        enum PreviewState {
            case ready, running, paused
        }

        /// A model over an in-memory store, 25 minutes into a session, for previews.
        static func preview(_ state: PreviewState) -> PracticeModel {
            let store = PreviewStore()
            let startedAt = Date(timeIntervalSince1970: 1_798_761_600)
            let now = PreviewClock(now: startedAt.addingTimeInterval(25 * 60 + 3))
            if state != .ready {
                _ = try? SessionRecorder(store: store, clock: PreviewClock(now: startedAt)).start()
            }
            let model = PracticeModel(
                recorder: SessionRecorder(store: store, clock: now), history: PreviewHistory(), clock: now)
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
        private let stored = Mutex<PracticeSession?>(nil)

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
#endif
