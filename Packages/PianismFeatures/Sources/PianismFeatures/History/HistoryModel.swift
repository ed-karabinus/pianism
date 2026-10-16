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
    /// Whether the last load failed, so the screen can say so instead of looking empty.
    private(set) var loadFailed = false

    let clock: any WallClock
    let calendar = Calendar.autoupdatingCurrent
    private let history: any SessionHistory
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "history")

    public init(history: any SessionHistory, clock: any WallClock) {
        self.history = history
        self.clock = clock
    }

    /// Loads the history again. Call when the screen appears, since sessions finish elsewhere.
    func refresh() {
        do {
            days = PracticeDay.group(try history.sessions(), in: calendar)
            loadFailed = false
        } catch {
            logger.error("Couldn't load the history: \(error, privacy: .public)")
            loadFailed = true
        }
    }
}
