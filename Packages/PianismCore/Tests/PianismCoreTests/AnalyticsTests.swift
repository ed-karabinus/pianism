import Foundation
import PianismCore
import Testing

struct AnalyticsTests {
    private let launch = Date(timeIntervalSince1970: 1_798_761_600)
    private let day: TimeInterval = 24 * 60 * 60

    /// These names and details are what ADR 0011 promises, and renaming one splits its history on the dashboard.
    @Test func theSignalsAreTheOnesTheADRLists() {
        #expect(AnalyticsSignal.firstLaunch.name == "Install.firstLaunch")
        #expect(AnalyticsSignal.firstLaunch.parameters.isEmpty)
        #expect(AnalyticsSignal.activationReached.name == "Activation.reached")
        #expect(AnalyticsSignal.activationReached.parameters.isEmpty)
        #expect(AnalyticsSignal.sessionSaved(.timer).name == "Practice.sessionSaved")
        #expect(AnalyticsSignal.sessionSaved(.timer).parameters == ["source": "timer"])
        #expect(AnalyticsSignal.sessionSaved(.midi).parameters == ["source": "midi"])
        #expect(AnalyticsSignal.sessionSaved(.manual).parameters == ["source": "manual"])
    }

    /// Saves one new session at each of these times, and returns which of them reached activation.
    private func reached(_ progress: inout ActivationProgress, at dates: [Date]) -> [Bool] {
        dates.map { progress.sessionSaved(id: UUID(), at: $0) }
    }

    @Test func theThirdSessionReachesActivationOnce() {
        var progress = ActivationProgress(firstLaunch: launch, isCounting: true)
        let results = reached(&progress, at: [launch, launch + day, launch + 2 * day, launch + 3 * day])
        #expect(results == [false, false, true, false])
    }

    @Test func aSessionSavedTwiceCountsOnce() {
        var progress = ActivationProgress(firstLaunch: launch, isCounting: true)
        let repeated = UUID()
        let first = progress.sessionSaved(id: repeated, at: launch)
        let again = progress.sessionSaved(id: repeated, at: launch)
        let results = reached(&progress, at: [launch, launch])
        #expect([first, again] + results == [false, false, false, true])
    }

    @Test func theSeventhDayCountsAndAfterItDoesNot() {
        var inTime = ActivationProgress(firstLaunch: launch, isCounting: true)
        var late = inTime
        #expect(reached(&inTime, at: [launch, launch, launch + 7 * day]) == [false, false, true])
        #expect(reached(&late, at: [launch, launch, launch + 7 * day + 1]) == [false, false, false])
    }

    @Test func offAtFirstLaunchActivationNeverComes() {
        var progress = ActivationProgress(firstLaunch: launch, isCounting: false)
        #expect(reached(&progress, at: [launch, launch, launch, launch]) == [false, false, false, false])
    }

    @Test func progressSurvivesBeingStored() throws {
        var progress = ActivationProgress(firstLaunch: launch, isCounting: true)
        _ = reached(&progress, at: [launch, launch])
        var restored = try JSONDecoder().decode(ActivationProgress.self, from: JSONEncoder().encode(progress))
        #expect(restored == progress)
        #expect(reached(&restored, at: [launch]) == [true])
    }
}
