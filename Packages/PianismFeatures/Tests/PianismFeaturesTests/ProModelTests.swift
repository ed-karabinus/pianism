import Foundation
import PianismCore
import Testing

@testable import PianismFeatures

@MainActor
struct ProModelTests {
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "ProModelTests.\(UUID().uuidString)"))
    }

    private func refreshed(_ store: InMemoryProStore) async -> ProModel {
        let model = ProModel(store: store, defaults: defaults)
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
        #expect(ProModel(store: InMemoryProStore(), defaults: defaults).isPro)
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

    @Test("PRO-1: a change in the store reaches an open app, both ways", .timeLimit(.minutes(1)))
    func followsTheStore() async {
        let store = InMemoryProStore()
        let model = ProModel(store: store, defaults: defaults)
        let following = Task { await model.keepUpToDate() }
        defer { following.cancel() }
        await store.set(.entitled)
        while !model.isPro { await Task.yield() }
        await store.set(.revoked)
        while model.isPro { await Task.yield() }
    }

    @Test("PRO-1: a restore that finds the purchase unlocks Pro and says nothing else")
    func restoreFinds() async {
        let model = ProModel(store: InMemoryProStore(restoreFinds: true), defaults: defaults)
        await model.restore()
        #expect(model.isPro)
        #expect(model.restoreNotice == nil)
        #expect(!model.isRestoring)
    }

    @Test("PRO-1: a restore that finds nothing says so")
    func restoreFindsNothing() async {
        let model = ProModel(store: InMemoryProStore(), defaults: defaults)
        await model.restore()
        #expect(!model.isPro)
        #expect(model.restoreNotice == .noPurchase)
    }

    @Test("PRO-1: a restore that fails says so, and leaves Pro as it was")
    func restoreFails() async {
        _ = await refreshed(InMemoryProStore(status: .entitled))
        let model = ProModel(store: InMemoryProStore(status: .revoked, restoring: .failed), defaults: defaults)
        await model.restore()
        #expect(model.restoreNotice == .unreachable)
        #expect(model.isPro)
    }

    @Test("PRO-1: cancelling a restore says nothing")
    func restoreCancelled() async {
        let model = ProModel(store: InMemoryProStore(restoring: .cancelled), defaults: defaults)
        await model.restore()
        #expect(model.restoreNotice == nil)
        #expect(!model.isPro)
    }

    @Test("PRO-1: trying again clears what the last restore said")
    func aNewRestoreClearsTheNotice() async {
        let store = InMemoryProStore()
        let model = ProModel(store: store, defaults: defaults)
        await model.restore()
        #expect(model.restoreNotice == .noPurchase)
        await store.set(.entitled)
        await model.restore()
        #expect(model.restoreNotice == nil)
    }

    @Test("PRO-1: a restore that finds a refunded purchase turns Pro off and says nothing's there")
    func restoreFindsARefund() async {
        _ = await refreshed(InMemoryProStore(status: .entitled))
        let model = ProModel(store: InMemoryProStore(status: .revoked), defaults: defaults)
        await model.restore()
        #expect(!model.isPro)
        #expect(model.restoreNotice == .noPurchase)
    }
}
