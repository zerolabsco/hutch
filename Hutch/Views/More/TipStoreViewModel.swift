import StoreKit

@Observable
final class TipStoreViewModel {
    enum TipProduct: String, CaseIterable {
        case small
        case medium
        case large

        var id: String {
            "net.cleberg.hutch.tip.\(rawValue)"
        }

        var displayName: String {
            switch self {
            case .small:
                "Small Tip"
            case .medium:
                "Medium Tip"
            case .large:
                "Large Tip"
            }
        }
    }

    static let productIDs = TipProduct.allCases.map(\.id)

    var products: [Product] = []
    var isLoading = false
    var isRestoringPurchases = false
    var purchasingProductID: String?
    var errorMessage: String?
    var statusMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task.detached(priority: .background) {
            for await verification in Transaction.updates {
                guard case .verified(let transaction) = verification else { continue }
                await transaction.finish()
            }
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    @MainActor
    func loadProducts() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await Product.products(for: Self.productIDs)
            let productsByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            let orderedProducts = TipProduct.allCases.compactMap { productsByID[$0.id] }
            let missingProducts = TipProduct.allCases.filter { productsByID[$0.id] == nil }

            products = orderedProducts

            if !missingProducts.isEmpty {
                let missingNames = missingProducts.map(\.displayName).joined(separator: ", ")
                errorMessage = "Missing products from the App Store response: \(missingNames). Confirm the product identifiers match App Store Connect exactly and that each item is approved or available in sandbox."
            }
        } catch {
            products = []
            errorMessage = "Couldn't load tips from the App Store. \(error.localizedDescription)"
        }
    }

    @MainActor
    func purchase(_ product: Product) async {
        guard purchasingProductID == nil else { return }

        purchasingProductID = product.id
        errorMessage = nil
        statusMessage = nil
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    statusMessage = "Purchase completed successfully."
                case .unverified(_, let error):
                    errorMessage = "The App Store returned an unverified transaction. \(error.localizedDescription)"
                }

            case .pending:
                statusMessage = "Purchase is pending approval."

            case .userCancelled:
                break

            @unknown default:
                errorMessage = "The App Store returned an unknown purchase result."
            }
        } catch {
            errorMessage = "Purchase failed. \(error.localizedDescription)"
        }
    }

    @MainActor
    func restorePurchases() async {
        guard !isRestoringPurchases else { return }

        isRestoringPurchases = true
        errorMessage = nil
        defer { isRestoringPurchases = false }

        do {
            try await AppStore.sync()
            statusMessage = "Purchase history synced with the App Store."
            await loadProducts()
        } catch {
            errorMessage = "Couldn't sync purchases. \(error.localizedDescription)"
        }
    }

    @MainActor
    func clearStatusMessage() {
        statusMessage = nil
    }

    func isPurchasing(_ product: Product) -> Bool {
        purchasingProductID == product.id
    }
}
