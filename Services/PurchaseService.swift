import Combine
import StoreKit

@MainActor
final class PurchaseService: ObservableObject {

    nonisolated static let lifetimeProductID = "com.flashcatch.lifetime"

    @Published private(set) var isLifetimePurchased = false
    @Published private(set) var product: Product?
    @Published private(set) var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
    }

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchaseStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.lifetimeProductID])
            product = products.first
        } catch {}
    }

    // MARK: - Purchase

    func purchaseLifetime() async {
        guard let product = product else {
            purchaseState = .failed("商品信息加载失败，请重试")
            return
        }

        purchaseState = .purchasing

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isLifetimePurchased = true
                purchaseState = .purchased

            case .userCancelled:
                purchaseState = .idle

            case .pending:
                purchaseState = .idle

            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed("购买失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        purchaseState = .purchasing
        try? await AppStore.sync()
        await updatePurchaseStatus()

        if isLifetimePurchased {
            purchaseState = .purchased
        } else {
            purchaseState = .failed("未找到可恢复的购买记录")
        }
    }

    // MARK: - Check Status

    func updatePurchaseStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.lifetimeProductID {
                isLifetimePurchased = true
                return
            }
        }
        isLifetimePurchased = false
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if transaction.productID == PurchaseService.lifetimeProductID {
                        self?.isLifetimePurchased = true
                        self?.purchaseState = .purchased
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
}

enum PurchaseError: LocalizedError {
    case verificationFailed
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "交易验证失败"
        case .productNotFound:
            return "未找到商品信息"
        }
    }
}
