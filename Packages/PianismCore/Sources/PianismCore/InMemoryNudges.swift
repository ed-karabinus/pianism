import Foundation
import Synchronization

/// ``PracticeNudges`` that only remember the nudge waiting, for previews and tests.
public final class InMemoryNudges: PracticeNudges {
    private let state = Mutex<(pending: (delay: TimeInterval, sessionID: UUID)?, canAsk: Bool)>((nil, true))

    /// Nudges that can ask for permission once.
    public init() {}

    /// The nudge waiting, if there is one: its delay and session.
    // periphery:ignore - read by PianismFeatures' tests, which Periphery doesn't index
    public var pending: (delay: TimeInterval, sessionID: UUID)? { state.withLock { $0.pending } }

    public func canAskPermission() -> Bool {
        state.withLock { $0.canAsk }
    }

    public func requestPermission() {
        state.withLock { $0.canAsk = false }
    }

    public func schedule(after delay: TimeInterval, sessionID: UUID) {
        state.withLock { $0.pending = (delay, sessionID) }
    }

    public func cancel() {
        state.withLock { $0.pending = nil }
    }
}
