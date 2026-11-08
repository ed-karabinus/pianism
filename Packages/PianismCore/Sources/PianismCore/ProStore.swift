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

/// Where Pro's status comes from: StoreKit in the app, and ``InMemoryProStore`` in tests and previews.
public protocol ProStore: Sendable {
    func status() async -> ProStatus
    /// Asks the store for this account's purchases, which can ask the person to sign in.
    func restore() async -> RestoreOutcome
    /// Fires when the status may have changed, as when a purchase on another device or a refund arrives.
    var changes: AsyncStream<Void> { get }
}
