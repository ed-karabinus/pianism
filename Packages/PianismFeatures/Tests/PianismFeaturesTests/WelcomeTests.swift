import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
struct WelcomeTests {
    let clock = ManualClock()
    let store = InMemoryRunningSessionStore()
    /// Stands in for the device's settings, new for each test.
    let defaults = UserDefaults(suiteName: "WelcomeTests-\(UUID())") ?? .standard

    private func launch() -> PracticeModel {
        PracticeModel(
            store: store, history: InMemorySessionHistory(), outbox: InMemorySessionHistory(), clock: clock,
            nudges: InMemoryNudges(), glance: InMemoryPracticeGlance(), defaults: defaults, nudge: 90 * 60,
            cap: 4 * 60 * 60)
    }

    @Test("ONB-1: the first launch with no practice opens the welcome")
    func firstLaunchWithNoPracticeWelcomes() {
        let model = launch()

        model.offerWelcome(historyIsEmpty: true)

        #expect(model.isShowingWelcome)
    }

    @Test("ONB-1: the welcome shows once, even if it's still true that there's no practice")
    func welcomeShowsOnce() {
        launch().offerWelcome(historyIsEmpty: true)
        let relaunched = launch()

        relaunched.offerWelcome(historyIsEmpty: true)

        #expect(!relaunched.isShowingWelcome)
    }

    @Test("ONB-1: returning to the app while it's up doesn't open a welcome that was closed")
    func aClosedWelcomeStaysClosed() {
        let model = launch()
        model.offerWelcome(historyIsEmpty: true)
        model.isShowingWelcome = false

        model.offerWelcome(historyIsEmpty: true)

        #expect(!model.isShowingWelcome)
    }

    @Test("ONB-1: someone with practice never sees the welcome, even after deleting all of it")
    func practiceMeansNoWelcome() {
        let withPractice = launch()
        withPractice.offerWelcome(historyIsEmpty: false)
        #expect(!withPractice.isShowingWelcome)
        let afterDeleting = launch()

        afterDeleting.offerWelcome(historyIsEmpty: true)

        #expect(!afterDeleting.isShowingWelcome)
    }

    @Test("ONB-1: a session already running, as from the widget's Start, means no welcome")
    func aRunningSessionMeansNoWelcome() {
        let model = launch()
        model.start()

        model.offerWelcome(historyIsEmpty: true)

        #expect(!model.isShowingWelcome)
    }

    @Test("ONB-1: a piano's notes starting a session close the welcome, which would hide the clock")
    func notesThatStartASessionCloseTheWelcome() {
        let model = launch()
        model.offerWelcome(historyIsEmpty: true)

        for _ in 1...3 { model.noteOn(at: clock.now) }

        #expect(model.session?.source == .midi)
        #expect(!model.isShowingWelcome)
    }

    @Test("ONB-1: skipping the welcome is the same as having decided it")
    func skippingMeansNoWelcome() {
        PracticeModel.skipWelcome(in: defaults)
        let model = launch()

        model.offerWelcome(historyIsEmpty: true)

        #expect(!model.isShowingWelcome)
    }
}
