import Foundation
import Synchronization

/// ``PracticeNudges`` that only remember the nudge waiting, for previews and tests.
public final class InMemoryNudges: PracticeNudges {
    /// The nudge waiting: its delay and session.
    public struct Pending: Sendable {
        public let delay: TimeInterval
        public let sessionID: UUID
    }

    private let state: Mutex<(pending: Pending?, canAsk: Bool)>

    /// Nudges that can ask for permission once.
    public init() {
        state = Mutex((nil, true))
    }

    /// The nudge waiting, if there is one.
    public var pending: Pending? { state.withLock { $0.pending } }

    public func canAskPermission() -> Bool {
        state.withLock { $0.canAsk }
    }

    public func requestPermission() {
        state.withLock { $0.canAsk = false }
    }

    public func schedule(after delay: TimeInterval, sessionID: UUID) {
        state.withLock { $0.pending = Pending(delay: delay, sessionID: sessionID) }
    }

    public func cancel() {
        state.withLock { $0.pending = nil }
    }
}
