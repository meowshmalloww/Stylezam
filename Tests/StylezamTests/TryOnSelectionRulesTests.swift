import XCTest
@testable import Stylezam

final class TryOnSelectionRulesTests: XCTestCase {
    func testTwoTopsConflict() {
        let first = item("White tee", category: .clothes, region: .upperBody)
        let second = item("Blue shirt", category: .clothes, region: .upperBody)

        XCTAssertNotNil(TryOnSelectionRules.conflictMessage(in: [first, second]))
    }

    func testTopCanLayerUnderOuterwear() {
        let top = item("White tee", category: .clothes, region: .upperBody)
        let jacket = item("Denim jacket", category: .clothes, region: .outerwear)

        XCTAssertNil(TryOnSelectionRules.conflictMessage(in: [top, jacket]))
    }

    func testFullBodyConflictsWithSeparateBottom() {
        let dress = item("Dress", category: .clothes, region: .fullBody)
        let trousers = item("Trousers", category: .clothes, region: .lowerBody)

        XCTAssertNotNil(TryOnSelectionRules.conflictMessage(in: [dress, trousers]))
    }

    func testTwoHatsConflictButHatAndBagDoNot() {
        let firstHat = item("Cap", category: .hat, region: .accessory)
        let secondHat = item("Beanie", category: .hat, region: .accessory)
        let bag = item("Tote", category: .bag, region: .accessory)

        XCTAssertNotNil(TryOnSelectionRules.conflictMessage(in: [firstHat, secondHat]))
        XCTAssertNil(TryOnSelectionRules.conflictMessage(in: [firstHat, bag]))
    }

    private func item(
        _ title: String,
        category: TryOnCategory,
        region: TryOnGarmentRegion
    ) -> TryOnTrayItem {
        TryOnTrayItem(
            title: title,
            category: category,
            region: region,
            imageData: Data([0x01]),
            isSelected: true
        )
    }
}
