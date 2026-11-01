/// What the widget's buttons do to the session, which the app registers at launch with App Intents' dependency
/// manager (ADR 0010). An intent calls these rather than the model, so this package never links PianismFeatures,
/// and the start takes the same path as a tap on Practice, nudge and cap included.
public struct GlanceCommands: Sendable {
    public let start: @MainActor @Sendable () async -> Void

    public init(start: @escaping @MainActor @Sendable () async -> Void) {
        self.start = start
    }
}
