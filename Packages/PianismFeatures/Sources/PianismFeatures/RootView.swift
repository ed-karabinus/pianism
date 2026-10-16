import SwiftUI

/// The app's top-level screen: a tab per area.
public struct RootView: View {
    let practice: PracticeModel
    let history: HistoryModel

    @Environment(\.scenePhase) private var scenePhase

    public init(practice: PracticeModel, history: HistoryModel) {
        self.practice = practice
        self.history = history
    }

    public var body: some View {
        TabView {
            Tab(LocalizedStringResource("Practice", bundle: .module), systemImage: "pianokeys") {
                PracticeView(model: practice)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(AccessibilityID.root)
            }
            Tab(LocalizedStringResource("History", bundle: .module), systemImage: "calendar") {
                HistoryView(model: history)
            }
        }
        // Shows changes made while the app was away, and moves "today" along after midnight.
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                practice.refresh()
                history.refresh()
            }
        }
    }
}

/// Accessibility identifiers, which the UI tests look up by the same strings.
enum AccessibilityID {
    static let root = "root"
    static let practiceStatus = "practice.status"
    static let practiceElapsed = "practice.elapsed"
    static let practiceLastSession = "practice.last-session"
    static let practiceWaiting = "practice.waiting"
    static let practiceStart = "practice.start"
    static let practicePause = "practice.pause"
    static let practiceResume = "practice.resume"
    static let practiceStop = "practice.stop"
    static let historyEmpty = "history.empty"
    static let historyUnavailable = "history.unavailable"
    static let historyDay = "history.day"
    static let historySession = "history.session"
}

#Preview {
    RootView(practice: .preview(.ready), history: .preview())
}
