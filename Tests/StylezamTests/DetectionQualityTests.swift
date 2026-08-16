import Foundation
import UIKit
import XCTest
@testable import Stylezam

final class DetectionQualityTests: XCTestCase {
    func testForegroundPNGPreservesGarmentAndClearsBackground() throws {
        let size = CGSize(width: 12, height: 12)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let source = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let cgImage = try XCTUnwrap(source.cgImage)
        var alpha = [UInt8](repeating: 0, count: 12 * 12)
        for y in 3 ..< 9 {
            for x in 3 ..< 9 {
                alpha[(y * 12) + x] = 255
            }
        }

        let data = try XCTUnwrap(
            GarmentVisionEngine.foregroundPNG(
                image: cgImage,
                alpha: alpha,
                width: 12,
                height: 12
            )
        )
        let decoded = try XCTUnwrap(UIImage(data: data)?.cgImage)
        let pixels = try rgbaBytes(decoded)

        XCTAssertLessThan(pixels[((1 * 12) + 1) * 4 + 3], 10)
        XCTAssertGreaterThan(pixels[((6 * 12) + 6) * 4 + 3], 245)
        XCTAssertGreaterThan(pixels[((6 * 12) + 6) * 4 + 2], 120)
    }

    func testHighRiskBagScoreIsNotPresentedAsTrustworthy() {
        let garment = makeGarment(label: "bag, wallet", confidence: 0.78)

        XCTAssertTrue(garment.needsUserReview)
        XCTAssertFalse(garment.isPipelineEligible)
        XCTAssertEqual(garment.userFacingDetectionStatus, "Needs confirmation")
        XCTAssertEqual(
            GarmentDetectionQualityPolicy.liveLabel(
                label: garment.localLabel,
                confidence: garment.localConfidence
            ),
            "Possible Bag"
        )
    }

    func testCalibratedHighRiskBoundaryRequiresStrongEvidence() {
        XCTAssertTrue(
            GarmentDetectionQualityPolicy.needsReview(
                label: "jacket",
                confidence: 0.879
            )
        )
        XCTAssertFalse(
            GarmentDetectionQualityPolicy.needsReview(
                label: "jacket",
                confidence: 0.88
            )
        )
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

    @MainActor
    func testLibraryPrefersTransparentSegmentationOverTheRectangleCrop() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "stylezam-segmentation-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = LibraryStore(rootURL: rootURL)
        let boxCrop = Data("rectangle-with-background".utf8)
        let segmentedCrop = Data("transparent-foreground-garment".utf8)
        let candidate = GarmentCandidate(
            id: "segmented-candidate",
            localLabel: "shirt",
            confidence: 0.94,
            box: BoundingBoxDTO(x: 0.2, y: 0.1, width: 0.5, height: 0.7),
            boxCropData: boxCrop,
            cropData: segmentedCrop
        )

        let scan = try store.addScan(
            imageData: Data("source".utf8),
            origin: .screenCapture,
            mode: .screen,
            detection: GarmentDetectionBatch(method: .coreML, candidates: [candidate], metrics: nil)
        )
        let item = try XCTUnwrap(scan.items.first)
        let cropURL = try XCTUnwrap(store.cropURL(for: item))

        XCTAssertEqual(cropURL.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: cropURL), segmentedCrop)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: scan)), segmentedCrop)
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

    private func rgbaBytes(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: image.width,
                      height: image.height,
                      bitsPerComponent: 8,
                      bytesPerRow: image.width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }
        XCTAssertTrue(rendered)
        return pixels
    }
}
