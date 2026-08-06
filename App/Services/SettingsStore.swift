import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    static let googleVisionHardMonthlyLimit = 1_000

    private let defaults: UserDefaults

    var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    var maxDetectedItems: Int {
        didSet {
            let clamped = min(12, max(1, maxDetectedItems))
            if maxDetectedItems != clamped {
                maxDetectedItems = clamped
                return
            }
            defaults.set(maxDetectedItems, forKey: Keys.maxDetectedItems)
        }
    }

    var liveAutoCaptureEnabled: Bool {
        didSet {
            defaults.set(liveAutoCaptureEnabled, forKey: Keys.liveAutoCaptureEnabled)
        }
    }

    var liveScreenAutoCaptureEnabled: Bool {
        didSet {
            defaults.set(
                liveScreenAutoCaptureEnabled,
                forKey: Keys.liveScreenAutoCaptureEnabled
            )
        }
    }

    var productSearchPipeline: ProductSearchPipeline {
        didSet { defaults.set(productSearchPipeline.rawValue, forKey: Keys.productSearchPipeline) }
    }

    var imageSearchProvider: ImageSearchProvider {
        didSet { defaults.set(imageSearchProvider.rawValue, forKey: Keys.imageSearchProvider) }
    }

    var productSearchesPerPiece: Int {
        didSet {
            let clamped = min(5, max(1, productSearchesPerPiece))
            if productSearchesPerPiece != clamped { productSearchesPerPiece = clamped; return }
            defaults.set(productSearchesPerPiece, forKey: Keys.productSearchesPerPiece)
        }
    }

    var productResultLimit: Int {
        didSet {
            let clamped = min(20, max(1, productResultLimit))
            if productResultLimit != clamped { productResultLimit = clamped; return }
            defaults.set(productResultLimit, forKey: Keys.productResultLimit)
        }
    }

    var searchAPIMonthlyLimit: Int {
        didSet { clampAndStore(&searchAPIMonthlyLimit, key: Keys.searchAPIMonthlyLimit) }
    }

    var serpAPIMonthlyLimit: Int {
        didSet { clampAndStore(&serpAPIMonthlyLimit, key: Keys.serpAPIMonthlyLimit) }
    }

    var brightDataMonthlyLimit: Int {
        didSet { clampAndStore(&brightDataMonthlyLimit, key: Keys.brightDataMonthlyLimit) }
    }

    var lykdatMonthlyLimit: Int {
        didSet { clampAndStore(&lykdatMonthlyLimit, key: Keys.lykdatMonthlyLimit) }
    }

    var googleVisionMonthlyLimit: Int {
        didSet {
            let clamped = min(Self.googleVisionHardMonthlyLimit, max(1, googleVisionMonthlyLimit))
            if googleVisionMonthlyLimit != clamped { googleVisionMonthlyLimit = clamped; return }
            defaults.set(googleVisionMonthlyLimit, forKey: Keys.googleVisionMonthlyLimit)
        }
    }

    var serperMonthlyLimit: Int {
        didSet { clampAndStore(&serperMonthlyLimit, key: Keys.serperMonthlyLimit) }
    }

    var fireworksMonthlyBudgetUSD: Double {
        didSet {
            let clamped = min(500, max(1, fireworksMonthlyBudgetUSD))
            if fireworksMonthlyBudgetUSD != clamped { fireworksMonthlyBudgetUSD = clamped; return }
            defaults.set(fireworksMonthlyBudgetUSD, forKey: Keys.fireworksMonthlyBudgetUSD)
        }
    }

    var fireworksModelID: String {
        didSet { defaults.set(fireworksModelID, forKey: Keys.fireworksModelID) }
    }

    var brightDataZone: String {
        didSet { defaults.set(brightDataZone, forKey: Keys.brightDataZone) }
    }

    var publicImageURL: String {
        didSet { defaults.set(publicImageURL, forKey: Keys.publicImageURL) }
    }

    var searchCountry: String {
        didSet { defaults.set(searchCountry, forKey: Keys.searchCountry) }
    }

    var searchLanguage: String {
        didSet { defaults.set(searchLanguage, forKey: Keys.searchLanguage) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        let storedMax = defaults.integer(forKey: Keys.maxDetectedItems)
        maxDetectedItems = storedMax == 0 ? 5 : min(12, max(1, storedMax))
        if defaults.object(forKey: Keys.liveAutoCaptureEnabled) == nil {
            liveAutoCaptureEnabled = true
        } else {
            liveAutoCaptureEnabled = defaults.bool(
                forKey: Keys.liveAutoCaptureEnabled
            )
        }
        if defaults.object(forKey: Keys.liveScreenAutoCaptureEnabled) == nil {
            liveScreenAutoCaptureEnabled = true
        } else {
            liveScreenAutoCaptureEnabled = defaults.bool(
                forKey: Keys.liveScreenAutoCaptureEnabled
            )
        }
        // Exact product search is visual by default. Fireworks + Serper is
        // reserved for user-initiated AI/refinement searches.
        productSearchPipeline = .directImage
        imageSearchProvider = defaults.string(forKey: Keys.imageSearchProvider)
            .flatMap(ImageSearchProvider.init(rawValue:)) ?? .lykdat
        productSearchesPerPiece = Self.storedInt(defaults, key: Keys.productSearchesPerPiece, default: 1, range: 1...5)
        productResultLimit = Self.storedInt(defaults, key: Keys.productResultLimit, default: 6, range: 1...20)
        searchAPIMonthlyLimit = Self.storedInt(defaults, key: Keys.searchAPIMonthlyLimit, default: 100, range: 1...100_000)
        serpAPIMonthlyLimit = Self.storedInt(defaults, key: Keys.serpAPIMonthlyLimit, default: 250, range: 1...100_000)
        brightDataMonthlyLimit = Self.storedInt(defaults, key: Keys.brightDataMonthlyLimit, default: 5_000, range: 1...100_000)
        lykdatMonthlyLimit = Self.storedInt(defaults, key: Keys.lykdatMonthlyLimit, default: 500, range: 1...100_000)
        googleVisionMonthlyLimit = Self.storedInt(
            defaults,
            key: Keys.googleVisionMonthlyLimit,
            default: Self.googleVisionHardMonthlyLimit,
            range: 1...Self.googleVisionHardMonthlyLimit
        )
        serperMonthlyLimit = Self.storedInt(defaults, key: Keys.serperMonthlyLimit, default: 2_500, range: 1...100_000)
        let storedBudget = defaults.double(forKey: Keys.fireworksMonthlyBudgetUSD)
        fireworksMonthlyBudgetUSD = storedBudget == 0 ? 50 : min(500, max(1, storedBudget))
        fireworksModelID = defaults.string(forKey: Keys.fireworksModelID)
            ?? "accounts/fireworks/models/qwen3p7-plus"
        brightDataZone = defaults.string(forKey: Keys.brightDataZone) ?? ""
        publicImageURL = defaults.string(forKey: Keys.publicImageURL) ?? ""
        searchCountry = defaults.string(forKey: Keys.searchCountry) ?? "us"
        searchLanguage = defaults.string(forKey: Keys.searchLanguage) ?? "en"
    }

    func monthlyRequestLimits(for pipeline: ProductSearchPipeline) -> [String: Int] {
        switch pipeline {
        case .privateAIText:
            ["fireworks": 100_000, "serper": serperMonthlyLimit]
        case .directImage:
            [
                "searchapi": searchAPIMonthlyLimit,
                "serpapi": serpAPIMonthlyLimit,
                "brightdata": brightDataMonthlyLimit,
                "lykdat": lykdatMonthlyLimit,
                "googlevision": min(Self.googleVisionHardMonthlyLimit, googleVisionMonthlyLimit),
            ]
        }
    }

    private func clampAndStore(_ value: inout Int, key: String) {
        let clamped = min(100_000, max(1, value))
        if value != clamped {
            value = clamped
            return
        }
        defaults.set(value, forKey: key)
    }

    private static func storedInt(
        _ defaults: UserDefaults,
        key: String,
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        let value = defaults.integer(forKey: key)
        return min(range.upperBound, max(range.lowerBound, value == 0 ? defaultValue : value))
    }

    private enum Keys {
        static let notificationsEnabled = "stylezam.notifications-enabled"
        static let maxDetectedItems = "stylezam.max-detected-items"
        static let liveAutoCaptureEnabled = "stylezam.live-auto-capture-enabled"
        static let liveScreenAutoCaptureEnabled = "stylezam.live-screen-auto-capture-enabled"
        static let productSearchPipeline = "stylezam.search.pipeline"
        static let imageSearchProvider = "stylezam.search.image-provider"
        static let productSearchesPerPiece = "stylezam.search.per-piece-limit"
        static let productResultLimit = "stylezam.search.result-limit"
        static let searchAPIMonthlyLimit = "stylezam.search.searchapi-monthly-limit"
        static let serpAPIMonthlyLimit = "stylezam.search.serpapi-monthly-limit"
        static let brightDataMonthlyLimit = "stylezam.search.brightdata-monthly-limit"
        static let lykdatMonthlyLimit = "stylezam.search.lykdat-monthly-limit"
        static let googleVisionMonthlyLimit = "stylezam.search.google-vision-monthly-limit"
        static let serperMonthlyLimit = "stylezam.search.serper-monthly-limit"
        static let fireworksMonthlyBudgetUSD = "stylezam.search.fireworks-monthly-budget-usd"
        static let fireworksModelID = "stylezam.search.fireworks-model-id"
        static let brightDataZone = "stylezam.search.brightdata-zone"
        static let publicImageURL = "stylezam.search.public-image-url"
        static let searchCountry = "stylezam.search.country"
        static let searchLanguage = "stylezam.search.language"
    }
}
