import Foundation
import PianismCore
import PianismCoreTestSupport
import Testing

@testable import PianismFeatures

@MainActor
struct ProModelTests {
    private let defaults: UserDefaults
    private let analytics = RecordingAnalytics()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "ProModelTests.\(UUID().uuidString)"))
    }

    private func proModel(_ store: InMemoryProStore) -> ProModel {
        ProModel(
            store: store, defaults: defaults,
            analytics: AnalyticsModel(analytics: analytics, defaults: defaults, clock: SystemClock()))
    }

    private func refreshed(_ store: InMemoryProStore) async -> ProModel {
        let model = proModel(store)
        await model.refresh()
        return model
    }

    @Test("PRO-1: Pro is off until the store says otherwise")
    func offByDefault() async {
        #expect(await !refreshed(InMemoryProStore()).isPro)
    }

    @Test("PRO-1: the store saying so unlocks Pro, and the next launch knows without asking")
    func unlocksAndRemembers() async {
        #expect(await refreshed(InMemoryProStore(status: .entitled)).isPro)
        #expect(proModel(InMemoryProStore()).isPro)
    }

    @Test("PRO-1: someone who paid keeps Pro when the store's answer comes back empty")
    func anEmptyAnswerKeepsPro() async {
        _ = await refreshed(InMemoryProStore(status: .entitled))
        #expect(await refreshed(InMemoryProStore(status: .unknown)).isPro)
    }

    @Test("PRO-1: a refund turns Pro off, and it stays off")
    func aRefundTurnsItOff() async {
        _ = await refreshed(InMemoryProStore(status: .entitled))
        #expect(await !refreshed(InMemoryProStore(status: .revoked)).isPro)
        #expect(await !refreshed(InMemoryProStore(status: .unknown)).isPro)
    }

    /// The key is permanent (`SettingsKey`): someone who paid must still have Pro after an update.
    @Test("PRO-1: Pro is stored under its permanent key")
    func storedKey() async {
        _ = await refreshed(InMemoryProStore(status: .entitled))
        #expect(defaults.bool(forKey: "proUnlocked"))
    }

    /// Waits with a deadline, not `.timeLimit`, which only cancels: these loops would spin on past it.
    @Test("PRO-1: a change in the store reaches an open app, both ways")
    func followsTheStore() async throws {
        let store = InMemoryProStore()
        let model = proModel(store)
        let following = Task { await model.keepUpToDate() }
        defer { following.cancel() }
        await store.set(.entitled)
        var deadline = ContinuousClock.now + .seconds(10)
        while !model.isPro {
            try #require(ContinuousClock.now < deadline, "A purchase didn't reach the open app")
            await Task.yield()
        }
        await store.set(.revoked)
        deadline = ContinuousClock.now + .seconds(10)
        while model.isPro {
            try #require(ContinuousClock.now < deadline, "A refund didn't reach the open app")
            await Task.yield()
        }
    }

    @Test("PRO-1: a restore that finds the purchase unlocks Pro and says nothing else")
    func restoreFinds() async {
        let model = proModel(InMemoryProStore(restoreFinds: true))
        await model.restore()
        #expect(model.isPro)
        #expect(model.restoreNotice == nil)
        #expect(!model.isRestoring)
    }

    @Test("PRO-1: a restore that finds nothing says so")
    func restoreFindsNothing() async {
        let model = proModel(InMemoryProStore())
        await model.restore()
        #expect(!model.isPro)
        #expect(model.restoreNotice == .noPurchase)
    }

    @Test("PRO-1: a restore that fails says so, and leaves Pro as it was")
    func restoreFails() async {
        _ = await refreshed(InMemoryProStore(status: .entitled))
        let model = proModel(InMemoryProStore(status: .revoked, restoring: .failed))
        await model.restore()
        #expect(model.restoreNotice == .unreachable)
        #expect(model.isPro)
    }

    @Test("PRO-1: cancelling a restore says nothing")
    func restoreCancelled() async {
        let model = proModel(InMemoryProStore(restoring: .cancelled))
        await model.restore()
        #expect(model.restoreNotice == nil)
        #expect(!model.isPro)
    }

    @Test("PRO-1: trying again clears what the last restore said")
    func aNewRestoreClearsTheNotice() async {
        let store = InMemoryProStore()
        let model = proModel(store)
        await model.restore()
        #expect(model.restoreNotice == .noPurchase)
        await store.set(.entitled)
        await model.restore()
        #expect(model.restoreNotice == nil)
    }

    @Test("PRO-1: a restore that finds a refunded purchase turns Pro off and says nothing's there")
    func restoreFindsARefund() async {
        _ = await refreshed(InMemoryProStore(status: .entitled))
        let model = proModel(InMemoryProStore(status: .revoked))
        await model.restore()
        #expect(!model.isPro)
        #expect(model.restoreNotice == .noPurchase)
    }

    @Test("PRO-3: buying unlocks Pro straight away, and the next launch knows")
    func buy() async {
        let model = proModel(InMemoryProStore())
        await model.buy()
        #expect(model.isPro)
        #expect(model.purchaseNotice == nil)
        #expect(!model.isBuying)
        #expect(proModel(InMemoryProStore()).isPro)
    }

    @Test("PRO-3: a purchase waiting for approval says so, and unlocks Pro in the open app once approved")
    func pendingThenApproved() async throws {
        let store = InMemoryProStore(buying: .pending)
        let model = proModel(store)
        let following = Task { await model.keepUpToDate() }
        defer { following.cancel() }
        await model.buy()
        #expect(model.purchaseNotice == .waiting)
        #expect(!model.isPro)
        await store.set(.entitled)
        let deadline = ContinuousClock.now + .seconds(10)
        while !model.isPro {
            try #require(ContinuousClock.now < deadline, "The approval didn't reach the open app")
            await Task.yield()
        }
    }

    @Test("PRO-3: cancelling a purchase says nothing; one that fails says so; trying again clears it")
    func cancelledAndFailed() async {
        let cancelling = proModel(InMemoryProStore(buying: .cancelled))
        await cancelling.buy()
        #expect(cancelling.purchaseNotice == nil)
        #expect(!cancelling.isPro)

        let store = InMemoryProStore(buying: .failed)
        let failing = proModel(store)
        await failing.buy()
        #expect(failing.purchaseNotice == .failed)
        #expect(!failing.isPro)
        await store.set(buying: .cancelled)
        await failing.buy()
        #expect(failing.purchaseNotice == nil)
    }

    @Test("PRO-3: a failed purchase leaves Pro as it was")
    func failedKeepsPro() async {
        _ = await refreshed(InMemoryProStore(status: .entitled))
        let model = proModel(InMemoryProStore(buying: .failed))
        await model.buy()
        #expect(model.isPro)
    }

    @Test("PRO-3: the price is the store's; with no store, it says so, and trying again can find it")
    func offer() async {
        let model = proModel(InMemoryProStore(offer: ProOffer(displayPrice: "9,99 €")))
        await model.loadOffer()
        #expect(model.offer == ProOffer(displayPrice: "9,99 €"))
        #expect(!model.isOfferUnavailable)

        let unreachable = proModel(InMemoryProStore(offer: nil))
        await unreachable.loadOffer()
        #expect(unreachable.offer == nil)
        #expect(unreachable.isOfferUnavailable)
    }

    @Test("PRO-3: each opening of the Pro screen is one Paywall.shown, and none while analytics is off")
    func paywallShown() {
        let model = proModel(InMemoryProStore())
        #expect(!model.isShowingPaywall)
        model.showPaywall()
        #expect(model.isShowingPaywall)
        model.isShowingPaywall = false
        model.showPaywall()
        #expect(analytics.sent.filter { $0 == .paywallShown }.count == 2)

        let off = AnalyticsModel(analytics: analytics, defaults: defaults, clock: SystemClock())
        off.isOn = false
        ProModel(store: InMemoryProStore(), defaults: defaults, analytics: off).showPaywall()
        #expect(analytics.sent.filter { $0 == .paywallShown }.count == 2)
    }
}
