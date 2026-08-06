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
}
