import Foundation

/// Starts, pauses, resumes and stops the running session, storing each change before it returns
/// (SES-1, SES-2, SES-6).
///
/// Because every change is stored as it happens, restoring a session after the app was killed is
/// just reading ``current()``: its elapsed time comes from the stored timestamps.
public struct SessionRecorder: Sendable {
    private let store: any RunningSessionStore
    private let clock: any WallClock
    private let makeID: @Sendable () -> UUID

    public init(
        store: any RunningSessionStore,
        clock: any WallClock,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.store = store
        self.clock = clock
        self.makeID = makeID
    }

    /// The running, paused or just-ended session, or `nil` if there is none.
    public func current() throws -> PracticeSession? {
        try store.current()
    }

    /// Starts a new session now (SES-1).
    ///
    /// Throws ``RecorderError/alreadyStarted`` if a session is running or paused, and
    /// ``RecorderError/previousSessionNotSaved`` if an ended session hasn't moved to history yet,
    /// so starting never overwrites practice.
    @discardableResult
    public func start() throws -> PracticeSession {
        try store.update { stored in
            if let stored {
                throw stored.state == .ended ? RecorderError.previousSessionNotSaved : .alreadyStarted
            }
            let session = PracticeSession(id: makeID(), startedAt: clock.now)
            stored = session
            return session
        }
    }

    /// Pauses the running session now (SES-2).
    @discardableResult
    public func pause() throws -> PracticeSession {
        try change { session, now in try session.pause(at: now) }
    }

    /// Resumes the paused session now (SES-2).
    @discardableResult
    public func resume() throws -> PracticeSession {
        try change { session, now in try session.resume(at: now) }
    }

    /// Ends the session now (SES-1). It stays in the store, ended, until it moves to history.
    @discardableResult
    public func stop() throws -> PracticeSession {
        try change { session, now in try session.stop(at: now) }
    }

    /// Applies `apply` to the stored session at the current time.
    ///
    /// The time is read inside the update, after any change from another process has been
    /// stored, so it is never earlier than that change.
    private func change(
        _ apply: (inout PracticeSession, Date) throws -> Void
    ) throws -> PracticeSession {
        try store.update { stored in
            guard var session = stored else { throw RecorderError.noSession }
            try apply(&session, clock.now)
            stored = session
            return session
        }
    }
}

/// Why a ``SessionRecorder`` command was rejected. Changes the session itself rejects throw
/// ``SessionError``.
public enum RecorderError: Error, Sendable, Hashable {
    /// `start` while a session is running or paused.
    case alreadyStarted
    /// `start` while an ended session is still waiting to move to history.
    case previousSessionNotSaved
    /// `pause`, `resume` or `stop` with no session.
    case noSession
}
