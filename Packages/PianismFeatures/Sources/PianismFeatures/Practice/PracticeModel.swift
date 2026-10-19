import Foundation
import Observation
import PianismCore
import os

/// State and commands for the Practice screen (SES-1 to SES-4, SES-6).
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
    /// Whether the running session has practiced past the nudge, so Practice asks "Still practicing?" (SES-3).
    private(set) var isPastNudge = false  // mutate:ignore - init's refresh() sets it
    /// The session that ended itself at the cap, until the banner explaining it is acted on (SES-4).
    private var cappedID: UUID?

    let clock: any WallClock
    /// The practice time after which Practice asks "Still practicing?" (SES-3).
    let nudge: TimeInterval
    /// The practice time that ends a running session by itself, in case it was left running (SES-4).
    let cap: TimeInterval
    private let recorder: SessionRecorder
    private let history: any SessionHistory
    private let outbox: any SessionOutbox
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "practice")

    public init(
        store: any RunningSessionStore, history: any SessionHistory, outbox: any SessionOutbox, clock: any WallClock,
        nudge: TimeInterval, cap: TimeInterval
    ) {
        self.recorder = SessionRecorder(store: store, clock: clock)
        self.history = history
        self.outbox = outbox
        self.clock = clock
        self.nudge = nudge
        self.cap = cap
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

    /// Ends the session at `date`, when it ended before now (SES-3). A date before the last resume, as when the
    /// clock steps back, ends it at the resume.
    func stop(at date: Date) {
        let end = session.map { max(date, $0.latestEvent).keepingSeconds(of: $0.startedAt, within: stopRange(of: $0)) }
        perform { try recorder.stop(at: end ?? date) }
    }

    /// The times "I stopped earlier" offers, from the last resume to now (SES-3). The upper bound never falls
    /// below the lower, as a ClosedRange traps then, should the clock step back.
    func stopRange(of session: PracticeSession) -> ClosedRange<Date> {
        session.latestEvent...max(session.latestEvent, clock.now)
    }

    /// When the running session reaches the nudge or the cap next, so Practice refreshes then (SES-3, SES-4).
    var nextRefresh: Date? {
        let now = clock.now
        return [nudge, cap].compactMap { session?.whenPracticeReaches($0) }.filter { $0 > now }.min()
    }

    /// Whether the last session ended itself at the cap, which a banner explains until the next start (SES-4).
    var lastSessionReachedCap: Bool { lastSession.map { $0.id == cappedID } == true }

    /// Hides the cap banner, as its Edit was tapped.
    func dismissCapBanner() {
        cappedID = nil
    }

    var tagIDs: [Tag.ID] { session?.tagIDs ?? [] }

    /// Replaces the running session's tags (TAG-2).
    func setTags(_ ids: [Tag.ID]) {
        perform { try recorder.setTags(ids) }
    }

    /// Shows the stored session, after ending one that reached the cap and moving an ended one into
    /// history, or into the outbox if history can't save it (ADR 0007).
    ///
    /// Call when the app becomes active: the session may have changed in another process, such as
    /// a Live Activity, or have been restored after the app was killed.
    func refresh() {
        do {
            if let capped = try recorder.end(atCap: cap) {
                cappedID = capped.id
            }
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
        isPastNudge = session?.whenPracticeReaches(nudge).map { $0 <= clock.now } ?? false
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

extension Date {
    /// This date's minute, at the seconds of `reference`, the session's other end (SES-3, SES-5). Time wheels
    /// show only minutes, so a picked time would otherwise keep hidden seconds, and a session picked as 2:00 to
    /// 3:00 could last 59:43. It stays in `range`, as the wheels do; a date already outside is left as it is,
    /// for the caller to reject.
    func keepingSeconds(of reference: Date, within range: ClosedRange<Date>) -> Date {
        guard range.contains(self) else { return self }
        let calendar = Calendar.autoupdatingCurrent
        func minute(of date: Date) -> Date { calendar.dateInterval(of: .minute, for: date)?.start ?? date }
        let picked = minute(of: self) + reference.timeIntervalSince(minute(of: reference))
        return min(max(picked, range.lowerBound), range.upperBound)
    }
}
