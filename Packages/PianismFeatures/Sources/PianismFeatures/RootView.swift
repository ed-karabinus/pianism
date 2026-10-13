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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.root)
            // Restores a session after the app was killed, and shows changes made while it was away.
            .onChange(of: scenePhase, initial: true) {
                if scenePhase == .active { practice.refresh() }
            }
    }
}

/// Accessibility identifiers shared with the UI tests.
public enum AccessibilityID {
    public static let root = "root"
    public static let practiceStatus = "practice.status"
    public static let practiceElapsed = "practice.elapsed"
    public static let practiceLastSession = "practice.last-session"
    public static let practiceStart = "practice.start"
    public static let practicePause = "practice.pause"
    public static let practiceResume = "practice.resume"
    public static let practiceStop = "practice.stop"
}

#Preview {
    RootView(practice: .preview(.ready))
}
