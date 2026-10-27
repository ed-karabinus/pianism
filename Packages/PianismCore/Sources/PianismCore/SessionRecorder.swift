import Foundation

/// Starts, pauses, resumes and stops the running session, storing each change before it returns
/// (SES-1, SES-2, SES-6).
///
/// Because every change is stored as it happens, restoring a session after the app was killed is
/// just reading ``current()``: its elapsed time comes from the stored timestamps.
public struct SessionRecorder: Sendable {
    private let store: any RunningSessionStore
    private let clock: any WallClock
    private let midi: MIDISettings
    private let makeID: @Sendable () -> UUID
    private let timeZone: @Sendable () -> TimeZone

    public init(
        store: any RunningSessionStore,
        clock: any WallClock,
        midi: MIDISettings = .init(),
        makeID: @escaping @Sendable () -> UUID = UUID.init,
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.store = store
        self.clock = clock
        self.midi = midi
        self.makeID = makeID
        self.timeZone = timeZone
    }

    /// The running, paused or just-ended session, or `nil` if there is none.
    public func current() throws -> PracticeSession? {
        try store.current()
    }

    /// Starts a new session now, in the current time zone (SES-1, ADR 0006).
    ///
    /// Throws ``RecorderError/alreadyStarted`` if a session is running or paused, and
    /// ``RecorderError/previousSessionNotSaved`` if an ended session is still stored because neither
    /// history nor the outbox could take it, so starting never overwrites practice.
    @discardableResult
    public func start() throws -> PracticeSession {
        try start(.timer, at: nil)
    }

    /// Starts a MIDI session at `date`, the first of the notes that started it, in the current time zone (MIDI-1).
    /// Refuses as ``start()`` does.
    @discardableResult
    public func start(at date: Date) throws -> PracticeSession {
        try start(.midi, at: date)
    }

    /// Starts a session at `date`, or now if it's `nil`.
    private func start(_ source: PracticeSession.Source, at date: Date?) throws -> PracticeSession {
        try store.update { stored in
            if let stored {
                throw stored.state == .ended ? RecorderError.previousSessionNotSaved : .alreadyStarted
            }
            let session = PracticeSession(
                id: makeID(), startedAt: date ?? clock.now, timeZone: timeZone(), source: source)
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

    /// Pauses the running session at `date`, a MIDI session's last note before a silence (MIDI-1).
    @discardableResult
    public func pause(at date: Date) throws -> PracticeSession {
        try change { session, _ in try session.pause(at: date) }
    }

    /// Resumes the paused session at `date`, the note that ended a MIDI session's silence (MIDI-1).
    @discardableResult
    public func resume(at date: Date) throws -> PracticeSession {
        try change { session, _ in try session.resume(at: date) }
    }

    /// Stores when the running MIDI session's last note was played (MIDI-1).
    @discardableResult
    public func noteLastPlayed(at date: Date) throws -> PracticeSession {
        try change { session, _ in try session.noteLastPlayed(at: date) }
    }

    /// Ends the session now (SES-1). It stays in the store, ended, until ``archive(to:or:)`` moves it to history
    /// or drops it.
    @discardableResult
    public func stop() throws -> PracticeSession {
        try change { session, now in try session.stop(at: now) }
    }

    /// Ends the session at `date`, earlier than now, when the user says it ended before they tapped (SES-3).
    /// Throws ``SessionError/timeWentBackwards`` if `date` is before the session's last change.
    @discardableResult
    public func stop(at date: Date) throws -> PracticeSession {
        try change { session, _ in try session.stop(at: date) }
    }

    /// Ends a MIDI session at `date` (MIDI-1). If it's running, it first pauses at `lastNote`, so the time after the
    /// last note is a closing pause, not played time (ADR 0009). One update, so a kill can't leave it paused but
    /// not ended.
    @discardableResult
    public func end(afterLastNote lastNote: Date, at date: Date) throws -> PracticeSession {
        try change { session, _ in
            if session.state == .running { try session.pause(at: lastNote) }
            try session.stop(at: date)
        }
    }

    /// Ends the running session at the moment its practice time reached `cap`, if it has by now, in case it
    /// was left running (SES-4). A paused session is left alone, and so is a MIDI session, which a silence ends.
    /// Returns the ended session, or `nil`.
    public func end(atCap cap: TimeInterval) throws -> PracticeSession? {
        // Read first, as `archive` does, so the usual case writes nothing.
        guard let read = try store.current(), read.source != .midi, let end = read.whenPracticeReaches(cap),
            end <= clock.now
        else {
            return nil
        }
        return try store.update { stored in
            // Another process may have paused or stopped it since; the next call sees that change.
            guard var session = stored, session == read else { return nil }
            try session.stop(at: end)
            stored = session
            return session
        }
    }

    /// Replaces the running or paused session's tags (TAG-2).
    @discardableResult
    public func setTags(_ ids: [Tag.ID]) throws -> PracticeSession {
        try change { session, _ in try session.setTags(ids) }
    }

    /// Moves an ended session out of the store, so a new one can start: into `history`, or into
    /// `outbox` if history can't save it (ADR 0007), unless it isn't practice, which drops it: a mis-tap under
    /// 10 s, quietly (SES-1), or a few stray notes under a MIDI session's minimum played time (MIDI-1). Then moves any waiting sessions into history. Returns the
    /// ended session it kept, or `nil` if none had ended or it was dropped.
    ///
    /// Throws only if the ended session could go nowhere; it then stays in the store. Safe to repeat
    /// after a crash at any step: history saves each ID once, the outbox replaces by ID, and the
    /// store is cleared only while it still holds that session.
    @discardableResult
    public func archive(to history: any SessionHistory, or outbox: any SessionOutbox) throws -> PracticeSession? {
        let ended = try store.current().flatMap { $0.state == .ended ? $0 : nil }
        let kept = ended.flatMap {
            $0.elapsed(at: clock.now) >= ($0.source == .midi ? midi.minimumPlayed : 10) ? $0 : nil
        }
        if let kept {
            do {
                try history.save(kept)
            } catch {
                try outbox.add(kept)
            }
        }
        if let ended {
            try store.update { stored in
                if stored?.id == ended.id { stored = nil }
            }
        }
        // History may still be failing; whatever it doesn't take waits for the next archive.
        _ = try? moveWaiting(from: outbox, to: history)
        return kept
    }

    /// Stops at the first failure, as when the store can't open, so an outage costs one failed save
    /// per archive, not one per waiting session. A refused session is skipped, so it can't hold back
    /// the rest.
    private func moveWaiting(from outbox: any SessionOutbox, to history: any SessionHistory) throws {
        for waiting in try outbox.sessions() {
            do {
                try history.save(waiting)
                try outbox.remove(id: waiting.id)
            } catch is SessionRefused {}
        }
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
    /// `start` while an ended session is still stored, because neither history nor the outbox could
    /// take it.
    case previousSessionNotSaved
    /// `pause`, `resume` or `stop` with no session.
    case noSession
}
