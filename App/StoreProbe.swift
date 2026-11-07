import StoreKit
import SwiftUI

/// THROWAWAY: does real StoreKit work under xcodebuild, with no account?
struct StoreProbe: View {
    static let id = "com.edkarabinus.Pianism.pro"
    @State private var price = "none"
    @State private var entitled = "unknown"
    @State private var error = "none"
    @State private var product: Product?

    var body: some View {
        VStack(spacing: 20) {
            Text(verbatim: price).accessibilityIdentifier("probe.price")
            Text(verbatim: entitled).accessibilityIdentifier("probe.entitled")
            Text(verbatim: error).accessibilityIdentifier("probe.error")
            Button {
                Task { await buy() }
            } label: {
                Text(verbatim: "Buy")
            }
            .accessibilityIdentifier("probe.buy")
            Button {
                Task { await restore() }
            } label: {
                Text(verbatim: "Restore")
            }
            .accessibilityIdentifier("probe.restore")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .task {
            do {
                product = try await Product.products(for: [Self.id]).first
                price = product?.displayPrice ?? "no product"
            } catch {
                self.error = "products: \(error)"
            }
            await refresh()
        }
        .task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await refresh()
            }
        }
    }

    private func refresh() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.id,
                transaction.revocationDate == nil
            {
                found = true
            }
        }
        entitled = found ? "yes" : "no"
    }

    private func buy() async {
        do {
            let result = try await product?.purchase()
            if case .success(.verified(let transaction)) = result { await transaction.finish() }
            if case .pending = result { error = "pending" }
            if result == nil { error = "no product to buy" }
            await refresh()
        } catch {
            self.error = "buy: \(error)"
        }
    }

    private func restore() async {
        await refresh()
    }
}
