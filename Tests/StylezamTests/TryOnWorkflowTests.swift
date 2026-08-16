import Foundation
import UIKit
import XCTest
@testable import Stylezam

final class TryOnWorkflowTests: XCTestCase {
    func testProviderRequestsUseStableAppIdentity() {
        XCTAssertEqual(
            ProductSearchService.requestUserAgent,
            "Stylezam/1.0 (iOS; API client)"
        )
    }

    func testYouCamPayloadRoutesExactCategoryAndOuterwear() {
        XCTAssertEqual(TryOnCategory.hat.youCamEndpoint, "hat")
        XCTAssertEqual(TryOnCategory.bag.youCamEndpoint, "bag")
        XCTAssertEqual(TryOnCategory.clothes.youCamEndpoint, "cloth-v4")
        XCTAssertEqual(YouCamTryOnService.uploadPath(for: .hat), "/s2s/v2.0/file")
        XCTAssertEqual(YouCamTryOnService.uploadPath(for: .shoes), "/s2s/v2.0/file")
        XCTAssertEqual(YouCamTryOnService.uploadPath(for: .bag), "/s2s/v2.0/file")
        XCTAssertEqual(YouCamTryOnService.uploadPath(for: .scarf), "/s2s/v2.0/file")
        XCTAssertEqual(YouCamTryOnService.uploadPath(for: .clothes), "/s2s/v2.0/file")

        let hat = YouCamTryOnService.tryOnTaskBody(
            category: .hat,
            garmentRegion: .accessory,
            sourceID: "person",
            referenceID: "hat-reference",
            gender: .male
        )
        XCTAssertEqual(hat["src_file_id"] as? String, "person")
        XCTAssertEqual(hat["ref_file_id"] as? String, "hat-reference")
        XCTAssertEqual(hat["gender"] as? String, "male")
        XCTAssertEqual(hat["style"] as? String, "random")
        XCTAssertNil(hat["garment_category"])
        XCTAssertNil(hat["change_shoes"])

        let jacket = YouCamTryOnService.tryOnTaskBody(
            category: .clothes,
            garmentRegion: .outerwear,
            sourceID: "person",
            referenceID: "jacket-reference",
            gender: .female
        )
        XCTAssertEqual(jacket["garment_category"] as? String, "outer")
        XCTAssertEqual(jacket["change_shoes"] as? Bool, false)
        XCTAssertNil(jacket["gender"])

        XCTAssertEqual(
            TryOnGarmentRegion.infer(category: .clothes, title: "White T-shirt or top"),
            .upperBody
        )
    }

    func testFinishingOptionsMapToExactEntitledEndpoints() {
        let options = YouCamFinishingOptions(
            removesBackground: true,
            changesBackground: false,
            backgroundPrompt: "",
            improvesLighting: true,
            enhancesPhoto: true
        )
        XCTAssertEqual(options.enabledTaskCount, 3)
        XCTAssertEqual(
            Set(options.enabledTasks.map { $0.endpoint }),
            Set(["enhance", "lighting", "sod"])
        )
    }

    func testTryOnSceneGuardAcceptsLocalizedHatAndRejectsStyledScene() throws {
        let source = try XCTUnwrap(testImageData(background: .lightGray))
        let localizedHat = try XCTUnwrap(
            testImageData(
                background: .lightGray,
                editColor: .black,
                editRect: CGRect(x: 90, y: 14, width: 180, height: 92)
            )
        )
        XCTAssertNoThrow(
            try YouCamTryOnService.validateSingleItemScenePreservation(
                source: source,
                result: localizedHat,
                category: .hat,
                garmentRegion: .accessory
            )
        )

        let styledScene = try XCTUnwrap(testImageData(background: .systemBlue))
        XCTAssertThrowsError(
            try YouCamTryOnService.validateSingleItemScenePreservation(
                source: source,
                result: styledScene,
                category: .hat,
                garmentRegion: .accessory
            )
        )
    }

    func testTryOnSceneGuardAllowsNormalProviderToneShift() throws {
        let source = try XCTUnwrap(testImageData(background: .lightGray))
        let lightlyRelit = try XCTUnwrap(
            testImageData(
                background: UIColor(white: 0.78, alpha: 1),
                editColor: .black,
                editRect: CGRect(x: 90, y: 14, width: 180, height: 92)
            )
        )

        XCTAssertNoThrow(
            try YouCamTryOnService.validateSingleItemScenePreservation(
                source: source,
                result: lightlyRelit,
                category: .hat,
                garmentRegion: .accessory
            )
        )
    }

    func testBackgroundRemovalRequiresActualTransparentPixels() throws {
        let opaque = try XCTUnwrap(testImageData(background: .white))
        XCTAssertFalse(YouCamTryOnService.hasUsefulTransparency(opaque))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let transparent = UIGraphicsImageRenderer(
            size: CGSize(width: 360, height: 480),
            format: format
        ).image { context in
            context.cgContext.clear(CGRect(x: 0, y: 0, width: 360, height: 480))
            UIColor.black.setFill()
            context.fill(CGRect(x: 110, y: 55, width: 140, height: 390))
        }.pngData()
        XCTAssertTrue(YouCamTryOnService.hasUsefulTransparency(try XCTUnwrap(transparent)))
    }

    func testNonBackgroundFinishCannotReplaceTheWholeScene() throws {
        let source = try XCTUnwrap(testImageData(background: .lightGray))
        let lightlyRelit = try XCTUnwrap(
            testImageData(background: UIColor(white: 0.78, alpha: 1))
        )
        XCTAssertNoThrow(
            try YouCamTryOnService.validateFinishingSubjectPreservation(
                source: source,
                result: lightlyRelit,
                operation: "lighting",
                allowsBackgroundChange: false
            )
        )

        let replacement = try XCTUnwrap(testImageData(background: .systemPurple))
        XCTAssertThrowsError(
            try YouCamTryOnService.validateFinishingSubjectPreservation(
                source: source,
                result: replacement,
                operation: "detail enhancement",
                allowsBackgroundChange: false
            )
        )
    }

    func testSpecificAccessoryInferenceAndPhotoContextCompatibility() {
        XCTAssertEqual(
            TryOnCategory.infer(from: "Women's apparel pearl chain necklace"),
            .necklace
        )
        XCTAssertEqual(
            TryOnCategory.infer(category: "Women's clothing", title: "Pearl necklace"),
            .necklace
        )
        XCTAssertEqual(
            TryOnCategory.infer(category: "Apparel accessories", title: "Leather cuff bracelet"),
            .bracelet
        )
        XCTAssertEqual(
            TryOnCategory.infer(category: "Women's clothing", title: "Wide-leg trousers"),
            .clothes
        )

        XCTAssertEqual(
            TryOnPhotoContext.outfit.renderCategories,
            [.clothes, .bag, .shoes]
        )
        XCTAssertEqual(
            TryOnPhotoContext.head.renderCategories,
            [.hat]
        )
        XCTAssertEqual(
            TryOnPhotoContext.handAndWrist.renderCategories,
            [.ring, .bracelet, .watch]
        )
        XCTAssertEqual(
            TryOnPhotoContext.faceAndNeck.renderCategories,
            [.scarf, .earring, .necklace]
        )
        XCTAssertEqual(
            TryOnPhotoContext.faceAndNeck.categories,
            TryOnPhotoContext.faceAndNeck.renderCategories
        )
    }

    private func testImageData(
        background: UIColor,
        editColor: UIColor? = nil,
        editRect: CGRect? = nil
    ) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: 360, height: 480),
            format: format
        ).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 360, height: 480))
            if let editColor, let editRect {
                editColor.setFill()
                context.fill(editRect)
            }
        }.pngData()
    }

    @MainActor
    func testWardrobeAndSelectedRailEntryPersistAcrossStoreInstances() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let imageData = Data("ivory-shirt-image".utf8)
        let store = LibraryStore(rootURL: rootURL)
        let item = try store.addWardrobeItem(
            title: "Ivory Shirt",
            category: .clothes,
            imageData: imageData,
            garmentRegion: .upperBody
        )
        store.addWardrobeItemToTryOnRail(item, selected: true)

        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.wardrobeItems.map(\.id), [item.id])
        XCTAssertEqual(store.tryOnRail.map(\.wardrobeItemID), [item.id])
        XCTAssertEqual(store.tryOnRail.first?.isSelected, true)

        let reopenedStore = LibraryStore(rootURL: rootURL)
        let persistedItem = try XCTUnwrap(
            reopenedStore.wardrobeItems.first(where: { $0.id == item.id })
        )
        let persistedRailEntry = try XCTUnwrap(
            reopenedStore.tryOnRail.first(where: { $0.wardrobeItemID == item.id })
        )
        let persistedTrayItem = try XCTUnwrap(
            reopenedStore.tryOnTrayItems().first(where: { $0.id == item.id })
        )

        XCTAssertNil(reopenedStore.loadError)
        XCTAssertEqual(persistedItem.title, "Ivory Shirt")
        XCTAssertEqual(persistedItem.garmentRegion, .upperBody)
        XCTAssertTrue(persistedRailEntry.isSelected)
        XCTAssertTrue(persistedTrayItem.isSelected)
        XCTAssertEqual(persistedTrayItem.imageData, imageData)
    }

    @MainActor
    func testRailToggleAndRemoveRetainTheWardrobeItem() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = LibraryStore(rootURL: rootURL)
        let item = try store.addWardrobeItem(
            title: "Wide-leg Trousers",
            category: .clothes,
            imageData: Data("trousers-image".utf8),
            garmentRegion: .lowerBody
        )
        store.addWardrobeItemToTryOnRail(item)
        store.setTryOnRailSelection(item.id, isSelected: false)

        XCTAssertEqual(store.tryOnRail.first?.isSelected, false)
        XCTAssertNotNil(store.wardrobeItem(for: item.id))
        XCTAssertNil(store.tryOnTrayItems().first?.youCamReferenceImageData)
        XCTAssertEqual(store.tryOnTrayItems().first?.isYouCamReferenceReady, false)

        let storeAfterToggle = LibraryStore(rootURL: rootURL)
        XCTAssertEqual(storeAfterToggle.tryOnRail.first?.isSelected, false)
        XCTAssertNotNil(storeAfterToggle.wardrobeItem(for: item.id))

        storeAfterToggle.removeFromTryOnRail(item.id)

        XCTAssertTrue(storeAfterToggle.tryOnRail.isEmpty)
        XCTAssertNotNil(storeAfterToggle.wardrobeItem(for: item.id))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storeAfterToggle.imageURL(for: item).path)
        )

        let storeAfterRemove = LibraryStore(rootURL: rootURL)
        XCTAssertTrue(storeAfterRemove.tryOnRail.isEmpty)
        XCTAssertEqual(storeAfterRemove.wardrobeItems.map(\.id), [item.id])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storeAfterRemove.imageURL(for: item).path)
        )
    }

    @MainActor
    func testAppliedItemIDsAndContentDigestDescribeTheRenderedOutfit() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = LibraryStore(rootURL: rootURL)
        let shirt = try store.addWardrobeItem(
            title: "Blue Shirt",
            category: .clothes,
            imageData: Data("blue-shirt-crop".utf8),
            garmentRegion: .upperBody
        )
        let necklace = try store.addWardrobeItem(
            title: "Gold Necklace",
            category: .necklace,
            imageData: Data("gold-necklace-crop".utf8),
            garmentRegion: .accessory
        )
        store.addWardrobeItemToTryOnRail(shirt, selected: true)
        store.addWardrobeItemToTryOnRail(necklace, selected: false)

        let snapshots = store.tryOnItemSnapshots(appliedItemIDs: Set([necklace.id]))
        let shirtSnapshot = try XCTUnwrap(snapshots.first(where: { $0.id == shirt.id }))
        let necklaceSnapshot = try XCTUnwrap(snapshots.first(where: { $0.id == necklace.id }))
        let tray = store.tryOnTrayItems()

        XCTAssertFalse(shirtSnapshot.wasSelected)
        XCTAssertTrue(necklaceSnapshot.wasSelected)
        XCTAssertEqual(shirtSnapshot.contentDigest, shirt.contentDigest)
        XCTAssertEqual(necklaceSnapshot.contentDigest, necklace.contentDigest)
        XCTAssertEqual(
            tray.first(where: { $0.id == shirt.id })?.contentDigest,
            shirt.contentDigest
        )
        XCTAssertEqual(
            tray.first(where: { $0.id == necklace.id })?.contentDigest,
            necklace.contentDigest
        )

        let railSnapshots = store.tryOnItemSnapshots()
        XCTAssertEqual(
            railSnapshots.first(where: { $0.id == shirt.id })?.wasSelected,
            true
        )
        XCTAssertEqual(
            railSnapshots.first(where: { $0.id == necklace.id })?.wasSelected,
            false
        )
    }

    @MainActor
    func testExactSourceProductEnrichmentKeepsTwoCropsWithOneProductIDDistinct() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let trousersCrop = Data("exact-detected-trousers-crop".utf8)
        let jacketCrop = Data("second-detected-jacket-crop".utf8)
        let replacementMerchantImage = Data("replacement-merchant-shirt-image".utf8)
        let firstScanID = UUID()
        let secondScanID = UUID()
        let originalProduct = try makeProduct(
            id: "merchant-shirt-match",
            title: "Merchant Silk Shirt",
            category: "shirt",
            merchant: "Original Catalog",
            productURLString: "https://original.example.com/silk-shirt",
            checkoutURLString: "https://original.example.com/silk-shirt/buy",
            amount: 120
        )
        let enrichedProduct = try makeProduct(
            id: originalProduct.id,
            title: "Merchant Silk Shirt",
            category: "shirt",
            merchant: "Enriched Catalog",
            productURLString: "https://enriched.example.com/silk-shirt",
            checkoutURLString: "https://enriched.example.com/silk-shirt/buy",
            amount: 115
        )
        let store = LibraryStore(rootURL: rootURL)
        let trousersItem = try store.addWardrobeItem(
            title: "Detected wide-leg trousers",
            category: .clothes,
            imageData: trousersCrop,
            sourceProduct: originalProduct,
            sourceScanID: firstScanID,
            sourceGarmentID: "detected-trousers",
            garmentRegion: .lowerBody
        )
        let jacketItem = try store.addWardrobeItem(
            title: "Detected cropped jacket",
            category: .clothes,
            imageData: jacketCrop,
            sourceProduct: originalProduct,
            sourceScanID: secondScanID,
            sourceGarmentID: "detected-jacket",
            garmentRegion: .outerwear
        )

        let enrichedItem = try XCTUnwrap(store.enrichSourceWardrobeItemInTryOnRail(
            enrichedProduct,
            sourceScanID: firstScanID,
            sourceGarmentID: "detected-trousers"
        ))

        XCTAssertNotEqual(trousersItem.id, jacketItem.id)
        XCTAssertEqual(store.wardrobeItems.count, 2)
        XCTAssertEqual(enrichedItem.id, trousersItem.id)
        XCTAssertNotEqual(enrichedItem.id, jacketItem.id)
        XCTAssertEqual(enrichedItem.category, trousersItem.category)
        XCTAssertEqual(enrichedItem.garmentRegion, .lowerBody)
        XCTAssertEqual(enrichedItem.contentDigest, trousersItem.contentDigest)
        XCTAssertEqual(enrichedItem.sourceProduct?.id, enrichedProduct.id)
        XCTAssertEqual(enrichedItem.sourceProduct?.productURL, enrichedProduct.productURL)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: enrichedItem)), trousersCrop)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: jacketItem)), jacketCrop)
        XCTAssertEqual(store.wardrobeItem(for: jacketItem.id)?.sourceProduct?.merchant, "Original Catalog")
        XCTAssertEqual(store.wardrobeItem(for: jacketItem.id)?.garmentRegion, .outerwear)
        XCTAssertEqual(store.wardrobeItem(for: jacketItem.id)?.contentDigest, jacketItem.contentDigest)

        let enrichedJacket = try store.upsertProductInTryOnRail(
            enrichedProduct,
            imageData: replacementMerchantImage,
            sourceScanID: secondScanID,
            sourceGarmentID: "detected-jacket"
        )
        XCTAssertEqual(enrichedJacket.id, jacketItem.id)
        XCTAssertEqual(enrichedJacket.garmentRegion, .outerwear)
        XCTAssertEqual(enrichedJacket.contentDigest, jacketItem.contentDigest)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: enrichedJacket)), jacketCrop)

        let reopenedStore = LibraryStore(rootURL: rootURL)
        let reopenedItem = try XCTUnwrap(reopenedStore.wardrobeItem(for: trousersItem.id))
        let reopenedJacket = try XCTUnwrap(reopenedStore.wardrobeItem(for: jacketItem.id))
        XCTAssertEqual(reopenedItem.garmentRegion, .lowerBody)
        XCTAssertEqual(reopenedItem.contentDigest, trousersItem.contentDigest)
        XCTAssertEqual(reopenedItem.sourceProduct?.merchant, enrichedProduct.merchant)
        XCTAssertEqual(try Data(contentsOf: reopenedStore.imageURL(for: reopenedItem)), trousersCrop)
        XCTAssertEqual(reopenedJacket.sourceProduct?.merchant, enrichedProduct.merchant)
        XCTAssertEqual(try Data(contentsOf: reopenedStore.imageURL(for: reopenedJacket)), jacketCrop)
    }

    @MainActor
    func testDetectedLowerBodyItemKeepsDurableFullPersonReference() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fullPersonData = Data("full-person-wearing-detected-pants".utf8)
        let pantsCropData = Data("tight-detected-pants-crop".utf8)
        let store = LibraryStore(rootURL: rootURL)
        let scan = try store.addScan(
            imageData: fullPersonData,
            origin: .screenCapture,
            mode: .screen,
            detection: GarmentDetectionBatch(
                method: .coreML,
                candidates: [
                    GarmentCandidate(
                        id: "detected-pants",
                        localLabel: "wide-leg pants",
                        confidence: 0.94,
                        box: BoundingBoxDTO(x: 0.2, y: 0.4, width: 0.6, height: 0.5),
                        boxCropData: pantsCropData,
                        cropData: nil
                    )
                ],
                metrics: nil
            )
        )

        // Simulate a wardrobe item created by an earlier app version, then make
        // sure re-promoting the detected piece backfills its valid API reference.
        let legacyItem = try store.addWardrobeItem(
            title: "Wide-leg pants",
            category: .clothes,
            imageData: pantsCropData,
            sourceScanID: scan.id,
            sourceGarmentID: "detected-pants",
            garmentRegion: .lowerBody
        )
        XCTAssertNil(legacyItem.tryOnReferenceFilename)

        // A saved screen scan intentionally contains only its garment crop. Re-adding
        // it later must stay blocked instead of treating that crop as a worn reference.
        let cropOnlyPromotion = try XCTUnwrap(
            store.addDetectedGarmentToTryOnRail(
                scanID: scan.id,
                garmentID: "detected-pants"
            )
        )
        XCTAssertNil(cropOnlyPromotion.tryOnReferenceFilename)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: scan)), pantsCropData)

        let promotedItem = try XCTUnwrap(
            store.addDetectedGarmentToTryOnRail(
                scanID: scan.id,
                garmentID: "detected-pants",
                sourceFrameData: fullPersonData
            )
        )
        let referenceURL = try XCTUnwrap(store.tryOnReferenceURL(for: promotedItem))
        let displayURL = store.imageURL(for: promotedItem)

        XCTAssertEqual(promotedItem.id, legacyItem.id)
        XCTAssertEqual(promotedItem.garmentRegion, .lowerBody)
        XCTAssertEqual(try Data(contentsOf: displayURL), pantsCropData)
        XCTAssertEqual(try Data(contentsOf: referenceURL), fullPersonData)
        XCTAssertNotNil(promotedItem.tryOnReferenceDigest)

        let product = try makeProduct(
            id: "matched-pants",
            title: "Wide-leg wool pants",
            category: "pants",
            merchant: "Test Merchant",
            productURLString: "https://shop.example.com/wide-leg-pants",
            checkoutURLString: "https://shop.example.com/wide-leg-pants/buy",
            amount: 119
        )
        let enriched = try XCTUnwrap(
            store.enrichSourceWardrobeItemInTryOnRail(
                product,
                sourceScanID: scan.id,
                sourceGarmentID: "detected-pants"
            )
        )
        XCTAssertEqual(enriched.tryOnReferenceFilename, promotedItem.tryOnReferenceFilename)
        XCTAssertEqual(enriched.tryOnReferenceDigest, promotedItem.tryOnReferenceDigest)

        store.deleteScan(scan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenceURL.path))

        let reopenedStore = LibraryStore(rootURL: rootURL)
        let reopenedItem = try XCTUnwrap(reopenedStore.wardrobeItem(for: promotedItem.id))
        let trayItem = try XCTUnwrap(
            reopenedStore.tryOnTrayItems().first(where: { $0.id == promotedItem.id })
        )
        let snapshot = try XCTUnwrap(
            reopenedStore.tryOnItemSnapshots().first(where: { $0.id == promotedItem.id })
        )

        XCTAssertEqual(trayItem.imageData, pantsCropData)
        XCTAssertEqual(trayItem.referenceImageData, fullPersonData)
        XCTAssertEqual(trayItem.youCamReferenceImageData, fullPersonData)
        XCTAssertTrue(trayItem.isYouCamReferenceReady)
        XCTAssertEqual(trayItem.referenceContentDigest, reopenedItem.tryOnReferenceDigest)
        XCTAssertEqual(snapshot.referenceContentDigest, reopenedItem.tryOnReferenceDigest)

        reopenedStore.deleteWardrobeItem(reopenedItem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: displayURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: referenceURL.path))

        let clearItem = try reopenedStore.addWardrobeItem(
            title: "Second pair of pants",
            category: .clothes,
            imageData: pantsCropData,
            tryOnReferenceData: fullPersonData,
            garmentRegion: .lowerBody
        )
        let clearDisplayURL = reopenedStore.imageURL(for: clearItem)
        let clearReferenceURL = try XCTUnwrap(reopenedStore.tryOnReferenceURL(for: clearItem))
        try reopenedStore.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: clearDisplayURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: clearReferenceURL.path))
    }

    @MainActor
    func testIdenticalLowerBodyReferencesShareAReferenceCountedFile() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sharedReference = Data("one-person-wearing-shared-pants".utf8)
        let replacementReference = Data("one-person-wearing-replacement-pants".utf8)
        let store = LibraryStore(rootURL: rootURL)
        let first = try store.addWardrobeItem(
            title: "Black trousers",
            category: .clothes,
            imageData: Data("black-trousers-crop".utf8),
            tryOnReferenceData: sharedReference,
            garmentRegion: .lowerBody
        )
        let second = try store.addWardrobeItem(
            title: "Blue trousers",
            category: .clothes,
            imageData: Data("blue-trousers-crop".utf8),
            tryOnReferenceData: sharedReference,
            garmentRegion: .lowerBody
        )
        let sharedURL = try XCTUnwrap(store.tryOnReferenceURL(for: first))

        XCTAssertEqual(first.tryOnReferenceFilename, second.tryOnReferenceFilename)
        XCTAssertEqual(first.tryOnReferenceDigest, second.tryOnReferenceDigest)
        XCTAssertEqual(store.tryOnReferenceURL(for: second), sharedURL)
        XCTAssertEqual(try Data(contentsOf: sharedURL), sharedReference)

        let updatedFirst = try XCTUnwrap(
            store.setLowerBodyTryOnReference(
                for: first.id,
                imageData: replacementReference
            )
        )
        let replacementURL = try XCTUnwrap(store.tryOnReferenceURL(for: updatedFirst))
        XCTAssertNotEqual(replacementURL, sharedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedURL.path))
        XCTAssertEqual(try Data(contentsOf: replacementURL), replacementReference)

        store.deleteWardrobeItem(second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacementURL.path))

        let third = try store.addWardrobeItem(
            title: "Cream trousers",
            category: .clothes,
            imageData: Data("cream-trousers-crop".utf8),
            tryOnReferenceData: replacementReference,
            garmentRegion: .lowerBody
        )
        XCTAssertEqual(third.tryOnReferenceFilename, updatedFirst.tryOnReferenceFilename)

        store.deleteWardrobeItem(updatedFirst)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacementURL.path))

        let thirdDisplayURL = store.imageURL(for: third)
        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: thirdDisplayURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacementURL.path))
    }

    @MainActor
    func testBatchWardrobeDeletionCleansRailAndReferenceCountedFiles() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sharedReference = Data("one-person-wearing-batch-pants".utf8)
        let store = LibraryStore(rootURL: rootURL)
        let first = try store.addWardrobeItem(
            title: "Batch black trousers",
            category: .clothes,
            imageData: Data("batch-black-trousers-crop".utf8),
            tryOnReferenceData: sharedReference,
            garmentRegion: .lowerBody
        )
        let second = try store.addWardrobeItem(
            title: "Batch blue trousers",
            category: .clothes,
            imageData: Data("batch-blue-trousers-crop".utf8),
            tryOnReferenceData: sharedReference,
            garmentRegion: .lowerBody
        )
        store.addWardrobeItemToTryOnRail(first, selected: true)
        store.addWardrobeItemToTryOnRail(second, selected: true)

        let sharedURL = try XCTUnwrap(store.tryOnReferenceURL(for: first))
        let firstDisplayURL = store.imageURL(for: first)
        let secondDisplayURL = store.imageURL(for: second)

        store.deleteBatch(
            scanIDs: [],
            searchIDs: [],
            wardrobeIDs: [first.id],
            productIDs: [],
            tryOnIDs: []
        )

        XCTAssertNil(store.wardrobeItem(for: first.id))
        XCTAssertFalse(store.tryOnRail.contains { $0.wardrobeItemID == first.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDisplayURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedURL.path))

        store.deleteBatch(
            scanIDs: [],
            searchIDs: [],
            wardrobeIDs: [second.id],
            productIDs: [],
            tryOnIDs: []
        )

        XCTAssertNil(store.wardrobeItem(for: second.id))
        XCTAssertTrue(store.tryOnRail.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDisplayURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedURL.path))
    }

    @MainActor
    func testWardrobeTrimKeepsSharedReferenceUntilItsLastOwnerIsTrimmed() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sharedReference = Data("one-person-wearing-two-detected-pieces".utf8)
        let store = LibraryStore(rootURL: rootURL)
        let first = try store.addWardrobeItem(
            title: "First trousers",
            category: .clothes,
            imageData: Data("first-trousers-crop".utf8),
            tryOnReferenceData: sharedReference,
            garmentRegion: .lowerBody
        )
        let second = try store.addWardrobeItem(
            title: "Second trousers",
            category: .clothes,
            imageData: Data("second-trousers-crop".utf8),
            tryOnReferenceData: sharedReference,
            garmentRegion: .lowerBody
        )
        let sharedURL = try XCTUnwrap(store.tryOnReferenceURL(for: first))

        for index in 0..<99 {
            _ = try store.addWardrobeItem(
                title: "Filler shirt \(index)",
                category: .clothes,
                imageData: Data("filler-shirt-\(index)".utf8),
                garmentRegion: .upperBody
            )
        }

        XCTAssertEqual(store.wardrobeItems.count, 100)
        XCTAssertNil(store.wardrobeItem(for: first.id))
        XCTAssertNotNil(store.wardrobeItem(for: second.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedURL.path))

        _ = try store.addWardrobeItem(
            title: "Final filler shirt",
            category: .clothes,
            imageData: Data("final-filler-shirt".utf8),
            garmentRegion: .upperBody
        )

        XCTAssertEqual(store.wardrobeItems.count, 100)
        XCTAssertNil(store.wardrobeItem(for: second.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedURL.path))
    }

    @MainActor
    func testPersonPhotoHistoryDeduplicationAndActivePhotoPersist() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstPhotoData = Data("first-person-photo".utf8)
        let secondPhotoData = Data("second-person-photo".utf8)
        let store = LibraryStore(rootURL: rootURL)
        let firstPhoto = try store.addTryOnPersonPhoto(
            imageData: firstPhotoData,
            context: .outfit
        )
        let secondPhoto = try store.addTryOnPersonPhoto(
            imageData: secondPhotoData,
            context: .faceAndNeck
        )
        let sameImageDifferentContext = try store.addTryOnPersonPhoto(
            imageData: firstPhotoData,
            context: .handAndWrist
        )
        let duplicateFirstPhoto = try store.addTryOnPersonPhoto(
            imageData: firstPhotoData,
            context: .outfit
        )

        XCTAssertEqual(duplicateFirstPhoto.id, firstPhoto.id)
        XCTAssertNotEqual(sameImageDifferentContext.id, firstPhoto.id)
        XCTAssertEqual(store.tryOnPersonPhotos.count, 3)
        XCTAssertEqual(
            store.tryOnPersonPhotos.map(\.id),
            [firstPhoto.id, sameImageDifferentContext.id, secondPhoto.id]
        )
        XCTAssertEqual(store.tryOnPersonPhotos.first?.context, .outfit)
        XCTAssertEqual(store.activeTryOnPhoto?.id, firstPhoto.id)

        store.setActiveTryOnPhoto(secondPhoto)

        let reopenedStore = LibraryStore(rootURL: rootURL)
        XCTAssertNil(reopenedStore.loadError)
        XCTAssertEqual(
            reopenedStore.tryOnPersonPhotos.map(\.id),
            [firstPhoto.id, sameImageDifferentContext.id, secondPhoto.id]
        )
        XCTAssertEqual(reopenedStore.activeTryOnPhoto?.id, secondPhoto.id)
        XCTAssertEqual(
            try Data(contentsOf: reopenedStore.imageURL(for: firstPhoto)),
            firstPhotoData
        )
        XCTAssertEqual(
            try Data(contentsOf: reopenedStore.imageURL(for: secondPhoto)),
            secondPhotoData
        )
    }

    @MainActor
    func testSavedTryOnKeepsImmutableRailSnapshotsAndPurchaseProvenance() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let shirtProduct = try makeProduct(
            id: "product-shirt",
            title: "Silk Shirt",
            category: "shirt",
            merchant: "Atelier One",
            productURLString: "https://shop.example.com/silk-shirt",
            checkoutURLString: "https://shop.example.com/silk-shirt/buy",
            amount: 148
        )
        let necklaceProduct = try makeProduct(
            id: "product-necklace",
            title: "Pearl Necklace",
            category: "necklace",
            merchant: "Jewels Two",
            productURLString: "https://jewels.example.com/pearl-necklace",
            checkoutURLString: "https://jewels.example.com/pearl-necklace/buy",
            amount: 86
        )
        let store = LibraryStore(rootURL: rootURL)
        let personPhoto = try store.addTryOnPersonPhoto(
            imageData: Data("outfit-person-photo".utf8),
            context: .outfit
        )
        let shirt = try store.addWardrobeItem(
            title: shirtProduct.title,
            category: .clothes,
            imageData: Data("shirt-image".utf8),
            sourceProduct: shirtProduct,
            garmentRegion: .upperBody
        )
        let necklace = try store.addWardrobeItem(
            title: necklaceProduct.title,
            category: .necklace,
            imageData: Data("necklace-image".utf8),
            sourceProduct: necklaceProduct,
            garmentRegion: .accessory
        )
        store.addWardrobeItemToTryOnRail(shirt, selected: true)
        store.addWardrobeItemToTryOnRail(necklace, selected: false)

        let savedSnapshots = store.tryOnItemSnapshots()
        let savedTryOn = try store.addTryOn(
            jobID: "saved-outfit-job",
            title: "Dinner outfit",
            personPhotoID: personPhoto.id,
            photoContext: personPhoto.context,
            gender: .female,
            items: savedSnapshots,
            imageData: Data("rendered-outfit".utf8)
        )

        store.setTryOnRailSelection(shirt.id, isSelected: false)
        store.setTryOnRailSelection(necklace.id, isSelected: true)
        store.removeFromTryOnRail(necklace.id)

        XCTAssertEqual(savedTryOn.items.count, 2)
        XCTAssertEqual(
            savedTryOn.items.first(where: { $0.id == shirt.id })?.wasSelected,
            true
        )
        XCTAssertEqual(
            savedTryOn.items.first(where: { $0.id == necklace.id })?.wasSelected,
            false
        )

        let reopenedStore = LibraryStore(rootURL: rootURL)
        let persistedTryOn = try XCTUnwrap(
            reopenedStore.tryOns.first(where: { $0.id == savedTryOn.id })
        )
        let persistedShirt = try XCTUnwrap(
            persistedTryOn.items.first(where: { $0.id == shirt.id })
        )
        let persistedNecklace = try XCTUnwrap(
            persistedTryOn.items.first(where: { $0.id == necklace.id })
        )

        XCTAssertEqual(persistedTryOn.personPhotoID, personPhoto.id)
        XCTAssertEqual(persistedTryOn.photoContext, .outfit)
        XCTAssertEqual(persistedTryOn.gender, .female)
        XCTAssertTrue(persistedShirt.wasSelected)
        XCTAssertFalse(persistedNecklace.wasSelected)
        XCTAssertEqual(persistedShirt.contentDigest, shirt.contentDigest)
        XCTAssertEqual(persistedNecklace.contentDigest, necklace.contentDigest)
        XCTAssertEqual(persistedShirt.sourceProduct?.merchant, "Atelier One")
        XCTAssertEqual(persistedShirt.sourceProduct?.productURL, shirtProduct.productURL)
        XCTAssertEqual(persistedShirt.sourceProduct?.price?.amount, 148)
        XCTAssertEqual(
            persistedShirt.sourceProduct?.offers.first?.url,
            shirtProduct.offers.first?.url
        )
        XCTAssertEqual(persistedNecklace.sourceProduct?.merchant, "Jewels Two")
        XCTAssertEqual(persistedNecklace.sourceProduct?.productURL, necklaceProduct.productURL)
        XCTAssertEqual(persistedNecklace.sourceProduct?.price?.amount, 86)

        XCTAssertEqual(
            reopenedStore.tryOnRail.first(where: { $0.wardrobeItemID == shirt.id })?.isSelected,
            false
        )
        XCTAssertNil(
            reopenedStore.tryOnRail.first(where: { $0.wardrobeItemID == necklace.id })
        )
    }

    @MainActor
    func testLegacyLibraryAndSavedTryOnDecodeWithWorkflowDefaults() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let legacyLibrary = Data(
            """
            {
              "wardrobeItems": [
                {
                  "id": "BFBCE0A2-249A-4BF5-AB1B-B322A8816D71",
                  "savedAt": "2025-01-02T03:04:05Z",
                  "imageFilename": "legacy-item.jpg",
                  "title": "Legacy shirt",
                  "category": "clothes"
                }
              ],
              "tryOns": [
                {
                  "id": "legacy-job",
                  "createdAt": "2025-01-02T03:04:05Z",
                  "imageFilename": "legacy.jpg",
                  "items": [
                    {
                      "id": "96969112-406F-455F-B5D1-DC5C4BBA4AE8",
                      "title": "Legacy shirt",
                      "category": "clothes",
                      "garmentRegion": "upperBody",
                      "wasSelected": true
                    }
                  ]
                }
              ]
            }
            """.utf8
        )
        try legacyLibrary.write(
            to: rootURL.appending(path: "library.json"),
            options: .atomic
        )

        let store = LibraryStore(rootURL: rootURL)
        let legacyTryOn = try XCTUnwrap(store.tryOns.first)
        let legacyWardrobeItem = try XCTUnwrap(store.wardrobeItems.first)

        XCTAssertNil(store.loadError)
        XCTAssertNil(legacyWardrobeItem.sourceScanID)
        XCTAssertNil(legacyWardrobeItem.sourceGarmentID)
        XCTAssertNil(legacyWardrobeItem.contentDigest)
        XCTAssertNil(legacyWardrobeItem.garmentRegion)
        XCTAssertNil(legacyWardrobeItem.tryOnReferenceFilename)
        XCTAssertNil(legacyWardrobeItem.tryOnReferenceDigest)
        XCTAssertTrue(store.tryOnRail.isEmpty)
        XCTAssertTrue(store.tryOnPersonPhotos.isEmpty)
        XCTAssertNil(store.activeTryOnPhoto)
        XCTAssertEqual(legacyTryOn.items.count, 1)
        XCTAssertNil(legacyTryOn.items.first?.contentDigest)
        XCTAssertNil(legacyTryOn.items.first?.referenceContentDigest)
        XCTAssertNil(legacyTryOn.personPhotoID)
        XCTAssertNil(legacyTryOn.photoContext)
        XCTAssertNil(legacyTryOn.gender)
    }

    @MainActor
    func testLegacyWardrobeMediaBackfillsDigestInNewRenderSnapshots() throws {
        let rootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let wardrobeURL = rootURL.appending(path: "Wardrobe", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: wardrobeURL, withIntermediateDirectories: true)
        let legacyImageData = Data("legacy-wardrobe-image".utf8)
        try legacyImageData.write(to: wardrobeURL.appending(path: "legacy-item.jpg"))
        let legacyLibrary = Data(
            """
            {
              "wardrobeItems": [
                {
                  "id": "BFBCE0A2-249A-4BF5-AB1B-B322A8816D71",
                  "savedAt": "2025-01-02T03:04:05Z",
                  "imageFilename": "legacy-item.jpg",
                  "title": "Legacy shirt",
                  "category": "clothes"
                }
              ],
              "tryOnRail": [
                {
                  "wardrobeItemID": "BFBCE0A2-249A-4BF5-AB1B-B322A8816D71",
                  "isSelected": true,
                  "addedAt": "2025-01-02T03:04:05Z"
                }
              ]
            }
            """.utf8
        )
        try legacyLibrary.write(
            to: rootURL.appending(path: "library.json"),
            options: .atomic
        )

        let store = LibraryStore(rootURL: rootURL)
        let legacyItem = try XCTUnwrap(store.wardrobeItems.first)
        let snapshot = try XCTUnwrap(store.tryOnItemSnapshots().first)
        let trayItem = try XCTUnwrap(store.tryOnTrayItems().first)

        XCTAssertNil(legacyItem.contentDigest)
        XCTAssertNotNil(snapshot.contentDigest)
        XCTAssertEqual(snapshot.contentDigest, trayItem.contentDigest)
    }

    private func makeTemporaryRootURL() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "Stylezam-TryOnWorkflowTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        return rootURL
    }

    private func makeProduct(
        id: String,
        title: String,
        category: String,
        merchant: String,
        productURLString: String,
        checkoutURLString: String,
        amount: Double
    ) throws -> ProductResultDTO {
        let productURL = try XCTUnwrap(URL(string: productURLString))
        let checkoutURL = try XCTUnwrap(URL(string: checkoutURLString))
        let price = MoneyDTO(amount: amount, currency: "USD", display: nil)

        return ProductResultDTO(
            id: id,
            searchID: "search-\(id)",
            provider: "test-catalog",
            providerResultID: "provider-\(id)",
            title: title,
            brand: merchant,
            category: category,
            color: nil,
            imageURL: nil,
            productURL: productURL,
            merchant: merchant,
            price: price,
            matchTier: .exact,
            score: 1,
            rating: 4.8,
            reviewCount: 42,
            attributes: ["purchaseSource": .string("scraped")],
            offers: [
                MerchantOfferDTO(
                    merchant: merchant,
                    url: checkoutURL,
                    price: price,
                    shipping: "Free",
                    condition: "New"
                )
            ]
        )
    }
}
