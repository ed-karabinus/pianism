import Foundation
import PianismCore
import Synchronization

/// ``PracticeNudges`` that only remember the nudge waiting, for tests.
public final class InMemoryNudges: PracticeNudges {
    private let state = Mutex<
        (
            pending: (delay: TimeInterval, sessionID: UUID)?, permission: NotificationPermission,
            reminders: [DateComponents]
        )
    >((nil, .notAsked, []))
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

    /// The reminders waiting.
    public var waitingReminders: [DateComponents] { state.withLock { $0.reminders } }

    public func permission() -> NotificationPermission {
        state.withLock { $0.permission }
    }

    public func requestPermission() {
        state.withLock { if $0.permission == .notAsked { $0.permission = answer } }
    }

    public func schedule(after delay: TimeInterval, sessionID: UUID) {
        // As the system does, which refuses a notification until it's allowed.
        state.withLock { if $0.permission == .allowed { $0.pending = (delay, sessionID) } }
    }

    public func cancel() {
        state.withLock { $0.pending = nil }
    }

    public func scheduleReminders(at dates: [DateComponents]) {
        // As the system does, as for a nudge.
        state.withLock { if $0.permission == .allowed { $0.reminders = dates } }
    }

    public func cancelReminders() {
        state.withLock { $0.reminders = [] }
    }
}
