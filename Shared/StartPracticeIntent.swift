import ActivityKit
import AppIntents
import PianismCore
import PianismPersistence

/// Starts a practice session and its Live Activity from a widget, without opening the app (spike #17).
///
/// As a `LiveActivityIntent`, it runs in the app's process: the system launches the app in the
/// background to perform it. The widget extension compiles it too, so its button can name it.
struct StartPracticeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Practice"

    func perform() async throws -> some IntentResult {
        guard let store = FileRunningSessionStore(appGroup: "group.com.edkarabinus.Pianism") else {
            throw SpikeError.noAppGroup
        }
        let session = try SessionRecorder(store: store, clock: SystemClock()).start()
        _ = try Activity.request(
            attributes: PracticeAttributes(),
            content: ActivityContent(state: .init(startedAt: session.startedAt), staleDate: nil)
        )
        return .result()
    }
}

enum SpikeError: Error {
    case noAppGroup
}
