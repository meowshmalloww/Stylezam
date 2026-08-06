import UIKit
import XCTest
@testable import Stylezam

final class GarmentDuplicateGuardTests: XCTestCase {
    func testAcceptedCropPersistsAReusableVisualSignature() async throws {
        let cropURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "jacket", withExtension: "jpg")
        )
        let crop = try Data(contentsOf: cropURL)
        let candidate = makeCandidate(id: "first", label: "shirt", crop: crop)
        let guardOne = GarmentDuplicateGuard()

        let accepted = await guardOne.novelCandidates([candidate], history: [])

        XCTAssertEqual(accepted.map(\.candidate.id), ["first"])
        let fingerprint = try XCTUnwrap(accepted.first?.fingerprint)
        XCTAssertNotNil(fingerprint.perceptualHash)
        XCTAssertNotNil(fingerprint.featurePrintData)

        // Simulate relaunching the app: a new actor receives only the signature stored in Library.
        let guardAfterRelaunch = GarmentDuplicateGuard()
        let repeated = await guardAfterRelaunch.novelCandidates(
            [makeCandidate(id: "second", label: "top", crop: crop)],
            history: [
                GarmentFingerprintSource(
                    id: "saved-scan:first",
                    label: "shirt",
                    data: nil,
                    perceptualHash: fingerprint.perceptualHash,
                    featurePrintData: fingerprint.featurePrintData
                ),
            ]
        )

        XCTAssertTrue(repeated.isEmpty)
    }

    func testDifferentVisualIsStillAcceptedWithinSameCategory() async throws {
        let first = try XCTUnwrap(garmentImageData(reverse: false))
        let second = try XCTUnwrap(garmentImageData(reverse: true))
        let duplicateGuard = GarmentDuplicateGuard()

        let accepted = await duplicateGuard.novelCandidates(
            [
                makeCandidate(id: "light-left", label: "shirt", crop: first),
                makeCandidate(id: "light-right", label: "shirt", crop: second),
            ],
            history: []
        )

        XCTAssertEqual(accepted.count, 2)
    }

    func testResizedReencodedCropMatchesStoredLibrarySignature() async throws {
        let cropURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "jacket", withExtension: "jpg")
        )
        let original = try Data(contentsOf: cropURL)
        let firstGuard = GarmentDuplicateGuard()
        let first = await firstGuard.novelCandidates(
            [makeCandidate(id: "camera", label: "jacket", crop: original)],
            history: []
        )
        let fingerprint = try XCTUnwrap(first.first?.fingerprint)

        let image = try XCTUnwrap(UIImage(data: original))
        let resized = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 480)).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 720, height: 480))
        }
        let reencoded = try XCTUnwrap(resized.jpegData(compressionQuality: 0.55))
        let guardAfterRelaunch = GarmentDuplicateGuard()
        let repeated = await guardAfterRelaunch.novelCandidates(
            [makeCandidate(id: "live-screen", label: "coat", crop: reencoded)],
            history: [
                GarmentFingerprintSource(
                    id: "saved-camera-jacket",
                    label: "jacket",
                    data: nil,
                    perceptualHash: fingerprint.perceptualHash,
                    featurePrintData: fingerprint.featurePrintData
                ),
            ]
        )

        XCTAssertTrue(repeated.isEmpty)
    }

    private func makeCandidate(id: String, label: String, crop: Data) -> GarmentCandidate {
        GarmentCandidate(
            id: id,
            localLabel: label,
            confidence: 0.94,
            box: BoundingBoxDTO(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            boxCropData: crop,
            cropData: crop
        )
    }

    private func garmentImageData(reverse: Bool) -> Data? {
        let size = CGSize(width: 256, height: 320)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor.systemBackground.setFill()
            context.fill(bounds)

            let left = reverse ? UIColor.black : UIColor.white
            let right = reverse ? UIColor.white : UIColor.black
            left.setFill()
            context.fill(CGRect(x: 28, y: 30, width: 100, height: 260))
            right.setFill()
            context.fill(CGRect(x: 128, y: 30, width: 100, height: 260))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 74, y: 110, width: 108, height: 76))
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}
