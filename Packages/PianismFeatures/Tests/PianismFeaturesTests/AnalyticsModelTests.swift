import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
struct AnalyticsModelTests {
    private let analytics = RecordingAnalytics()
    private let defaults: UserDefaults
    private let clock = ManualClock()

    init() throws {
        let suite = "AnalyticsModelTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    private func makeModel() -> AnalyticsModel {
        AnalyticsModel(analytics: analytics, defaults: defaults, clock: clock)
    }

    private func session(_ source: PracticeSession.Source = .timer) -> PracticeSession {
        PracticeSession(startedAt: clock.now, source: source)
    }

    @Test func isOnByDefaultAndSaysSoOnce() {
        let model = makeModel()
        #expect(model.isOn)
        #expect(analytics.enabledChanges == [true])
        #expect(analytics.sent == [.firstLaunch])
    }

    @Test func aLaterLaunchIsNotAFirstLaunch() {
        _ = makeModel()
        _ = makeModel()
        #expect(analytics.sent == [.firstLaunch])
    }

    @Test func aSavedSessionSaysHowItWasMade() {
        let model = makeModel()
        model.sessionSaved(session(.midi))
        model.sessionSaved(session(.manual))
        #expect(analytics.sent == [.firstLaunch, .sessionSaved(.midi), .sessionSaved(.manual)])
    }

    @Test func theThirdSessionReachesActivationAcrossLaunchesOnce() {
        makeModel().sessionSaved(session())
        makeModel().sessionSaved(session())
        let model = makeModel()
        model.sessionSaved(session())
        model.sessionSaved(session())
        #expect(
            analytics.sent == [
                .firstLaunch, .sessionSaved(.timer), .sessionSaved(.timer), .sessionSaved(.timer), .activationReached,
                .sessionSaved(.timer),
            ])
    }

    @Test func turnedOffItSendsNothingFurtherAndStaysOff() {
        let model = makeModel()
        model.isOn = false
        model.sessionSaved(session())
        #expect(analytics.enabledChanges == [true, false])
        #expect(analytics.sent == [.firstLaunch])

        let relaunched = makeModel()
        #expect(!relaunched.isOn)
        #expect(analytics.enabledChanges.last == false)
    }

    /// So the ratio of activation to first launches stays honest.
    @Test func offAtFirstLaunchNeitherIsEverSentEvenIfTurnedOnLater() {
        defaults.set(false, forKey: SettingsKey.sharesUsage)
        let model = makeModel()
        #expect(analytics.sent.isEmpty)
        model.isOn = true
        for _ in 0..<3 { model.sessionSaved(session()) }
        let later = makeModel()
        later.sessionSaved(session())
        #expect(analytics.sent == Array(repeating: .sessionSaved(.timer), count: 4))
    }

    @Test func aSessionSavedWhileOffStillCountsTowardActivation() {
        let model = makeModel()
        model.isOn = false
        model.sessionSaved(session())
        model.isOn = true
        model.sessionSaved(session())
        model.sessionSaved(session())
        #expect(analytics.sent.last == .activationReached)
    }
}
