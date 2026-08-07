import Foundation
import Observation
import StoreKit

enum SubscriptionBillingPeriod: String, CaseIterable, Identifiable, Sendable {
    case monthly
    case annual

    var id: String { rawValue }
    var title: String { self == .monthly ? "Monthly" : "Annual" }
}
@MainActor
@Observable
final class SubscriptionStore {
    private(set) var products: [String: Product] = [:]
    private(set) var entitledPlan: AccountPlan = .free
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    static let productIDs: [AccountPlan: [SubscriptionBillingPeriod: String]] = [
        .plus: [
            .monthly: "com.stylezam.app.plus.monthly",
            .annual: "com.stylezam.app.plus.annual",
        ],
        .pro: [
            .monthly: "com.stylezam.app.pro.monthly",
            .annual: "com.stylezam.app.pro.annual",
        ],
    ]

    var hasLoadedProducts: Bool { !products.isEmpty }

    func start() async {
        await loadProducts()
        await refreshEntitlements()
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case let .verified(transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    func product(for plan: AccountPlan, period: SubscriptionBillingPeriod) -> Product? {
        Self.productIDs[plan]?[period].flatMap { products[$0] }
    }

    func price(for plan: AccountPlan, period: SubscriptionBillingPeriod) -> String {
        if plan == .free { return "$0" }
        if plan == .developer { return "Internal" }
        return product(for: plan, period: period)?.displayPrice ?? "Unavailable"
    }

    func annualSavings(for plan: AccountPlan) -> Int? {
        guard let monthly = product(for: plan, period: .monthly),
              let annual = product(for: plan, period: .annual)
        else { return nil }
        let fullYear = monthly.price * Decimal(12)
        guard fullYear > 0, annual.price < fullYear else { return nil }
        let percent = ((fullYear - annual.price) / fullYear) * Decimal(100)
        return NSDecimalNumber(decimal: percent).intValue
    }

    @discardableResult
    func purchase(plan: AccountPlan, period: SubscriptionBillingPeriod) async -> Bool {
        guard let product = product(for: plan, period: period) else {
            errorMessage = "This subscription is not available from the App Store yet."
            return false
        }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(result):
                let transaction = try verified(result)
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .pending:
                errorMessage = "The App Store purchase is waiting for approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                errorMessage = "The App Store could not complete this purchase."
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let ids = Self.productIDs.values.flatMap { $0.values }
            products = Dictionary(uniqueKeysWithValues: try await Product.products(for: ids).map {
                ($0.id, $0)
            })
        } catch {
            products = [:]
            errorMessage = "Stylezam could not load App Store plans. \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var best: AccountPlan = .free
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true,
                  let plan = Self.plan(for: transaction.productID)
            else { continue }
            if plan.rank > best.rank { best = plan }
        }
        entitledPlan = best
    }

    private static func plan(for productID: String) -> AccountPlan? {
        productIDs.first { $0.value.values.contains(productID) }?.key
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(value): value
        case .unverified: throw SubscriptionError.failedVerification
        }
    }
}

private extension AccountPlan {
    var rank: Int {
        switch self {
        case .free: 0
        case .plus: 1
        case .pro: 2
        case .developer: 3
        }
    }
}

private enum SubscriptionError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "The App Store transaction could not be verified on this device."
    }
}
