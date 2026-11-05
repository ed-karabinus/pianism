import Foundation
import PianismCore
import Synchronization

/// ``PracticeNudges`` that only remember the nudge waiting, for tests.
public final class InMemoryNudges: PracticeNudges {
    private let state = Mutex<(pending: (delay: TimeInterval, sessionID: UUID)?, permission: NotificationPermission)>(
        (nil, .notAsked))
    private let answer: NotificationPermission

    /// Nudges that can ask for permission once, when `answer` is what they're told.
    public init(answer: NotificationPermission = .allowed) {
        self.answer = answer
    }

    /// Changes what's allowed, as the system's Settings app does.
    public func setPermission(_ permission: NotificationPermission) {
        state.withLock { $0.permission = permission }
    }

    /// The nudge waiting, if there is one: its delay and session.
    public var pending: (delay: TimeInterval, sessionID: UUID)? { state.withLock { $0.pending } }

    public func permission() -> NotificationPermission {
        state.withLock { $0.permission }
    }

    public func requestPermission() {
        state.withLock { if $0.permission == .notAsked { $0.permission = answer } }
    }

    public func schedule(after delay: TimeInterval, sessionID: UUID) {
        state.withLock { $0.pending = (delay, sessionID) }
    }

    public func cancel() {
        state.withLock { $0.pending = nil }
    }
}
