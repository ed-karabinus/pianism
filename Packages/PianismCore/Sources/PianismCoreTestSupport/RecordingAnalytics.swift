import PianismCore

/// Records what would have been sent.
@MainActor
public final class RecordingAnalytics: Analytics {
    public private(set) var sent: [AnalyticsSignal] = []
    public private(set) var enabledChanges: [Bool] = []

    public init() {}

    public func setEnabled(_ enabled: Bool) {
        enabledChanges.append(enabled)
    }

    public func send(_ signal: AnalyticsSignal) {
        sent.append(signal)
    }
}
