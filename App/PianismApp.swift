import Foundation
import PianismCore
import PianismFeatures
import PianismPersistence
import SwiftUI

/// The composition root: the only place that wires concrete adapters into the core.
@main
struct PianismApp: App {
    /// Shared with the widget and Live Activity. Must match `Config/Pianism.entitlements`.
    static let appGroup = "group.com.edkarabinus.Pianism"

    @State private var practice: PracticeModel
    @State private var history: HistoryModel

    init() {
        guard let store = FileRunningSessionStore(appGroup: Self.appGroup) else {
            // Without the App Group, the widget and Live Activity couldn't see the session.
            fatalError("Missing the \(Self.appGroup) App Group entitlement.")
        }
        var clock: any WallClock = SystemClock()
        var historyURL = URL.applicationSupportDirectory.appending(path: "History/History.store")
        // Finished sessions wait here while history can't save them (ADR 0007). Only the app moves
        // sessions into history, so this stays out of the App Group.
        let outboxURL = URL.applicationSupportDirectory.appending(path: "Outbox")
        #if DEBUG
            // End-to-end tests fix the time with PIANISM_NOW (seconds since 1970), start with no
            // running session, history or outbox with PIANISM_RESET=1, and make the history fail to
            // open with PIANISM_BREAK_HISTORY=1. Release builds ignore all three.
            let environment = ProcessInfo.processInfo.environment
            if let seconds = environment["PIANISM_NOW"].flatMap(TimeInterval.init) {
                clock = FixedClock(now: Date(timeIntervalSince1970: seconds))
            }
            if environment["PIANISM_RESET"] == "1" {
                try? store.update { $0 = nil }
                try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent())
                try? FileManager.default.removeItem(at: outboxURL)
            }
            if environment["PIANISM_BREAK_HISTORY"] == "1" {
                historyURL = URL(filePath: "/dev/null/History.store")
            }
        #endif
        let sessions = SwiftDataSessionHistory(store: HistoryStore(url: historyURL), clock: clock)
        let outbox = FileSessionOutbox(directory: outboxURL)
        practice = PracticeModel(store: store, history: sessions, outbox: outbox, clock: clock)
        history = HistoryModel(history: sessions, outbox: outbox, clock: clock)
    }

    var body: some Scene {
        WindowGroup {
            RootView(practice: practice, history: history)
        }
    }
}

/// A clock that always reads the same time, for end-to-end tests.
private struct FixedClock: WallClock {
    let now: Date
}
