import Foundation
import XCTest
@testable import Stylezam

final class WardrobeRetrievalTests: XCTestCase {
    func testMetadataEmbeddingIsDeterministicAndNormalized() {
        let first = StylezamMetadataEmbedding.vector(for: "navy wide leg trousers")
        let second = StylezamMetadataEmbedding.vector(for: "navy wide leg trousers")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 256)
        let magnitude = sqrt(first.reduce(Float.zero) { $0 + ($1 * $1) })
        XCTAssertEqual(magnitude, 1, accuracy: 0.0001)
    }

    func testRetrievalReturnsOnlyBoundedEligibleRelevantItems() {
        let selectedID = UUID()
        let scans = [
            makeScan(id: selectedID, daysAgo: 0, item: makeItem(id: "selected", label: "navy trousers", category: "pants", confirmed: true)),
            makeScan(daysAgo: 1, item: makeItem(id: "shoes", label: "off white leather sneakers", category: "shoes", confirmed: true)),
            makeScan(daysAgo: 2, item: makeItem(id: "jacket", label: "navy wool jacket", category: "jacket", confirmed: true)),
            makeScan(daysAgo: 3, item: makeItem(id: "bag", label: "brown leather bag", category: "bag", confirmed: true)),
            makeScan(daysAgo: 4, item: makeItem(id: "rejected", label: "blanket jacket", category: "jacket", confirmed: false)),
        ]

        let results = WardrobeRetrievalService.relevantItems(
            question: "What shoes work with my navy trousers?",
            selectedScanID: selectedID,
            selectedGarmentID: "selected",
            scans: scans,
            cropURL: { _ in nil },
            limit: 3
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.contains { $0.garmentID == "shoes" })
        XCTAssertFalse(results.contains { $0.garmentID == "rejected" })
    }

    @MainActor
    func testCloudProjectionExcludesPersonAndTryOnMedia() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "stylezam-cloud-privacy-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let candidate = GarmentCandidate(
            id: "garment",
            localLabel: "shirt",
            confidence: 0.99,
            box: BoundingBoxDTO(x: 0, y: 0, width: 1, height: 1),
            boxCropData: Data("private-crop".utf8),
            cropData: nil
        )
        _ = try store.addScan(
            imageData: Data("full-private-capture".utf8),
            origin: .camera,
            mode: .photo,
            detection: GarmentDetectionBatch(method: .coreML, candidates: [candidate], metrics: nil)
        )
        let person = try store.addTryOnPersonPhoto(
            imageData: Data("face-and-body".utf8),
            context: .outfit
        )
        _ = try store.addTryOn(
            jobID: "try-on",
            personPhotoID: person.id,
            photoContext: .outfit,
            imageData: Data("generated-person".utf8)
        )

        let projection = store.cloudLibraryExport()
        XCTAssertEqual(projection.garments.count, 1)
        XCTAssertEqual(projection.eligibleCropCount, 1)
        XCTAssertTrue(store.tryOnPersonPhotos.count == 1)
        XCTAssertTrue(store.tryOns.count == 1)
        // CloudLibraryExport has no capture, person-photo, or try-on media collection by design.
        XCTAssertEqual(projection.wardrobe.count, 0)
    }

    private func makeScan(
        id: UUID = UUID(),
        daysAgo: Double,
        item: SavedGarment
    ) -> SavedScan {
        SavedScan(
            id: id,
            createdAt: Date().addingTimeInterval(-daysAgo * 86_400),
            imageFilename: "\(id).jpg",
            origin: .camera,
            mode: .photo,
            detectionMethod: .coreML,
            visionMetrics: nil,
            labelState: .local,
            items: [item]
        )
    }

    private func makeItem(
        id: String,
        label: String,
        category: String,
        confirmed: Bool
    ) -> SavedGarment {
        SavedGarment(
            id: id,
            cropFilename: nil,
            localLabel: label,
            localConfidence: confirmed ? 0.99 : 0.6,
            box: BoundingBoxDTO(x: 0, y: 0, width: 1, height: 1),
            accepted: confirmed,
            category: category,
            displayName: label,
            brand: nil,
            colors: [],
            materials: [],
            patterns: [],
            details: [],
            visibleText: [],
            reviewState: confirmed ? .confirmed : .rejected
        )
    }
}
