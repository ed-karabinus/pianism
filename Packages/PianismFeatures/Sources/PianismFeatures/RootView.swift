import SwiftUI

/// The app's top-level screen.
public struct RootView: View {
    let practice: PracticeModel

    @Environment(\.scenePhase) private var scenePhase

    public init(practice: PracticeModel) {
        self.practice = practice
    }

    public var body: some View {
        PracticeView(model: practice)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.root)
            // Restores a session after the app was killed, and shows changes made while it was away.
            .onChange(of: scenePhase, initial: true) {
                if scenePhase == .active { practice.refresh() }
            }
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
}

#Preview {
    RootView(practice: .preview(.ready))
}
