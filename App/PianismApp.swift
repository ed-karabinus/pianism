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

    init() {
        guard let store = FileRunningSessionStore(appGroup: Self.appGroup) else {
            // Without the App Group, the widget and Live Activity couldn't see the session.
            fatalError("Missing the \(Self.appGroup) App Group entitlement.")
        }
        var clock: any WallClock = SystemClock()
        #if DEBUG
            // End-to-end tests fix the time with PIANISM_NOW (seconds since 1970) and start with
            // no running session with PIANISM_RESET=1. Release builds ignore both.
            let environment = ProcessInfo.processInfo.environment
            if let seconds = environment["PIANISM_NOW"].flatMap(TimeInterval.init) {
                clock = FixedClock(now: Date(timeIntervalSince1970: seconds))
            }
            if environment["PIANISM_RESET"] == "1" {
                try? store.update { $0 = nil }
            }
        #endif
        practice = PracticeModel(store: store, history: UnsavedSessionHistory(), clock: clock)
    }

    var body: some Scene {
        WindowGroup {
            RootView(practice: practice)
        }
    }
}

/// Stands in for the synced history until it lands with HIS-1 (#14, ADR 0004): finished sessions
/// are not kept yet.
private struct UnsavedSessionHistory: SessionHistory {
    func save(_ session: PracticeSession) {}
}

/// A clock that always reads the same time, for end-to-end tests.
private struct FixedClock: WallClock {
    let now: Date
}
