import Foundation
import Observation
import PianismCore
import os

/// State and commands for the Practice screen (SES-1, SES-2, SES-6).
///
/// Every command goes through a ``SessionRecorder``, which stores it before returning, so the
/// screen always shows what is stored, even if the app was killed or another process changed it.
@MainActor
@Observable
public final class PracticeModel: TagTarget {
    /// The running or paused session, or `nil` when ready to start. Also an ended session that neither
    /// history nor the outbox could take, which shows as ready to start.
    private(set) var session: PracticeSession?
    /// The session that just ended, shown until the next one starts.
    private(set) var lastSession: PracticeSession?
    /// How many finished sessions are waiting to move into history, which couldn't save them yet.
    private(set) var waitingCount = 0
    /// Whether to show that a change couldn't be stored.
    var isShowingStorageError = false

    let clock: any WallClock
    private let recorder: SessionRecorder
    private let history: any SessionHistory
    private let outbox: any SessionOutbox
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "practice")

    public init(
        store: any RunningSessionStore, history: any SessionHistory, outbox: any SessionOutbox, clock: any WallClock
    ) {
        self.recorder = SessionRecorder(store: store, clock: clock)
        self.history = history
        self.outbox = outbox
        self.clock = clock
        // Loads the stored session now, so the first frame after a relaunch already shows it.
        refresh()
    }

    func start() {
        perform {
            try recorder.start()
            lastSession = nil
        }
    }

    func pause() {
        perform { try recorder.pause() }
    }

    func resume() {
        perform { try recorder.resume() }
    }

    func stop() {
        perform { try recorder.stop() }
    }

    /// The running session's tags.
    var tagIDs: [Tag.ID] { session?.tagIDs ?? [] }

    /// Replaces the running session's tags (TAG-2).
    func setTags(_ ids: [Tag.ID]) {
        perform { try recorder.setTags(ids) }
    }

    /// Shows the stored session, after moving an ended one into history, or into the outbox if
    /// history can't save it (ADR 0007).
    ///
    /// Call when the app becomes active: the session may have changed in another process, such as
    /// a Live Activity, or have been restored after the app was killed.
    func refresh() {
        do {
            if let archived = try recorder.archive(to: history, or: outbox) {
                lastSession = archived
            }
            waitingCount = try outbox.sessions().count
        } catch {
            // Neither history nor the outbox could take it, so it stays stored and Start is refused.
            logger.error("Couldn't move the session out of the running-session file: \(error, privacy: .public)")
            isShowingStorageError = true
        }
        do {
            session = try recorder.current()
        } catch {
            logger.error("Couldn't load the running session: \(error, privacy: .public)")
            isShowingStorageError = true
        }
    }

    /// Runs `command`, then shows what is stored, moving a session it ended into history.
    ///
    /// A command the session rejects means another process changed it first. The refresh shows
    /// that change, so it isn't an error for the user.
    private func perform(_ command: () throws -> Void) {
        do {
            try command()
        } catch is RecorderError, is SessionError {
            logger.info("Command superseded by another change to the session")
        } catch {
            logger.error("Couldn't store a session change: \(error, privacy: .public)")
            isShowingStorageError = true
        }
        refresh()
    }
}
