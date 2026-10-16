import Foundation
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
            Tab(Self.title("Practice"), systemImage: "pianokeys") {
                PracticeView(model: practice)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(AccessibilityID.root)
            }
            Tab(Self.title("History"), systemImage: "calendar") {
                HistoryView(model: history)
            }
        }
        // Restores a session after the app was killed, and shows changes made while it was away.
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active { practice.refresh() }
        }
    }

    /// A tab title from this package's String Catalog.
    private static func title(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}

/// Accessibility identifiers, which the UI tests look up by the same strings.
enum AccessibilityID {
    static let root = "root"
    static let practiceStatus = "practice.status"
    static let practiceElapsed = "practice.elapsed"
    static let practiceLastSession = "practice.last-session"
    static let practiceStart = "practice.start"
    static let practicePause = "practice.pause"
    static let practiceResume = "practice.resume"
    static let practiceStop = "practice.stop"
    static let historyEmpty = "history.empty"
    static let historyDay = "history.day"
    static let historySession = "history.session"
}

#Preview {
    RootView(practice: .preview(.ready), history: .preview())
}
