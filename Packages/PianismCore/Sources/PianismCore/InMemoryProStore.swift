/// A store with no App Store behind it, for tests and previews, whose answers are set up front.
public actor InMemoryProStore: ProStore {
    public nonisolated let changes: AsyncStream<Void>

    private let continuation: AsyncStream<Void>.Continuation
    private var current: ProStatus
    private let restoring: RestoreOutcome
    private let restoreFinds: Bool

    /// - Parameters:
    ///   - restoring: How a restore ends.
    ///   - restoreFinds: Whether one that finishes finds a purchase.
    public init(status: ProStatus = .unknown, restoring: RestoreOutcome = .finished, restoreFinds: Bool = false) {
        (changes, continuation) = AsyncStream<Void>.makeStream()
        current = status
        self.restoring = restoring
        self.restoreFinds = restoreFinds
    }

    public func status() -> ProStatus { current }

    public func restore() -> RestoreOutcome {
        if restoring == .finished, restoreFinds { current = .entitled }
        return restoring
    }

    /// Changes the status and says so, as a refund or a purchase elsewhere would.
    public func set(_ status: ProStatus) {
        current = status
        continuation.yield()
    }
}
