import Foundation
import PianismCore

/// Whether Pro is unlocked (PRO-1, ADR 0012). Kept on this device, so someone who paid never sees it disappear: only a
/// refund turns it off, and an answer that says nothing leaves it as it was.
@MainActor
@Observable
public final class ProModel {
    public private(set) var isPro: Bool {
        didSet { defaults.set(isPro, forKey: SettingsKey.proUnlocked) }
    }
    /// What the last restore has to say, if it didn't unlock Pro.
    private(set) var restoreNotice: RestoreNotice?
    private(set) var isRestoring = false
    /// Whether the Pro screen is open. Only a tap opens it, never the app by itself (PRO-3).
    var isShowingPaywall = false
    /// What Pro costs, once the store has said.
    private(set) var offer: ProOffer?
    /// Whether the store couldn't be reached for the price, which is never made up.
    private(set) var isOfferUnavailable = false
    private(set) var isBuying = false
    /// What the last purchase has to say, if it didn't unlock Pro.
    private(set) var purchaseNotice: PurchaseNotice?

    enum RestoreNotice {
        case noPurchase, unreachable

        var message: LocalizedStringResource {
            switch self {
            case .noPurchase: LocalizedStringResource("No purchase found.", bundle: .module)
            case .unreachable: LocalizedStringResource("Couldn't reach the App Store. Try again.", bundle: .module)
            }
        }
    }

    enum PurchaseNotice {
        case waiting, failed

        var message: LocalizedStringResource {
            switch self {
            case .waiting:
                LocalizedStringResource("Waiting for approval. Pro unlocks once it's approved.", bundle: .module)
            case .failed: LocalizedStringResource("The purchase didn't go through. Try again.", bundle: .module)
            }
        }
    }

    @ObservationIgnored private let store: any ProStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let analytics: AnalyticsModel

    public init(store: any ProStore, defaults: UserDefaults, analytics: AnalyticsModel) {
        self.store = store
        self.defaults = defaults
        self.analytics = analytics
        isPro = defaults.bool(forKey: SettingsKey.proUnlocked)
    }

    /// Follows the store for as long as the app is open.
    public func keepUpToDate() async {
        await refresh()
        for await _ in store.changes { await refresh() }
    }

    func refresh() async {
        apply(await store.status())
    }

    /// Asks the store for this account's purchases, from Settings. Cancelling, as at a sign-in, says nothing.
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        restoreNotice = nil
        switch await store.restore() {
        case .cancelled:
            break
        case .failed:
            show(.unreachable)
        case .finished:
            let status = await store.status()
            apply(status)
            if status == .entitled {
                // The button VoiceOver was on goes, so it would otherwise say nothing.
                PracticeModel.tellVoiceOver(String(localized: "Pro is unlocked", bundle: .module))
            } else {
                show(.noPurchase)
            }
        }
    }

    /// Opens the Pro screen, from a tap on Settings' row or on something Pro.
    func showPaywall() {
        isShowingPaywall = true
        analytics.paywallShown()
    }

    /// Asks the store what Pro costs, when the Pro screen opens and when it's asked to try again.
    func loadOffer() async {
        isOfferUnavailable = false
        offer = await store.offer()
        isOfferUnavailable = offer == nil
    }

    /// Buys Pro. Cancelling, as at the App Store's sheet, says nothing.
    func buy() async {
        isBuying = true
        defer { isBuying = false }
        purchaseNotice = nil
        switch await store.purchase() {
        case .purchased:
            // A verified purchase of Pro, which is all a refund-free entitlement needs.
            isPro = true
            PracticeModel.tellVoiceOver(String(localized: "Pro is unlocked", bundle: .module))
        case .pending:
            show(.waiting)
        case .cancelled:
            break
        case .failed:
            show(.failed)
        }
    }

    private func apply(_ status: ProStatus) {
        switch status {
        case .entitled: isPro = true
        case .revoked: isPro = false
        case .unknown: break
        }
    }

    private func show(_ notice: RestoreNotice) {
        restoreNotice = notice
        PracticeModel.tellVoiceOver(String(localized: notice.message))
    }

    private func show(_ notice: PurchaseNotice) {
        purchaseNotice = notice
        PracticeModel.tellVoiceOver(String(localized: notice.message))
    }
}
