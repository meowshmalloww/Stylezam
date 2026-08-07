import Foundation
import XCTest
@testable import Stylezam

final class DetectionQualityTests: XCTestCase {
    func testHighRiskBagScoreIsNotPresentedAsTrustworthy() {
        let garment = makeGarment(label: "bag, wallet", confidence: 0.78)

        XCTAssertTrue(garment.needsUserReview)
        XCTAssertFalse(garment.isPipelineEligible)
        XCTAssertEqual(garment.userFacingDetectionStatus, "Needs confirmation")
    }

    func testExplicitCorrectionOverridesUncertainDetectorScore() {
        var garment = makeGarment(label: "skirt", confidence: 0.63)
        garment.reviewState = .confirmed
        garment.category = TryOnCategory.clothes.rawValue
        garment.displayName = "Pants"

        XCTAssertFalse(garment.needsUserReview)
        XCTAssertTrue(garment.isPipelineEligible)
        XCTAssertEqual(garment.title, "Pants")
    }

    func testRejectedObjectCannotEnterPipeline() {
        var garment = makeGarment(label: "jacket", confidence: 0.95)
        garment.accepted = false
        garment.reviewState = .rejected

        XCTAssertFalse(garment.isPipelineEligible)
        XCTAssertEqual(garment.userFacingDetectionStatus, "Not fashion")
    }

    @MainActor
    func testLibraryCorrectionRejectsObjectAndConfirmsCorrectCategory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "stylezam-quality-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = LibraryStore(rootURL: rootURL)
        let candidate = GarmentCandidate(
            id: "candidate-1",
            localLabel: "bag, wallet",
            confidence: 0.78,
            box: BoundingBoxDTO(x: 0.1, y: 0.1, width: 0.7, height: 0.7),
            boxCropData: Data("crop".utf8),
            cropData: nil
        )
        let scan = try store.addScan(
            imageData: Data("capture".utf8),
            origin: .camera,
            mode: .photo,
            detection: GarmentDetectionBatch(method: .coreML, candidates: [candidate], metrics: nil)
        )

        let confirmed = try store.applyDetectionCorrection(
            .fashion(category: .clothes, label: "Pants"),
            scanID: scan.id,
            garmentID: candidate.id
        )
        XCTAssertTrue(confirmed.isPipelineEligible)
        XCTAssertEqual(confirmed.title, "Pants")

        let rejected = try store.applyDetectionCorrection(
            .notFashion,
            scanID: scan.id,
            garmentID: candidate.id
        )
        XCTAssertFalse(rejected.accepted)
        XCTAssertFalse(rejected.isPipelineEligible)
        XCTAssertEqual(rejected.reviewState, .rejected)
    }

    private func makeGarment(label: String, confidence: Double) -> SavedGarment {
        SavedGarment(
            id: UUID().uuidString,
            cropFilename: nil,
            localLabel: label,
            localConfidence: confidence,
            box: BoundingBoxDTO(x: 0, y: 0, width: 1, height: 1),
            accepted: true,
            category: nil,
            displayName: nil,
            brand: nil,
            colors: [],
            materials: [],
            patterns: [],
            details: [],
            visibleText: []
        )
    }
}
