/// What the widget's and the Live Activity's buttons do to the session, which the app registers at launch with App
/// Intents' dependency manager (ADR 0010). An intent calls these rather than the model, so this package never links
/// PianismFeatures, and each takes the same path as a tap on Practice, nudge and cap included. Each returns once the
/// Live Activity has taken the change, so the system doesn't suspend the app before it lands.
public struct GlanceCommands: Sendable {
    public typealias Command = @MainActor @Sendable () async -> Void

    public let start: Command
    public let pause: Command
    public let resume: Command
    public let stop: Command

    public init(start: @escaping Command, pause: @escaping Command, resume: @escaping Command, stop: @escaping Command)
    {
        self.start = start
        self.pause = pause
        self.resume = resume
        self.stop = stop
    }
}
