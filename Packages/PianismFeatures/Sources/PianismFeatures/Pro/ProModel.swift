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

    enum RestoreNotice {
        case noPurchase, unreachable

        var message: LocalizedStringResource {
            switch self {
            case .noPurchase: LocalizedStringResource("No purchase found.", bundle: .module)
            case .unreachable: LocalizedStringResource("Couldn't reach the App Store. Try again.", bundle: .module)
            }
        }
    }

    @ObservationIgnored private let store: any ProStore
    @ObservationIgnored private let defaults: UserDefaults

    public init(store: any ProStore, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
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
}
