import Foundation
import Observation
import PianismCore
import os

/// State for the History screen (HIS-1): finished sessions, grouped by the day they started.
@MainActor
@Observable
public final class HistoryModel {
    /// Days with practice, newest first, including sessions still waiting to be saved.
    private(set) var days: [PracticeDay] = []
    /// The week shown atop History, with each day's practice (HIS-2): this week, or an earlier one picked.
    var week: PracticeWeek { PracticeWeek(containing: pickedWeek ?? now, days: days, in: calendar) }
    /// A day in the earlier week picked, or nil for this week, which then moves along with each refresh.
    private(set) var pickedWeek: Date?
    /// Whether an earlier week has practice in it or before it, back to the week of the first session.
    var canShowEarlierWeek: Bool { days.last.map { $0.start < week.days[0].start } ?? false }
    /// The sessions shown that history hasn't saved yet (ADR 0007).
    private(set) var waitingIDs: Set<UUID> = []
    /// The time of the last refresh, which decides what counts as today and yesterday.
    private(set) var now: Date
    /// Whether the last refresh couldn't read the history. Waiting sessions still show.
    private(set) var loadFailed = false
    /// How many saved sessions this version can't show, such as ones a newer version wrote (ADR 0006).
    private(set) var unshowableCount = 0
    /// The tags sessions show, each merged tag as the tag it was merged into (ADR 0004).
    private(set) var tagIndex = TagIndex([])
    /// Whether iCloud can't sync the history, so History says so (SYN-1). The app sets it.
    public var isNotSyncing = false
    /// The finished session being edited or added, if any (SES-5).
    var editing: SessionEdit?
    /// The session deleted but still undoable, hidden until ``commitDelete()`` writes it to storage (SES-5).
    private(set) var pendingDeletion: PracticeSession?
    /// Whether to show that a deletion couldn't be saved.
    var isShowingDeleteError = false
    /// How long Undo lasts. End-to-end tests lengthen it, as a slow simulator's steps can outlast 5 seconds.
    public var undoDuration: Duration = .seconds(5)

    let calendar = Calendar.autoupdatingCurrent
    private let clock: any WallClock
    private let history: any SessionHistory
    private let tags: any TagLibrary
    private let outbox: any SessionOutbox
    private let running: any RunningSessionStore
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    public init(
        history: any SessionHistory, tags: any TagLibrary, outbox: any SessionOutbox, running: any RunningSessionStore,
        clock: any WallClock
    ) {
        self.history = history
        self.tags = tags
        self.outbox = outbox
        self.running = running
        self.clock = clock
        self.now = clock.now
    }

    /// Loads the history again, and moves "today" along. Call when the screen appears and when the
    /// app returns to the foreground, and when iCloud brings changes (SYN-1): sessions finish elsewhere, and
    /// midnight may have passed.
    public func refresh() {
        now = clock.now
        dropPickedWeekIfCurrent()
        // An outbox that can't be read is reported by Practice, which raises its storage alert.
        let waiting = (try? outbox.sessions()) ?? []
        var saved: [PracticeSession] = []
        do {
            saved = try history.sessions()
            unshowableCount = try history.unshowableCount()
            tagIndex = TagIndex(try tags.allTags())
            loadFailed = false
        } catch {
            logger.error("Couldn't load the history: \(error, privacy: .public)")
            loadFailed = true
            unshowableCount = 0
        }
        // A session can be in both, when history saved it but it couldn't leave the outbox. It shows
        // once, as saved.
        let savedIDs = Set(saved.map(\.id))
        let unsaved = waiting.filter { !savedIDs.contains($0.id) }
        waitingIDs = Set(unsaved.map(\.id))
        days = PracticeDay.group((saved + unsaved).filter { $0.id != pendingDeletion?.id }, in: calendar)
        // A session open for editing keeps its own copy, but shows tags as they are now, such as one renamed on
        // another device (SYN-1).
        editing?.tags.refresh()
    }

    /// Shows the week before the one shown, or the one after, back to the week of the first session and on to this
    /// week (HIS-2).
    func showWeek(earlier: Bool) {
        guard earlier ? canShowEarlierWeek : pickedWeek != nil,
            let date = calendar.date(byAdding: .weekOfYear, value: earlier ? -1 : 1, to: week.days[0].start)
        else { return }
        pickedWeek = date
        dropPickedWeekIfCurrent()
    }

    /// Goes back to following this week once the picked one isn't earlier, such as after the clock was set back.
    private func dropPickedWeekIfCurrent() {
        if let pickedWeek, calendar.compare(pickedWeek, to: now, toGranularity: .weekOfYear) != .orderedAscending {
            self.pickedWeek = nil
        }
    }

    /// Whether `session` can be deleted: one still waiting can, and a saved one can when it can be edited.
    func canDelete(_ session: PracticeSession) -> Bool {
        // As in the editor, if history can't say, deleting is offered, and committing reports what went wrong.
        waitingIDs.contains(session.id) || (try? history.canEdit(id: session.id)) != false
    }

    /// Hides `session` and makes it the deletion that can still be undone, after committing any earlier one.
    /// Storage changes only on ``commitDelete()``, so a session deleted just before the app is killed is kept.
    func delete(_ session: PracticeSession) {
        guard canDelete(session) else { return }
        commitDelete()
        if editing?.id == session.id { editing = nil }
        pendingDeletion = session
        refresh()
    }

    /// Shows the pending deletion again.
    func undoDelete() {
        pendingDeletion = nil
        refresh()
    }

    /// Deletes the pending deletion from storage. If that fails, it shows again with an error.
    func commitDelete() {
        guard let id = pendingDeletion?.id else { return }
        pendingDeletion = nil
        do {
            // The outbox first, so a copy can't stay there to show again as waiting, or to be saved by a
            // later archive; if this fails, nothing is deleted.
            try outbox.remove(id: id)
            do {
                // History too, in case it saved a waiting session since.
                try history.delete(id: id)
            } catch  where waitingIDs.contains(id) {
                // History being down is why it was waiting; out of the outbox, it's gone. If history had saved
                // it and only a copy lingered, it shows again once history opens (Ed's call: stay quiet).
                logger.error("Couldn't delete a waiting session from history: \(error, privacy: .public)")
            }
        } catch {
            logger.error("Couldn't delete a session: \(error, privacy: .public)")
            isShowingDeleteError = true
        }
        refresh()
    }

    /// Starts editing `session`, unless it's still waiting to be saved (ADR 0007).
    func edit(_ session: PracticeSession) {
        guard !waitingIDs.contains(session.id) else { return }
        let now = clock.now
        editing = SessionEdit(
            session: session, others: otherSessions(at: now), history: history, library: tags, now: now)
    }

    /// Starts editing the session with `id` as history has it now, for the cap banner, whose copy may be out of
    /// date (SES-4). Nothing opens if it's gone.
    func edit(id: UUID) {
        refresh()
        if let session = days.lazy.flatMap(\.sessions).first(where: { $0.id == id }) {
            edit(session)
        }
    }

    /// Starts adding a session after the fact, 30 minutes long, to adjust (SES-5). It ends now or, if that
    /// would overlap sessions, at the start of each one it meets in turn until it overlaps none, so the
    /// overlap warning doesn't show before anything has been changed.
    func add() {
        let now = clock.now
        let length: TimeInterval = 30 * 60
        let others = otherSessions(at: now)
        var end = now
        // Newest first, as otherSessions lists them, so each overlapping session moves the end back past it in turn.
        for other in others where other.startedAt < end && (other.endedAt ?? end) > end - length {
            end = other.startedAt
        }
        var session = PracticeSession(startedAt: end - length, timeZone: .current, source: .manual)
        // Can't fail: the session is running, and ends after it started.
        try? session.stop(at: end)
        editing = SessionEdit(
            session: session, isNew: true, others: others, history: history, library: tags, now: now)
    }

    /// The sessions a session being edited or added keeps clear of: the running one, as if it ended at `now`, then
    /// the shown ones, newest first (SES-5). The running session's store isn't changed.
    private func otherSessions(at now: Date) -> [PracticeSession] {
        // A store that can't be read is reported by Practice.
        guard var current = try? running.current() else { return days.flatMap(\.sessions) }
        // No earlier than its last change, so a clock set back still ends the copy, and the warning still names it.
        if current.state != .ended { try? current.stop(at: max(now, current.latestEvent)) }
        return [current] + days.flatMap(\.sessions)
    }
}
