import UIKit
import XCTest
@testable import Stylezam

final class LiveScreenAutoCaptureCoordinatorTests: XCTestCase {
    func testRequiresThreeStableFramesBeforeCapture() {
        var coordinator = LiveScreenAutoCaptureCoordinator()
        let start = Date(timeIntervalSince1970: 1_000)
        let candidate = makeCandidate(fingerprint: 0x1111_1111_1111_1111)

        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.72, now: start))
        XCTAssertFalse(
            coordinator.shouldCapture(
                candidate,
                qualityScore: 0.74,
                now: start.addingTimeInterval(1)
            )
        )
        XCTAssertTrue(
            coordinator.shouldCapture(
                candidate,
                qualityScore: 0.76,
                now: start.addingTimeInterval(2)
            )
        )
    }

    func testSuccessfulCaptureSuppressesAStationaryDuplicate() {
        var coordinator = LiveScreenAutoCaptureCoordinator()
        let start = Date(timeIntervalSince1970: 2_000)
        let fingerprint: UInt64 = 0x2222_2222_2222_2222
        let candidate = makeCandidate(fingerprint: fingerprint)

        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start))
        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(1)))
        XCTAssertTrue(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(2)))
        coordinator.recordCaptureResult(
            fingerprint: fingerprint,
            shouldSuppressRepeat: true,
            now: start.addingTimeInterval(2)
        )

        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(12)))
        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(13)))
        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(14)))
    }

    func testDifferentGarmentCanCaptureAfterPreviousPiece() {
        var coordinator = LiveScreenAutoCaptureCoordinator()
        let start = Date(timeIntervalSince1970: 3_000)
        let first = makeCandidate(fingerprint: 0)

        _ = coordinator.shouldCapture(first, qualityScore: 0.8, now: start)
        _ = coordinator.shouldCapture(first, qualityScore: 0.8, now: start.addingTimeInterval(1))
        XCTAssertTrue(coordinator.shouldCapture(first, qualityScore: 0.8, now: start.addingTimeInterval(2)))
        coordinator.recordCaptureResult(
            fingerprint: first.fingerprint,
            shouldSuppressRepeat: true,
            now: start.addingTimeInterval(2)
        )

        let next = makeCandidate(label: "coat", fingerprint: .max)
        XCTAssertFalse(coordinator.shouldCapture(next, qualityScore: 0.8, now: start.addingTimeInterval(10)))
        XCTAssertFalse(coordinator.shouldCapture(next, qualityScore: 0.8, now: start.addingTimeInterval(11)))
        XCTAssertTrue(coordinator.shouldCapture(next, qualityScore: 0.8, now: start.addingTimeInterval(12)))
    }

    func testLowQualityFrameBreaksTheStableRun() {
        var coordinator = LiveScreenAutoCaptureCoordinator()
        let start = Date(timeIntervalSince1970: 4_000)
        let candidate = makeCandidate(fingerprint: 0xABCD)

        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start))
        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.2, now: start.addingTimeInterval(1)))
        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(2)))
        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(3)))
        XCTAssertTrue(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(4)))
    }

    func testPerceptualHashIsStableForTheSameCrop() throws {
        let imageData = try XCTUnwrap(splitImageData(leftIsDark: true))
        let region = BoundingBoxDTO(x: 0, y: 0, width: 1, height: 1)

        let first = LiveScreenPerceptualHash.differenceHash(
            imageData: imageData,
            region: region
        )
        let second = LiveScreenPerceptualHash.differenceHash(
            imageData: imageData,
            region: region
        )

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    @MainActor
    func testTallScreenFrameProducesAHighResolutionGarmentCrop() async throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "jacket", withExtension: "jpg")
        )
        let fixture = try XCTUnwrap(UIImage(data: Data(contentsOf: fixtureURL)))
        let screenSize = CGSize(width: 1_290, height: 2_796)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let screen = UIGraphicsImageRenderer(size: screenSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: screenSize))
            let productFrame = CGRect(x: 115, y: 610, width: 1_060, height: 1_520)
            fixture.draw(in: productFrame)
        }
        let screenData = try XCTUnwrap(screen.jpegData(compressionQuality: 0.94))

        let pack = ModelPackManager()
        await pack.refresh()
        let modelURL = try XCTUnwrap(pack.activeModelURL, pack.lastError ?? "model unavailable")
        let manifest = try XCTUnwrap(pack.manifest)
        let engine = GarmentVisionEngine()
        let preview = try await engine.preview(
            imageData: screenData,
            modelURL: modelURL,
            manifest: manifest,
            maxItems: 5
        )
        XCTAssertFalse(preview.candidates.isEmpty)

        let detection = try await engine.analyze(
            imageData: screenData,
            modelURL: modelURL,
            manifest: manifest,
            maxItems: 5,
            enableAdaptiveDetail: true
        )
        let largestCrop = detection.candidates
            .compactMap(\.boxCropData)
            .compactMap(UIImage.init(data:))
            .max { left, right in
                max(left.size.width, left.size.height) < max(right.size.width, right.size.height)
            }
        let crop = try XCTUnwrap(largestCrop)
        XCTAssertGreaterThan(max(crop.size.width, crop.size.height), 384)
        XCTAssertLessThanOrEqual(detection.metrics?.totalMilliseconds ?? .infinity, 10_000)
    }

    @MainActor
    func testTallScreenTopProductIsVisibleToFocusedPreview() async throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "jacket", withExtension: "jpg")
        )
        let fixture = try XCTUnwrap(UIImage(data: Data(contentsOf: fixtureURL)))
        let screenSize = CGSize(width: 1_290, height: 2_796)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let screen = UIGraphicsImageRenderer(size: screenSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: screenSize))
            fixture.draw(in: CGRect(x: 0, y: 80, width: 1_290, height: 900))
        }
        let screenData = try XCTUnwrap(screen.jpegData(compressionQuality: 0.92))

        let pack = ModelPackManager()
        await pack.refresh()
        let modelURL = try XCTUnwrap(pack.activeModelURL, pack.lastError ?? "model unavailable")
        let manifest = try XCTUnwrap(pack.manifest)
        let engine = GarmentVisionEngine()
        let preview = try await engine.adaptiveScreenPreview(
            imageData: screenData,
            modelURL: modelURL,
            manifest: manifest,
            maxItems: 5
        )

        XCTAssertTrue(
            preview.candidates.contains(where: { $0.localLabel == "jacket" }),
            "A top-of-page jacket must pass the lightweight Live Screen gate."
        )
    }

    private func makeCandidate(
        label: String = "jacket",
        fingerprint: UInt64
    ) -> LiveScreenAutoCaptureCoordinator.Candidate {
        LiveScreenAutoCaptureCoordinator.Candidate(
            label: label,
            confidence: 0.82,
            box: BoundingBoxDTO(x: 0.2, y: 0.18, width: 0.52, height: 0.58),
            fingerprint: fingerprint
        )
    }

    private func splitImageData(leftIsDark: Bool) -> Data? {
        let size = CGSize(width: 240, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            (leftIsDark ? UIColor.black : UIColor.white).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            (leftIsDark ? UIColor.white : UIColor.black).setFill()
            context.fill(
                CGRect(
                    x: size.width / 2,
                    y: 0,
                    width: size.width / 2,
                    height: size.height
                )
            )
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}
