import Foundation
import XCTest
@testable import Stylezam

final class FitEngineTests: XCTestCase {
    private func chart(
        basis: GarmentSizeChart.Basis = .garment,
        sizes: [GarmentSizeSpec]
    ) -> GarmentSizeChart {
        GarmentSizeChart(
            productID: "test-product",
            sourceURL: URL(string: "https://example.com/product")!,
            basis: basis,
            sizes: sizes,
            sourceNote: nil,
            fetchedAt: .now
        )
    }

    func testRecommendsSizeWithIdealEaseForTop() {
        // Body chest 96 cm. Garment chest: S 98 (2 cm ease, snug for a top),
        // M 104 (8 cm, ideal), L 112 (16 cm, relaxed/oversized edge).
        let body = BodyMeasurements(chestCm: 96, waistCm: 82)
        let chart = chart(sizes: [
            GarmentSizeSpec(label: "S", measurements: [.chest: 98]),
            GarmentSizeSpec(label: "M", measurements: [.chest: 104]),
            GarmentSizeSpec(label: "L", measurements: [.chest: 112]),
        ])

        let recommendation = FitEngine.recommendation(
            chart: chart,
            body: body,
            category: "shirts",
            title: "Oxford cotton shirt"
        )

        XCTAssertEqual(recommendation.recommendedSizeLabel, "M")
        XCTAssertEqual(recommendation.assessment(for: "M")?.verdict, .ideal)
        XCTAssertEqual(recommendation.assessment(for: "S")?.dimensionFits.first?.rating, .snug)
    }

    func testFlagsTooTightSize() {
        let body = BodyMeasurements(chestCm: 104)
        let chart = chart(sizes: [
            GarmentSizeSpec(label: "XS", measurements: [.chest: 92]),
        ])

        let recommendation = FitEngine.recommendation(
            chart: chart,
            body: body,
            category: "t-shirts",
            title: "Basic tee"
        )

        XCTAssertNil(recommendation.recommendedSizeLabel)
        XCTAssertEqual(recommendation.assessment(for: "XS")?.verdict, .tooTight)
    }

    func testBodyBasisChartComparesDirectly() {
        // A body-measurement chart says size M fits a 96 cm chest; the user
        // is 96 cm, so M should be ideal even though ease would be zero.
        let body = BodyMeasurements(chestCm: 96)
        let chart = chart(basis: .body, sizes: [
            GarmentSizeSpec(label: "S", measurements: [.chest: 88]),
            GarmentSizeSpec(label: "M", measurements: [.chest: 96]),
            GarmentSizeSpec(label: "L", measurements: [.chest: 104]),
        ])

        let recommendation = FitEngine.recommendation(
            chart: chart,
            body: body,
            category: nil,
            title: "Crewneck sweater"
        )

        XCTAssertEqual(recommendation.recommendedSizeLabel, "M")
        XCTAssertEqual(recommendation.assessment(for: "M")?.verdict, .ideal)
    }

    func testBottomsPrioritizeWaistAndHips() {
        let body = BodyMeasurements(waistCm: 80, hipsCm: 98, inseamCm: 78)
        let chart = chart(sizes: [
            GarmentSizeSpec(label: "30", measurements: [.waist: 78, .hips: 100, .inseam: 78]),
            GarmentSizeSpec(label: "32", measurements: [.waist: 82, .hips: 104, .inseam: 78]),
            GarmentSizeSpec(label: "34", measurements: [.waist: 87, .hips: 109, .inseam: 78]),
        ])

        let recommendation = FitEngine.recommendation(
            chart: chart,
            body: body,
            category: "jeans",
            title: "Straight-leg denim jeans"
        )

        XCTAssertEqual(recommendation.recommendedSizeLabel, "32")
        let waistFit = recommendation.assessment(for: "34")?
            .dimensionFits.first { $0.dimension == .waist }
        XCTAssertEqual(waistFit?.rating, .relaxed)
    }

    func testNoMeasurementsYieldsNoRecommendationButKeepsChart() {
        let chart = chart(sizes: [
            GarmentSizeSpec(label: "S", measurements: [.chest: 98, .length: 68]),
            GarmentSizeSpec(label: "M", measurements: [.chest: 104, .length: 70]),
        ])

        let recommendation = FitEngine.recommendation(
            chart: chart,
            body: .empty,
            category: "shirts",
            title: "Linen shirt"
        )

        XCTAssertNil(recommendation.recommendedSizeLabel)
        XCTAssertEqual(recommendation.assessments.count, 2)
        XCTAssertNotNil(recommendation.note)
    }

    func testLengthProducesHemNoteWithHeight() {
        // 170 cm tall; shoulder ≈ 139 cm from floor. A 70 cm shirt hem lands
        // ≈ 69 cm from the floor — mid-thigh territory, never "cropped".
        let body = BodyMeasurements(heightCm: 170, chestCm: 96)
        let chart = chart(sizes: [
            GarmentSizeSpec(label: "M", measurements: [.chest: 104, .length: 70]),
        ])

        let recommendation = FitEngine.recommendation(
            chart: chart,
            body: body,
            category: "shirts",
            title: "Longline tee"
        )

        let lengthFit = recommendation.assessment(for: "M")?
            .dimensionFits.first { $0.dimension == .length }
        XCTAssertNotNil(lengthFit)
        XCTAssertNil(lengthFit?.rating)
        XCTAssertTrue(lengthFit?.note.contains("hem") == true)
    }

    func testBetweenSizesNoteAppearsWhenScoresAreClose() {
        let body = BodyMeasurements(chestCm: 100)
        let chart = chart(sizes: [
            GarmentSizeSpec(label: "M", measurements: [.chest: 106]),
            GarmentSizeSpec(label: "L", measurements: [.chest: 110]),
        ])

        let recommendation = FitEngine.recommendation(
            chart: chart,
            body: body,
            category: "shirts",
            title: "Flannel overshirt"
        )

        // Both sizes fall inside the ideal ease band, so the user is between sizes.
        XCTAssertNotNil(recommendation.recommendedSizeLabel)
        XCTAssertNotNil(recommendation.note)
        XCTAssertTrue(recommendation.note?.contains("between") == true)
    }
}
