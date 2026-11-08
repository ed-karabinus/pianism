import Foundation

/// Everything Pianism tells its analytics service (ADR 0011). A new signal or detail needs that ADR changed first, and
/// nothing here may carry what someone practiced or typed.
public enum AnalyticsSignal: Sendable, Hashable {
    case firstLaunch
    case sessionSaved(PracticeSession.Source)
    case activationReached
    /// The Pro screen opened (PRO-3). Buying and restoring send nothing, which keeps Purchase History off the App
    /// Store's privacy label (ADR 0011).
    case paywallShown

    public var name: String {
        switch self {
        case .firstLaunch: "Install.firstLaunch"
        case .sessionSaved: "Practice.sessionSaved"
        case .activationReached: "Activation.reached"
        case .paywallShown: "Paywall.shown"
        }
    }

    public var parameters: [String: String] {
        switch self {
        case .firstLaunch, .activationReached, .paywallShown: [:]
        case .sessionSaved(let source): ["source": source.rawValue]
        }
    }
}

/// Where analytics signals go. Turned off, nothing further may leave the device.
public protocol Analytics: Sendable {
    @MainActor func setEnabled(_ enabled: Bool)
    @MainActor func send(_ signal: AnalyticsSignal)
}

/// Sends nothing: Debug builds, tests, and a Release build with no App ID.
public struct NoAnalytics: Analytics {
    public init() {}
    public func setEnabled(_ enabled: Bool) {}
    public func send(_ signal: AnalyticsSignal) {}
}

/// How far a new user is toward activation: 3 sessions saved within 7 days of first launch (ADR 0011).
public struct ActivationProgress: Codable, Hashable, Sendable {
    private static let sessionsNeeded = 3
    private static let days: TimeInterval = 7 * 24 * 60 * 60

    private let firstLaunch: Date
    /// With analytics off at first launch, its signal never went, so activation mustn't either: the ratio of the two
    /// is the number we read.
    private let isCounting: Bool
    /// By ID, as saving a session twice is harmless (``SessionHistory/save(_:)``) and mustn't count twice.
    private var saved: Set<UUID> = []

    public init(firstLaunch: Date, isCounting: Bool) {
        self.firstLaunch = firstLaunch
        self.isCounting = isCounting
    }

    /// Counts a saved session, and returns whether this one reached activation, which happens once.
    public mutating func sessionSaved(id: UUID, at date: Date) -> Bool {
        guard isCounting, date <= firstLaunch + Self.days else { return false }
        return saved.insert(id).inserted && saved.count == Self.sessionsNeeded
    }
}
