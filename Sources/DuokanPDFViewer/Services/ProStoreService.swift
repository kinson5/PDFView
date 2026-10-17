import Foundation
import StoreKit
import SwiftUI

/// Core StoreKit 2 manager handling PDFview Pro Lifetime in-app purchase and entitlement verification
@MainActor
public final class ProStoreService: ObservableObject {
    public static let shared = ProStoreService()

    /// Product ID for lifetime purchase
    public static let proLifetimeProductID = "com.duokan.pdfview.pro.lifetime"

    /// Cache key for offline entitlement resilience
    private static let cachedProKey = "com.duokan.pdfview.is_pro_unlocked_cached"

    @Published public private(set) var isProUnlocked: Bool = false
    @Published public private(set) var proProduct: Product? = nil
    @Published public private(set) var isLoadingProducts: Bool = false
    @Published public private(set) var isPurchasing: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var purchaseSuccess: Bool = false

    private var updateListenerTask: Task<Void, Never>? = nil

    private init() {
        // 1. Immediately read offline cache for instantaneous UI response
        self.isProUnlocked = UserDefaults.standard.bool(forKey: Self.cachedProKey)

        // 2. Start background transaction update listener
        updateListenerTask = listenForTransactions()

        // 3. Check actual entitlements & load products asynchronously
        Task {
            await checkCurrentEntitlements()
            await loadProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in StoreKit.Transaction.updates {
                do {
                    guard let self = self else { break }
                    let transaction = try self.checkVerified(result)
                    await self.handle(transaction: transaction)
                    await transaction.finish()
                } catch {
                    print("[ProStore] Transaction update verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Load Products

    public func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: [Self.proLifetimeProductID])
            self.proProduct = products.first
        } catch {
            print("[ProStore] Failed to fetch products: \(error)")
        }
    }

    // MARK: - Entitlements Check

    public func checkCurrentEntitlements() async {
        var hasActivePro = false

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proLifetimeProductID {
                if transaction.revocationDate == nil {
                    hasActivePro = true
                    break
                }
            }
        }

        updateProStatus(hasActivePro)
    }

    // MARK: - Purchase Flow

    @discardableResult
    public func purchasePro() async -> Bool {
        guard let product = proProduct else {
            await loadProducts()
            guard let reloadedProduct = proProduct else {
                self.errorMessage = "未能连接到 App Store 商品信息，请检查网络后重试"
                return false
            }
            return await doPurchase(product: reloadedProduct)
        }
        return await doPurchase(product: product)
    }

    private func doPurchase(product: Product) async -> Bool {
        isPurchasing = true
        errorMessage = nil
        purchaseSuccess = false
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handle(transaction: transaction)
                await transaction.finish()
                self.purchaseSuccess = true
                PlatformHaptics.notificationSuccess()
                return true

            case .userCancelled:
                return false

            case .pending:
                self.errorMessage = "购买正在等待家长或管理员审批"
                return false

            @unknown default:
                return false
            }
        } catch {
            self.errorMessage = "购买失败: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Restore Purchases

    public func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()

            if isProUnlocked {
                PlatformHaptics.notificationSuccess()
                self.purchaseSuccess = true
            } else {
                self.errorMessage = "未在当前 Apple ID 下找到已购的 Pro 订单"
            }
        } catch {
            self.errorMessage = "恢复购买失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Helper Methods

    private func handle(transaction: StoreKit.Transaction) async {
        if transaction.productID == Self.proLifetimeProductID {
            if transaction.revocationDate == nil {
                updateProStatus(true)
            } else {
                updateProStatus(false)
            }
        }
    }

    private func updateProStatus(_ unlocked: Bool) {
        self.isProUnlocked = unlocked
        UserDefaults.standard.set(unlocked, forKey: Self.cachedProKey)
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    /// Formatted display price with fallback
    public var formattedPriceText: String {
        if let product = proProduct {
            return "\(product.displayPrice) 永久买断"
        }
        return "¥28.00 永久买断"
    }
}
