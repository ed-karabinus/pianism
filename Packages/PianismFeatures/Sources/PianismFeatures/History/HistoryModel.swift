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
    /// The sessions shown that history hasn't saved yet (ADR 0007).
    private(set) var waitingIDs: Set<UUID> = []
    /// The time of the last refresh, which decides what counts as today and yesterday.
    private(set) var now: Date
    /// Whether the last refresh couldn't read the history. Waiting sessions still show.
    private(set) var loadFailed = false
    /// The tags sessions show, each merged tag as the tag it was merged into (ADR 0004).
    private(set) var tagIndex = TagIndex([])
    /// The finished session being edited, if any (SES-5).
    var editing: SessionEdit?

    let calendar = Calendar.autoupdatingCurrent
    private let clock: any WallClock
    private let history: any SessionHistory
    private let tags: any TagLibrary
    private let outbox: any SessionOutbox
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    public init(history: any SessionHistory, tags: any TagLibrary, outbox: any SessionOutbox, clock: any WallClock) {
        self.history = history
        self.tags = tags
        self.outbox = outbox
        self.clock = clock
        self.now = clock.now
    }

    /// Loads the history again, and moves "today" along. Call when the screen appears and when the
    /// app returns to the foreground: sessions finish elsewhere, and midnight may have passed.
    func refresh() {
        now = clock.now
        // An outbox that can't be read is reported by Practice, which raises its storage alert.
        let waiting = (try? outbox.sessions()) ?? []
        var saved: [PracticeSession] = []
        do {
            saved = try history.sessions()
            tagIndex = TagIndex(try tags.allTags())
            loadFailed = false
        } catch {
            logger.error("Couldn't load the history: \(error, privacy: .public)")
            loadFailed = true
        }
        // A session can be in both, when history saved it but it couldn't leave the outbox. It shows
        // once, as saved.
        let savedIDs = Set(saved.map(\.id))
        let unsaved = waiting.filter { !savedIDs.contains($0.id) }
        waitingIDs = Set(unsaved.map(\.id))
        days = PracticeDay.group(saved + unsaved, in: calendar)
    }

    /// Starts editing `session`, unless it's still waiting to be saved (ADR 0007).
    func edit(_ session: PracticeSession) {
        guard !waitingIDs.contains(session.id) else { return }
        editing = SessionEdit(session: session, history: history, library: tags, now: clock.now)
    }

    /// Starts adding a session after the fact: one ending now and 30 minutes long, to adjust (SES-5).
    func add() {
        let now = clock.now
        var session = PracticeSession(startedAt: now.addingTimeInterval(-30 * 60), timeZone: .current)
        // Can't fail: the session is running, and ends after it started.
        try? session.stop(at: now)
        editing = SessionEdit(session: session, isNew: true, history: history, library: tags, now: now)
    }
}
