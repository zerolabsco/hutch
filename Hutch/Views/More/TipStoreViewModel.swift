import StoreKit

@Observable
final class TipStoreViewModel {
    var products: [Product] = []
    var isLoading = false
    var errorMessage: String?

    private let productIDs = [
        "net.cleberg.hutch.tip.small",
        "net.cleberg.hutch.tip.medium",
        "net.cleberg.hutch.tip.large"
    ]

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: productIDs)
            // Sort by price ascending to maintain small/medium/large order
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
