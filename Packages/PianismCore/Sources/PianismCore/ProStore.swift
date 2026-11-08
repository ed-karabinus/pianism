/// What the App Store knows about the one-time Pro purchase, on or offline (PRO-1, ADR 0012).
public enum ProProduct {
    /// Permanent: App Store Connect can't change it once saved, or reuse it after a deletion.
    public static let id = "com.edkarabinus.Pianism.pro"
}

/// What the store says about Pro right now.
public enum ProStatus: Sendable, Hashable {
    case entitled
    /// Bought, then refunded. The only answer that takes Pro away.
    case revoked
    /// Nothing says either way, as when it was never bought, or when the store's answer comes back empty.
    case unknown
}

/// How a request to restore purchases ended.
public enum RestoreOutcome: Sendable, Hashable {
    case finished
    case cancelled
    case failed
}

/// What the store asks for Pro, as it shows it: its price in the person's own currency (PRO-3).
public struct ProOffer: Sendable, Hashable {
    public let displayPrice: String

    public init(displayPrice: String) {
        self.displayPrice = displayPrice
    }
}

/// How a purchase of Pro ended.
public enum PurchaseOutcome: Sendable, Hashable {
    case purchased
    /// Waiting for someone else's approval, as with Ask to Buy. ``ProStore/changes`` fires if it comes.
    case pending
    case cancelled
    case failed
}

/// Where Pro's status comes from: StoreKit in the app, and ``InMemoryProStore`` in tests and previews.
public protocol ProStore: Sendable {
    func status() async -> ProStatus
    /// Asks the store for this account's purchases, which can ask the person to sign in.
    func restore() async -> RestoreOutcome
    /// What Pro costs, or `nil` if the store can't be reached.
    func offer() async -> ProOffer?
    /// Buys Pro. Only a verified purchase comes back as purchased.
    func purchase() async -> PurchaseOutcome
    /// Fires when the status may have changed, as when a purchase on another device or a refund arrives.
    var changes: AsyncStream<Void> { get }
}
