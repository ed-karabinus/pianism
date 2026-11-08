/// A store with no App Store behind it, for tests and previews, whose answers are set up front.
public actor InMemoryProStore: ProStore {
    public nonisolated let changes: AsyncStream<Void>

    private let continuation: AsyncStream<Void>.Continuation
    private var current: ProStatus
    private let restoring: RestoreOutcome
    private let restoreFinds: Bool
    private let offering: ProOffer?
    private var buying: PurchaseOutcome

    /// - Parameters:
    ///   - restoring: How a restore ends.
    ///   - restoreFinds: Whether one that finishes finds a purchase.
    ///   - offer: What Pro costs, or `nil` for a store that can't be reached.
    ///   - buying: How a purchase ends.
    public init(
        status: ProStatus = .unknown, restoring: RestoreOutcome = .finished, restoreFinds: Bool = false,
        offer: ProOffer? = ProOffer(displayPrice: "$14.99"), buying: PurchaseOutcome = .purchased
    ) {
        (changes, continuation) = AsyncStream<Void>.makeStream()
        current = status
        self.restoring = restoring
        self.restoreFinds = restoreFinds
        offering = offer
        self.buying = buying
    }

    public func status() -> ProStatus { current }

    public func restore() -> RestoreOutcome {
        if restoring == .finished, restoreFinds { current = .entitled }
        return restoring
    }

    public func offer() -> ProOffer? { offering }

    public func purchase() -> PurchaseOutcome {
        if buying == .purchased { current = .entitled }
        return buying
    }

    /// Changes how the next purchase ends.
    public func set(buying outcome: PurchaseOutcome) {
        buying = outcome
    }

    /// Changes the status and says so, as a refund or a purchase elsewhere would.
    public func set(_ status: ProStatus) {
        current = status
        continuation.yield()
    }
}
