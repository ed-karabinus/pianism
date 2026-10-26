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
    /// The session that just ended and was kept, shown until the next one starts.
    private(set) var lastSession: PracticeSession?
    /// How many finished sessions are waiting to move into history, which couldn't save them yet.
    private(set) var waitingCount = 0
    /// Whether to show that a change couldn't be stored.
    var isShowingStorageError = false
    /// Whether the running session has practiced past the nudge, so Practice asks "Still practicing?" (SES-3).
    private(set) var isPastNudge = false  // mutate:ignore - init's refresh() sets it
    /// The session whose "Still practicing?" was answered, in the app or its notification, so it's asked once per
    /// session (SES-3). Stored per device.
    private(set) var answeredID: UUID?
    /// Whether Practice offers the notification, which is until it's been asked for, as the system asks once.
    private(set) var canAskForNudges = false
    /// What the notification opened Practice to show, until it's shown: the question, or the end being picked.
    var nudgeOpened: NudgeOpening?
    /// The session that ended itself at the cap, until the banner explaining it is acted on (SES-4).
    private var cappedID: UUID?
    /// Whether the last MIDI session had under a minute of played time, so it wasn't saved, until the next start
    /// (MIDI-1).
    private(set) var lastRunWasTooShort = false
    /// Turns the piano's notes into MIDI sessions, following the stored session at each refresh (MIDI-1).
    @ObservationIgnored private var detector = MIDIDetector()

    let clock: any WallClock
    /// The practice time after which Practice asks "Still practicing?" (SES-3).
    let nudge: TimeInterval
    /// The practice time that ends a running session by itself, in case it was left running (SES-4).
    let cap: TimeInterval
    private let recorder: SessionRecorder
    private let history: any SessionHistory
    private let outbox: any SessionOutbox
    private let nudges: any PracticeNudges
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "practice")
    /// The key under which the banner's `@AppStorage` kept the answer, so answers given before stay given.
    private static let answeredKey = "stillPracticingAnswered"

    public init(
        store: any RunningSessionStore, history: any SessionHistory, outbox: any SessionOutbox, clock: any WallClock,
        nudges: any PracticeNudges, defaults: UserDefaults, nudge: TimeInterval, cap: TimeInterval
    ) {
        self.recorder = SessionRecorder(store: store, clock: clock)
        self.history = history
        self.outbox = outbox
        self.clock = clock
        self.nudges = nudges
        self.defaults = defaults
        self.nudge = nudge
        self.cap = cap
        answeredID = defaults.string(forKey: Self.answeredKey).flatMap(UUID.init(uuidString:))
        // Loads the stored session now, so the first frame after a relaunch already shows it.
        refresh()
    }

    func start() {
        perform {
            try recorder.start()
            lastSession = nil
            lastRunWasTooShort = false
        }
    }

    /// Counts a note played on a connected piano (MIDI-1). Three within 10 s start a MIDI session. On a session
    /// started by tapping, notes only show the user is there, so past the nudge they answer "Still practicing?" as
    /// a Pause does (MIDI-R4, SES-3).
    public func noteOn(at date: Date) {
        guard session?.source != .timer else {
            answerIfPastNudge()
            return
        }
        apply(detector.handle(.noteOn(date)))
    }

    func pause() {
        answerIfPastNudge()
        perform { try recorder.pause() }
    }

    func resume() {
        answerIfPastNudge()
        perform { try recorder.resume() }
    }

    /// Whether Practice asks "Still practicing?" (SES-3).
    var isAskingStillPracticing: Bool { isPastNudge && session.map { $0.id != answeredID } == true }

    /// Answers "Still practicing?" for the session with this ID, from the banner or the notification (SES-3).
    public func answerStillPracticing(for id: UUID) {
        answeredID = id
        defaults.set(id.uuidString, forKey: Self.answeredKey)
    }

    /// A Pause or Resume once practice has passed the nudge shows the user is there, so it answers "Still
    /// practicing?" for the session (SES-3).
    private func answerIfPastNudge() {
        if let session, answeredID != session.id, session.elapsed(at: clock.now) >= nudge {
            answerStillPracticing(for: session.id)
        }
    }

    /// Shows Practice with the question about the session with this ID or, after the notification's "I stopped
    /// earlier", with its end being picked (SES-3).
    public func open(fromNudgeAbout id: UUID, pickingEnd: Bool) {
        nudgeOpened = NudgeOpening(sessionID: id, pickingEnd: pickingEnd)
    }

    func checkNudges() async {
        canAskForNudges = await nudges.canAskPermission()
    }

    /// Asks for the notification, which nudges about the sessions after this one (SES-3).
    func askForNudges() async {
        canAskForNudges = false
        await nudges.requestPermission()
    }

    /// Ends the session now, or a MIDI session at the earlier of now and 5 s after its last note (MIDI-R4).
    func stop() {
        if session?.source == .midi {
            apply(detector.handle(.stop(clock.now)))
        } else {
            perform { try recorder.stop() }
        }
    }

    /// Stores the detector's effects in one command, so a note refreshes once, and only if it changed something.
    /// A MIDI session ended with under a minute played is dropped in the refresh, which Practice then says.
    private func apply(_ effects: [MIDIDetector.Effect]) {
        guard !effects.isEmpty else { return }  // mutate:ignore - without it, a note only refreshes needlessly
        var endedID: UUID?
        perform {
            for effect in effects {
                switch effect {
                case .start(let date):
                    try recorder.start(at: date)
                    lastRunWasTooShort = false
                case .end(let lastNote, let date):
                    // A Stop dated before the last note, as after the clock steps back, ends the session at it.
                    endedID = try recorder.end(afterLastNote: lastNote, at: max(date, lastNote)).id
                }
            }
        }
        // Neither kept nor still stored, as one is when history and the outbox both fail, so it was dropped.
        if let endedID {
            lastRunWasTooShort = lastSession?.id != endedID && session?.id != endedID
        }
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
        detector.sync(with: session)
        isPastNudge = session?.whenPracticeReaches(nudge).map { $0 <= clock.now } ?? false
        // The notification waits for the running session to reach the nudge. A pause, a stop or a session already
        // past it cancels it, so it comes at most once per session.
        if let session, let date = session.whenPracticeReaches(nudge), date > clock.now {
            nudges.schedule(after: date.timeIntervalSince(clock.now), sessionID: session.id)
        } else {
            nudges.cancel()
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

/// What the notification opened Practice to show (SES-3).
struct NudgeOpening: Equatable {
    let sessionID: UUID
    let pickingEnd: Bool
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
