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
        let options = LaunchOptions.current
        if options.reset {
            try? store.update { $0 = nil }
        }
        let clock = options.clock ?? SystemClock()
        _practice = State(
            initialValue: PracticeModel(
                recorder: SessionRecorder(store: store, clock: clock),
                history: UnsavedSessionHistory(),
                clock: clock
            )
        )
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
