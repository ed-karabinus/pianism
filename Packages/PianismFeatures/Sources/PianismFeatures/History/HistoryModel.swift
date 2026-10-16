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

    let calendar = Calendar.autoupdatingCurrent
    private let clock: any WallClock
    private let history: any SessionHistory
    private let outbox: any SessionOutbox
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    public init(history: any SessionHistory, outbox: any SessionOutbox, clock: any WallClock) {
        self.history = history
        self.outbox = outbox
        self.clock = clock
        self.now = clock.now
    }

    /// Loads the history again, and moves "today" along. Call when the screen appears and when the
    /// app returns to the foreground: sessions finish elsewhere, and midnight may have passed.
    func refresh() {
        now = clock.now
        var waiting: [PracticeSession] = []
        do {
            waiting = try outbox.sessions()
        } catch {
            logger.error("Couldn't read the waiting sessions: \(error, privacy: .public)")
        }
        var saved: [PracticeSession] = []
        do {
            saved = try history.sessions()
            loadFailed = false
        } catch {
            logger.error("Couldn't load the history: \(error, privacy: .public)")
            loadFailed = true
        }
        // A session can be in both for a moment, between being saved and leaving the outbox.
        let savedIDs = Set(saved.map(\.id))
        let unsaved = waiting.filter { !savedIDs.contains($0.id) }
        waitingIDs = Set(unsaved.map(\.id))
        days = PracticeDay.group(saved + unsaved, in: calendar)
    }
}
