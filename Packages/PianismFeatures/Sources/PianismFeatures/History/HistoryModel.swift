import Foundation
import Observation
import PianismCore
import os

/// State for the History screen (HIS-1): finished sessions, grouped by the day they started.
@MainActor
@Observable
public final class HistoryModel {
    /// Days with practice, newest first.
    private(set) var days: [PracticeDay] = []
    /// The time of the last refresh, which decides what counts as today and yesterday.
    private(set) var now: Date
    /// Whether the last refresh couldn't read the history.
    private(set) var loadFailed = false

    let calendar = Calendar.autoupdatingCurrent
    private let clock: any WallClock
    private let history: any SessionHistory
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    public init(history: any SessionHistory, clock: any WallClock) {
        self.history = history
        self.clock = clock
        self.now = clock.now
    }

    /// Loads the history again, and moves "today" along. Call when the screen appears and when the
    /// app returns to the foreground: sessions finish elsewhere, and midnight may have passed.
    func refresh() {
        now = clock.now
        do {
            days = PracticeDay.group(try history.sessions(), in: calendar)
            loadFailed = false
        } catch {
            logger.error("Couldn't load the history: \(error, privacy: .public)")
            loadFailed = true
        }
    }
}
