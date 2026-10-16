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
public final class PracticeModel {
    /// The running or paused session, or `nil` when ready to start.
    private(set) var session: PracticeSession?
    /// The session that just ended, shown until the next one starts.
    private(set) var lastSession: PracticeSession?
    /// Whether to show that a change couldn't be stored.
    var isShowingStorageError = false

    let clock: any WallClock
    private let recorder: SessionRecorder
    private let history: any SessionHistory
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "practice")

    public init(store: any RunningSessionStore, history: any SessionHistory, clock: any WallClock) {
        self.recorder = SessionRecorder(store: store, clock: clock)
        self.history = history
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

    /// Shows the stored session, after moving an ended one into history.
    ///
    /// Call when the app becomes active: the session may have changed in another process, such as
    /// a Live Activity, or have been restored after the app was killed.
    func refresh() {
        do {
            if let archived = try recorder.archive(to: history) {
                lastSession = archived
            }
        } catch {
            // The ended session stays stored and moves on a later refresh. Until then, Start is refused.
            logger.error("Couldn't move the session into history: \(error, privacy: .public)")
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
