import Foundation
import Observation
import PianismCore
import os

/// State and commands for the Practice screen (SES-1, SES-2, SES-6).
///
/// Every command goes through the ``SessionRecorder``, which stores it before returning, so the
/// screen always shows what is stored, even if the app was killed or another process changed it.
@MainActor
@Observable
public final class PracticeModel {
    /// The running or paused session, or `nil` when ready to start.
    public private(set) var session: PracticeSession?
    /// The session that just ended, shown until the next one starts.
    public private(set) var lastSession: PracticeSession?
    /// Whether to show that a change couldn't be stored.
    public var isShowingStorageError = false

    @ObservationIgnored public let clock: any WallClock
    @ObservationIgnored private let recorder: SessionRecorder
    @ObservationIgnored private let history: any SessionHistory
    @ObservationIgnored private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "practice")

    public init(recorder: SessionRecorder, history: any SessionHistory, clock: any WallClock) {
        self.recorder = recorder
        self.history = history
        self.clock = clock
    }

    /// Practice time of the current session at `now`, or zero when there is none.
    public func elapsed(at now: Date) -> TimeInterval {
        session?.elapsed(at: now) ?? 0
    }

    /// Shows the stored session, after moving an ended one into history.
    ///
    /// Call when the app becomes active: the session may have changed in another process, such as
    /// a Live Activity, or have been restored after the app was killed.
    public func refresh() {
        perform {}
    }

    public func start() {
        perform {
            try recorder.start()
            lastSession = nil
        }
    }

    public func pause() {
        perform { try recorder.pause() }
    }

    public func resume() {
        perform { try recorder.resume() }
    }

    public func stop() {
        perform { try recorder.stop() }
    }

    /// Runs `command`, then shows what is stored, moving a session it ended into history.
    ///
    /// A command the session rejects means another process changed it first. The reload shows
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
        reload()
    }

    private func reload() {
        do {
            if let archived = try recorder.archive(to: history) {
                lastSession = archived
            }
            session = try recorder.current()
        } catch {
            logger.error("Couldn't load the running session: \(error, privacy: .public)")
            isShowingStorageError = true
        }
    }
}
