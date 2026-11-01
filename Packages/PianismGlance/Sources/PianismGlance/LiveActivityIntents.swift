import AppIntents

// The Live Activity's buttons (GLN-1). Each runs in the app's process, as `StartPracticeIntent` does, and calls the
// matching command, so a Stop on the Lock Screen takes the same path as a Stop on Practice (ADR 0010). The titles are
// literals and never shown, and `isDiscoverable` hides them from Shortcuts, as for Start.

/// Pauses the session from the Live Activity.
public struct PausePracticeIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Pause practice"
    public static let isDiscoverable = false

    @AppDependency public var commands: GlanceCommands

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await commands.pause()
        return .result()
    }
}

/// Resumes the session from the Live Activity.
public struct ResumePracticeIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Resume practice"
    public static let isDiscoverable = false

    @AppDependency public var commands: GlanceCommands

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await commands.resume()
        return .result()
    }
}

/// Ends the session from the Live Activity.
public struct StopPracticeIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop practice"
    public static let isDiscoverable = false

    @AppDependency public var commands: GlanceCommands

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await commands.stop()
        return .result()
    }
}
