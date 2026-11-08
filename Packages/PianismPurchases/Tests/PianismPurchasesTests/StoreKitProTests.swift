import Foundation
import PianismCore
import Testing

@testable import PianismPurchases

struct StoreKitProTests {
    private func transaction(
        productID: String = ProProduct.id, isVerified: Bool = true, isRevoked: Bool = false
    ) -> ProTransaction {
        ProTransaction(productID: productID, isVerified: isVerified, isRevoked: isRevoked)
    }

    @Test("PRO-1: a verified purchase is Pro")
    func verifiedPurchase() {
        #expect(ProTransaction.status(from: [transaction()]) == .entitled)
    }

    @Test("PRO-1: no transactions says nothing, rather than taking Pro away")
    func noTransactions() {
        #expect(ProTransaction.status(from: []) == .unknown)
    }

    @Test("PRO-1: a refund is what takes Pro away")
    func refund() {
        #expect(ProTransaction.status(from: [transaction(isRevoked: true)]) == .revoked)
    }

    @Test("PRO-1: buying again after a refund is Pro, in either order")
    func boughtAgain() {
        let again = [transaction(isRevoked: true), transaction()]
        #expect(ProTransaction.status(from: again) == .entitled)
        #expect(ProTransaction.status(from: again.reversed()) == .entitled)
    }

    @Test("PRO-1: an unverified transaction neither grants Pro nor takes it away")
    func unverified() {
        #expect(ProTransaction.status(from: [transaction(isVerified: false)]) == .unknown)
        #expect(ProTransaction.status(from: [transaction(isVerified: false, isRevoked: true)]) == .unknown)
        let forgedRefund = transaction(isVerified: false, isRevoked: true)
        #expect(ProTransaction.status(from: [transaction(), forgedRefund]) == .entitled)
    }

    @Test("PRO-1: another product says nothing about Pro")
    func anotherProduct() {
        #expect(ProTransaction.status(from: [transaction(productID: "other")]) == .unknown)
        #expect(ProTransaction.status(from: [transaction(productID: "other", isRevoked: true)]) == .unknown)
    }

    /// The tests' StoreKit configuration describes the product the app asks for. App Store Connect can only be checked
    /// on a device.
    @Test("PRO-1: the tests' store sells the app's product, once, at $14.99")
    func configurationMatches() throws {
        struct Configuration: Decodable {
            struct Product: Decodable {
                let productID: String
                let type: String
                let displayPrice: String
            }
            let products: [Product]
        }
        let file = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AppUITests/Pianism.storekit")
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
        let product = try #require(configuration.products.first)
        #expect(configuration.products.count == 1)
        #expect(product.productID == ProProduct.id)
        #expect(product.type == "NonConsumable")
        #expect(product.displayPrice == "14.99")
    }
}
