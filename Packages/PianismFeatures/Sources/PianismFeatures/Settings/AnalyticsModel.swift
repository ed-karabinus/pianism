import Foundation
import PianismCore

/// The switch for anonymous analytics, and what to send when (ADR 0011). Created once at launch, which is what makes
/// the very first one a first launch.
@MainActor
@Observable
public final class AnalyticsModel {
    /// Whether analytics is on, as set in Settings. On by default; off, nothing further leaves the device.
    public var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: SettingsKey.sharesUsage)
            analytics.setEnabled(isOn)
        }
    }

    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private var progress: ActivationProgress

    public init(analytics: any Analytics, defaults: UserDefaults, clock: any WallClock) {
        self.analytics = analytics
        self.defaults = defaults
        self.clock = clock
        let isOn = defaults.object(forKey: SettingsKey.sharesUsage) as? Bool ?? true
        self.isOn = isOn
        analytics.setEnabled(isOn)
        if let stored = defaults.data(forKey: SettingsKey.activationProgress)
            .flatMap({ try? JSONDecoder().decode(ActivationProgress.self, from: $0) })
        {
            progress = stored
        } else {
            progress = ActivationProgress(firstLaunch: clock.now, isCounting: isOn)
            store()
            if isOn { analytics.send(.firstLaunch) }
        }
    }

    /// Call once a session is saved, however it was made (timer, piano or by hand). Counts toward activation even
    /// while off, but sends nothing then.
    func sessionSaved(_ session: PracticeSession) {
        let reached = progress.sessionSaved(id: session.id, at: clock.now)
        store()
        guard isOn else { return }
        analytics.send(.sessionSaved(session.source))
        if reached { analytics.send(.activationReached) }
    }

    private func store() {
        defaults.set(try? JSONEncoder().encode(progress), forKey: SettingsKey.activationProgress)
    }
}
