import Foundation
import PianismCore
import StoreKit

/// Pro's status from StoreKit 2, which keeps verified purchases on the device, so it works offline (PRO-1, ADR 0012).
///
/// Create it at launch: it starts listening then, as a purchase can finish, or a refund arrive, at any time.
public final class StoreKitPro: ProStore {
    public let changes: AsyncStream<Void>
    private let listening: Task<Void, Never>

    public init() {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        self.changes = changes
        listening = Task.detached {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                continuation.yield()
            }
        }
    }

    deinit { listening.cancel() }

    public func status() async -> ProStatus {
        var seen: [ProTransaction] = []
        // Both, as a purchase that's missing from one must still count: a refund is all that may take Pro away.
        for await result in Transaction.currentEntitlements { seen.append(ProTransaction(result)) }
        for await result in Transaction.all { seen.append(ProTransaction(result)) }
        return ProTransaction.status(from: seen)
    }

    public func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
            return .finished
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed
        }
    }

    public func offer() async -> ProOffer? {
        guard let product = await product() else { return nil }
        return ProOffer(displayPrice: product.displayPrice)
    }

    public func purchase() async -> PurchaseOutcome {
        guard let product = await product() else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(let result):
                // Like any unverified transaction, one StoreKit can't verify doesn't unlock Pro (ADR 0012).
                guard case .verified(let transaction) = result else { return .failed }
                await transaction.finish()
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed
        }
    }

    private func product() async -> Product? {
        try? await Product.products(for: [ProProduct.id]).first
    }
}

/// What ``ProStatus`` depends on in a transaction, apart from StoreKit, whose results a test can't make.
struct ProTransaction: Equatable {
    let productID: String
    let isVerified: Bool
    let isRevoked: Bool

    /// One good purchase is Pro, even after an earlier refund. Only a verified transaction says anything, so a forged
    /// one can neither grant Pro nor take it away.
    static func status(from transactions: [ProTransaction]) -> ProStatus {
        let verified = transactions.filter { $0.isVerified && $0.productID == ProProduct.id }
        if verified.contains(where: { !$0.isRevoked }) { return .entitled }
        return verified.isEmpty ? .unknown : .revoked
    }
}

extension ProTransaction {
    init(_ result: VerificationResult<Transaction>) {
        let transaction = result.unsafePayloadValue
        var isVerified = false
        if case .verified = result { isVerified = true }
        self.init(
            productID: transaction.productID, isVerified: isVerified, isRevoked: transaction.revocationDate != nil)
    }
}
