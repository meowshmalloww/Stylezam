import UIKit
import XCTest
@testable import Stylezam

final class LiveScreenAutoCaptureCoordinatorTests: XCTestCase {
    func testChangedContentRunsGlobalRecognitionImmediately() {
        XCTAssertEqual(
            LiveScreenAnalysisPlanner.strategy(
                contentIsStable: false,
                stableFrameCount: 1,
                hasFocus: false
            ),
            .global
        )
    }

    func testStableDetectedContentUsesFocusedConfirmation() {
        XCTAssertEqual(
            LiveScreenAnalysisPlanner.strategy(
                contentIsStable: true,
                stableFrameCount: 2,
                hasFocus: true
            ),
            .focused
        )
    }

    func testStableFocusedContentPeriodicallyReturnsToFullScreenDiscovery() {
        XCTAssertEqual(
            LiveScreenAnalysisPlanner.strategy(
                contentIsStable: true,
                stableFrameCount: 3,
                hasFocus: true
            ),
            .adaptive
        )
    }

    func testStableEmptyContentGetsAdaptiveDetailScan() {
        XCTAssertEqual(
            LiveScreenAnalysisPlanner.strategy(
                contentIsStable: true,
                stableFrameCount: 2,
                hasFocus: false
            ),
            .adaptive
        )
    }

    @MainActor
    func testLiveScreenDebugSnapshotUsesRealFrameAndBoxes() throws {
        let frameData = try XCTUnwrap(splitImageData(leftIsDark: true))
        let candidate = GarmentCandidate(
            id: "debug-jacket",
            localLabel: "jacket",
            confidence: 0.91,
            box: BoundingBoxDTO(x: 0.2, y: 0.15, width: 0.5, height: 0.65),
            boxCropData: nil,
            cropData: nil
        )
        let frame = LiveScreenFrame(
            capturedAt: Date(timeIntervalSince1970: 11_000),
            data: frameData,
            pixelWidth: 240,
            pixelHeight: 180
        )
        let manager = LiveScreenCaptureManager()

        manager.recordAnalysis(
            frame: frame,
            candidates: [candidate],
            stage: "Detected 1 garment region",
            retainDebugArtifacts: true
        )

        XCTAssertEqual(manager.analyzedFrameCount, 1)
        XCTAssertNotNil(manager.lastDetectionAt)
        XCTAssertEqual(manager.latestDebugSnapshot?.frameData, frameData)
        XCTAssertEqual(manager.latestDebugSnapshot?.candidates, [candidate])
        XCTAssertEqual(manager.latestDebugSnapshot?.stage, "Detected 1 garment region")

        manager.clearDebugSnapshot()
        XCTAssertNil(manager.latestDebugSnapshot)
    }

    func testRequiresTwoStableFramesBeforeCapture() {
        var coordinator = LiveScreenAutoCaptureCoordinator()
        let start = Date(timeIntervalSince1970: 1_000)
        let candidate = makeCandidate(fingerprint: 0x1111_1111_1111_1111)

        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.72, now: start))
        XCTAssertTrue(
            coordinator.shouldCapture(
                candidate,
                qualityScore: 0.74,
                now: start.addingTimeInterval(1)
            )
        )
    }

    func testSuccessfulCaptureSuppressesAStationaryDuplicate() {
        var coordinator = LiveScreenAutoCaptureCoordinator()
        let start = Date(timeIntervalSince1970: 2_000)
        let fingerprint: UInt64 = 0x2222_2222_2222_2222
        let candidate = makeCandidate(fingerprint: fingerprint)

        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start))
        XCTAssertTrue(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(1)))
        coordinator.recordCaptureResult(
            fingerprint: fingerprint,
            shouldSuppressRepeat: true,
            now: start.addingTimeInterval(1)
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
        XCTAssertTrue(coordinator.shouldCapture(first, qualityScore: 0.8, now: start.addingTimeInterval(1)))
        coordinator.recordCaptureResult(
            fingerprint: first.fingerprint,
            shouldSuppressRepeat: true,
            now: start.addingTimeInterval(1)
        )

        let next = makeCandidate(label: "coat", fingerprint: .max)
        XCTAssertFalse(coordinator.shouldCapture(next, qualityScore: 0.8, now: start.addingTimeInterval(10)))
        XCTAssertTrue(coordinator.shouldCapture(next, qualityScore: 0.8, now: start.addingTimeInterval(11)))
    }

    func testLowQualityFrameBreaksTheStableRun() {
        var coordinator = LiveScreenAutoCaptureCoordinator()
        let start = Date(timeIntervalSince1970: 4_000)
        let candidate = makeCandidate(fingerprint: 0xABCD)

        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start))
        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.2, now: start.addingTimeInterval(1)))
        XCTAssertFalse(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(2)))
        XCTAssertTrue(coordinator.shouldCapture(candidate, qualityScore: 0.8, now: start.addingTimeInterval(3)))
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

    func testContentFingerprintSkipsAnUnchangedScreen() throws {
        let imageData = try XCTUnwrap(splitImageData(leftIsDark: true))
        let first = try XCTUnwrap(
            LiveScreenContentFingerprint.make(imageData: imageData)
        )
        let second = try XCTUnwrap(
            LiveScreenContentFingerprint.make(imageData: imageData)
        )

        XCTAssertTrue(first.isVisuallySimilar(to: second))
    }

    func testContentFingerprintResumesForAChangedScreen() throws {
        let first = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(splitImageData(leftIsDark: true))
            )
        )
        let changed = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(splitImageData(leftIsDark: false))
            )
        )

        XCTAssertFalse(first.isVisuallySimilar(to: changed))
    }

    func testContentFingerprintIgnoresAnimatedOuterScreenChrome() throws {
        let first = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(
                    portraitScreenData(contentIsDark: true, chromeIsDark: false)
                )
            )
        )
        let changedChrome = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(
                    portraitScreenData(contentIsDark: true, chromeIsDark: true)
                )
            )
        )
        let changedContent = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(
                    portraitScreenData(contentIsDark: false, chromeIsDark: true)
                )
            )
        )

        XCTAssertTrue(first.isVisuallySimilar(to: changedChrome))
        XCTAssertFalse(first.isVisuallySimilar(to: changedContent))
    }

    func testEmptyLiveViewBacksOffAndRetriesPeriodically() throws {
        var gate = LiveContentInferenceGate()
        let fingerprint = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(splitImageData(leftIsDark: true))
            )
        )
        let start = Date(timeIntervalSince1970: 8_000)

        XCTAssertTrue(gate.shouldAnalyze(fingerprint: fingerprint, now: start))
        gate.recordResult(hasCandidates: false, now: start)
        XCTAssertTrue(
            gate.shouldAnalyze(fingerprint: fingerprint, now: start.addingTimeInterval(0.82))
        )
        gate.recordResult(hasCandidates: false, now: start.addingTimeInterval(0.82))
        XCTAssertFalse(
            gate.shouldAnalyze(fingerprint: fingerprint, now: start.addingTimeInterval(1.64))
        )
        XCTAssertTrue(
            gate.shouldAnalyze(fingerprint: fingerprint, now: start.addingTimeInterval(3.3))
        )
    }

    func testChangedLiveViewImmediatelyWakesAnEmptyBackoff() throws {
        var gate = LiveContentInferenceGate()
        let first = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(splitImageData(leftIsDark: true))
            )
        )
        let changed = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(splitImageData(leftIsDark: false))
            )
        )
        let start = Date(timeIntervalSince1970: 9_000)

        XCTAssertTrue(gate.shouldAnalyze(fingerprint: first, now: start))
        gate.recordResult(hasCandidates: false, now: start)
        XCTAssertTrue(gate.shouldAnalyze(fingerprint: first, now: start.addingTimeInterval(0.82)))
        gate.recordResult(hasCandidates: false, now: start.addingTimeInterval(0.82))
        XCTAssertTrue(gate.shouldAnalyze(fingerprint: changed, now: start.addingTimeInterval(1)))
    }

    func testLiveGarmentConfirmationKeepsTheFastCadence() throws {
        var gate = LiveContentInferenceGate()
        let fingerprint = try XCTUnwrap(
            LiveScreenContentFingerprint.make(
                imageData: try XCTUnwrap(splitImageData(leftIsDark: true))
            )
        )
        let start = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(gate.shouldAnalyze(fingerprint: fingerprint, now: start))
        gate.recordResult(hasCandidates: true, now: start)
        XCTAssertTrue(
            gate.shouldAnalyze(fingerprint: fingerprint, now: start.addingTimeInterval(0.82))
        )
        gate.recordResult(hasCandidates: true, now: start.addingTimeInterval(0.82))
        XCTAssertTrue(
            gate.shouldAnalyze(fingerprint: fingerprint, now: start.addingTimeInterval(1.64))
        )
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
        let segmentedCrops = detection.candidates
            .compactMap(\.cropData)
            .compactMap(UIImage.init(data:))
        XCTAssertFalse(
            segmentedCrops.isEmpty,
            "A saved live-screen capture must materialize at least one segmented garment crop."
        )
        XCTAssertTrue(
            segmentedCrops.contains { image in
                guard let data = image.pngData() else { return false }
                return YouCamTryOnService.hasUsefulTransparency(data)
            },
            "The saved garment artwork must retain a transparent background when the model mask is usable."
        )
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

    private func portraitScreenData(
        contentIsDark: Bool,
        chromeIsDark: Bool
    ) -> Data? {
        let size = CGSize(width: 240, height: 520)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            (chromeIsDark ? UIColor.black : UIColor.white).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            (contentIsDark ? UIColor.black : UIColor.white).setFill()
            context.fill(CGRect(x: 4, y: 33, width: 232, height: 428))
            (contentIsDark ? UIColor.white : UIColor.black).setFill()
            context.fill(CGRect(x: 70, y: 135, width: 100, height: 235))
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}
