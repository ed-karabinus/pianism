import AppIntents

/// Starts a session from the widget's Start (GLN-2). A `LiveActivityIntent` runs in the app's process, which the
/// system launches in the background if need be, so only the app ever writes the session (ADR 0010).
public struct StartPracticeIntent: LiveActivityIntent {
    /// Required, but never shown: the widget's button has its own label, and Shortcuts doesn't offer the intent. A
    /// literal, as the metadata processor reads it at build time and takes no bundle but the app's.
    public static let title: LocalizedStringResource = "Start practice"
    /// Only the widget's button runs it, so Shortcuts and Spotlight don't offer it.
    public static let isDiscoverable = false

    /// The app's commands, which the system hands the intent when it performs it. Set by hand only where the app
    /// performs the intent itself, for an end-to-end test; the system injects nothing then.
    @AppDependency public var commands: GlanceCommands

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await commands.start()
        return .result()
    }
}
