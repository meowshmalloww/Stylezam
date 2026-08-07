import Foundation
import XCTest
@testable import Stylezam

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testMaximumDetectedItemsClampsWithoutRecursiveSetter() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        store.maxDetectedItems = 8
        XCTAssertEqual(store.maxDetectedItems, 8)

        store.maxDetectedItems = 99
        XCTAssertEqual(store.maxDetectedItems, 12)

        store.maxDetectedItems = -4
        XCTAssertEqual(store.maxDetectedItems, 1)
    }

    func testSettingsPersistIntoInjectedDefaults() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        store.maxDetectedItems = 7

        XCTAssertEqual(SettingsStore(defaults: defaults).maxDetectedItems, 7)
    }

    func testVisualAndKeywordProvidersRotateAfterEverySearch() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StylezamSearchUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let usage = SearchUsageStore(rootURL: root)
        let visualProviders: [ImageSearchProvider] = [.lykdat, .googleVision, .searchAPI]
        let keywordProviders: [KeywordSearchProvider] = [.serper, .searchAPI, .serpAPI, .brightData]
        let limits = [
            "fireworks": 100,
            "serper": 100,
            "searchapi": 100,
            "serpapi": 100,
            "brightdata": 100,
            "lykdat": 100,
            "googlevision": 100,
        ]

        XCTAssertEqual(
            usage.routedImageProvider(
                from: [.serpAPI, .lykdat],
                maximumConsecutiveRequests: 1
            ),
            .serpAPI,
            "The developer's starting provider must remain first in the route."
        )
        XCTAssertEqual(
            usage.routedImageProvider(from: visualProviders, maximumConsecutiveRequests: 1),
            .lykdat
        )
        XCTAssertEqual(
            usage.routedKeywordProvider(from: [.brightData, .serper]),
            .brightData,
            "The caller's keyword starting provider must remain first in the route."
        )
        let visualID = try usage.reserveProductSearch(
            garmentKey: "visual-one",
            providers: [ImageSearchProvider.lykdat.rawValue],
            perGarmentLimit: 1,
            providerMonthlyLimits: limits,
            fireworksBudgetUSD: 50
        )
        usage.complete(
            visualID,
            resultCount: 5,
            latencyMilliseconds: 120,
            estimatedCostUSD: 0,
            diagnostic: "test"
        )
        XCTAssertEqual(
            usage.routedImageProvider(from: visualProviders, maximumConsecutiveRequests: 1),
            .googleVision
        )

        XCTAssertEqual(usage.routedKeywordProvider(from: keywordProviders), .serper)
        let keywordID = try usage.reserveProductSearch(
            garmentKey: "keyword-one",
            providers: ["fireworks", KeywordSearchProvider.serper.rawValue],
            perGarmentLimit: 1,
            providerMonthlyLimits: limits,
            fireworksBudgetUSD: 50
        )
        usage.complete(
            keywordID,
            resultCount: 6,
            latencyMilliseconds: 200,
            estimatedCostUSD: 0.01,
            diagnostic: "test"
        )
        XCTAssertEqual(usage.routedKeywordProvider(from: keywordProviders), .searchAPI)
    }

    func testYouCamFinishingTaskCountMatchesEnabledOperations() {
        var options = YouCamFinishingOptions.none
        XCTAssertEqual(options.enabledTaskCount, 0)
        options.enhancesPhoto = true
        options.improvesLighting = true
        options.changesBackground = true
        XCTAssertEqual(options.enabledTaskCount, 3)
    }
}
