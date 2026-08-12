import Foundation
import CryptoKit
import Observation

private enum LibraryStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The existing Library could not be loaded, so Stylezam stopped this write to protect its data."
    }
}

private final class CachedTryOnMedia {
    let imageFilename: String
    let referenceFilename: String?
    let imageData: Data
    let referenceData: Data?

    init(
        imageFilename: String,
        referenceFilename: String?,
        imageData: Data,
        referenceData: Data?
    ) {
        self.imageFilename = imageFilename
        self.referenceFilename = referenceFilename
        self.imageData = imageData
        self.referenceData = referenceData
    }

    var memoryCost: Int {
        imageData.count + (referenceData?.count ?? 0)
    }
}

@MainActor
@Observable
final class LibraryStore {
    private(set) var snapshot = LibrarySnapshot()
    private(set) var loadError: String?

    private let rootURL: URL
    private let capturesURL: URL
    private let garmentsURL: URL
    private let tryOnsURL: URL
    private let wardrobeURL: URL
    private let tryOnPeopleURL: URL
    private let snapshotURL: URL
    private var acceptsWrites = true
    private let tryOnMediaCache: NSCache<NSUUID, CachedTryOnMedia> = {
        let cache = NSCache<NSUUID, CachedTryOnMedia>()
        cache.countLimit = 12
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    init(rootURL overrideRootURL: URL? = nil) {
        let fallback = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        rootURL = overrideRootURL ?? (StylezamShared.containerURL ?? fallback)
            .appending(path: "Stylezam", directoryHint: .isDirectory)
        capturesURL = rootURL.appending(path: "Captures", directoryHint: .isDirectory)
        garmentsURL = rootURL.appending(path: "Garments", directoryHint: .isDirectory)
        tryOnsURL = rootURL.appending(path: "TryOns", directoryHint: .isDirectory)
        wardrobeURL = rootURL.appending(path: "Wardrobe", directoryHint: .isDirectory)
        tryOnPeopleURL = rootURL.appending(path: "TryOnPeople", directoryHint: .isDirectory)
        snapshotURL = rootURL.appending(path: "library.json")
        do {
            try FileManager.default.createDirectory(
                at: capturesURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: tryOnsURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: garmentsURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: wardrobeURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: tryOnPeopleURL, withIntermediateDirectories: true)
            try load()
        } catch {
            acceptsWrites = false
            loadError = error.localizedDescription
        }
    }

    var scans: [SavedScan] { snapshot.scans }
    var captures: [SavedCapture] { snapshot.captures }
    var searches: [SavedProductSearch] { snapshot.searches }
    var chats: [StylezamChatThread] { snapshot.chats }
    var products: [SavedProduct] { snapshot.products }
    var wardrobeItems: [SavedWardrobeItem] { snapshot.wardrobeItems }
    var tryOns: [SavedTryOn] { snapshot.tryOns }
    var tryOnRail: [TryOnRailEntry] { snapshot.tryOnRail }
    var tryOnPersonPhotos: [SavedTryOnPersonPhoto] { snapshot.tryOnPersonPhotos }

    var activeTryOnPhoto: SavedTryOnPersonPhoto? {
        guard let id = snapshot.activeTryOnPhotoID else {
            return snapshot.tryOnPersonPhotos.first
        }
        return snapshot.tryOnPersonPhotos.first(where: { $0.id == id })
            ?? snapshot.tryOnPersonPhotos.first
    }

    @discardableResult
    func addScan(
        imageData: Data,
        origin: CaptureOrigin,
        mode: CaptureMode,
        detection: GarmentDetectionBatch,
        visualFingerprints: [String: GarmentVisualFingerprint] = [:]
    ) throws -> SavedScan {
        let previousSnapshot = snapshot
        let id = UUID()
        // Screen scans use the first segmented garment as their Library cover when one is
        // available. Keep the extension truthful so image consumers preserve transparency.
        let screenCoverIsSegmented = mode == .screen && detection.candidates.first?.cropData != nil
        let imageFilename = "\(id.uuidString).\(screenCoverIsSegmented ? "png" : "jpg")"
        var createdURLs: [URL] = []

        do {
            let captureURL = capturesURL.appending(path: imageFilename)
            createdURLs.append(captureURL)
            // A full-display frame can contain private browser/app chrome and the Dynamic Island.
            // Keep only the first confirmed garment crop as the screen scan's Library cover. All
            // detected garments are still written individually below.
            let storedCaptureData = mode == .screen
                ? detection.candidates.first?.cropData
                    ?? detection.candidates.first?.boxCropData
                    ?? imageData
                : imageData
            try storedCaptureData.write(to: captureURL, options: .atomic)

            let items = try detection.candidates.map { candidate in
                var cropFilename: String?
                // A valid transparent segmentation is the product artwork. The rectangular
                // crop remains the fallback when a model mask is too weak or covers all pixels.
                let preferredCrop = candidate.cropData ?? candidate.boxCropData
                if let cropData = preferredCrop {
                    let fileExtension = candidate.cropData != nil ? "png" : "jpg"
                    let filename = "\(id.uuidString)-\(candidate.id).\(fileExtension)"
                    let destination = garmentsURL.appending(path: filename)
                    createdURLs.append(destination)
                    try cropData.write(to: destination, options: .atomic)
                    cropFilename = filename
                }
                return SavedGarment(
                    id: candidate.id,
                    cropFilename: cropFilename,
                    localLabel: candidate.localLabel,
                    localConfidence: candidate.confidence,
                    box: candidate.box,
                    accepted: true,
                    category: nil,
                    displayName: nil,
                    brand: nil,
                    colors: [],
                    materials: [],
                    patterns: [],
                    details: [],
                    visibleText: [],
                    perceptualHash: visualFingerprints[candidate.id]?.perceptualHash,
                    featurePrintData: visualFingerprints[candidate.id]?.featurePrintData
                )
            }
            let scan = SavedScan(
                id: id,
                createdAt: .now,
                imageFilename: imageFilename,
                origin: origin,
                mode: mode,
                detectionMethod: detection.method,
                visionMetrics: detection.metrics,
                labelState: .local,
                items: items
            )
            snapshot.scans.insert(scan, at: 0)
            try persist()
            return scan
        } catch {
            snapshot = previousSnapshot
            for url in createdURLs {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
    }

    func imageURL(for scan: SavedScan) -> URL {
        capturesURL.appending(path: scan.imageFilename)
    }

    /// Crop-first artwork for Library and Home. Existing full-screen captures are also presented
    /// using their first saved garment, so old entries no longer show app chrome.
    func displayImageURL(for scan: SavedScan) -> URL {
        if let first = scan.items.first(where: { $0.accepted }),
           let crop = cropURL(for: first)
        {
            return crop
        }
        return imageURL(for: scan)
    }

    func cropURL(for item: SavedGarment) -> URL? {
        guard let filename = item.cropFilename else { return nil }
        return garmentsURL.appending(path: filename)
    }

    func garmentFingerprintSources(limit: Int = 1_200) -> [GarmentFingerprintSource] {
        var values: [GarmentFingerprintSource] = []
        for scan in snapshot.scans {
            for item in scan.items {
                // New entries seed from their tiny stored signatures without loading large crop
                // files. Crop bytes are read only once for Library items created before durable
                // signatures shipped.
                let needsLegacySignature = item.featurePrintData == nil
                    && item.perceptualHash == nil
                let data = needsLegacySignature
                    ? cropURL(for: item).flatMap { try? Data(contentsOf: $0) }
                    : nil
                guard data != nil || item.featurePrintData != nil || item.perceptualHash != nil else {
                    continue
                }
                values.append(
                    GarmentFingerprintSource(
                        id: "\(scan.id.uuidString):\(item.id)",
                        label: item.localLabel,
                        data: data,
                        perceptualHash: item.perceptualHash,
                        featurePrintData: item.featurePrintData
                    )
                )
                if values.count == limit { return values }
            }
        }
        return values
    }

    @discardableResult
    func addCapture(input: SearchInput, searchID: String) throws -> SavedCapture {
        let id = UUID()
        var filename: String?
        if let imageData = input.imageData {
            filename = "\(id.uuidString).jpg"
            try imageData.write(
                to: capturesURL.appending(path: filename!),
                options: .atomic
            )
        }
        let capture = SavedCapture(
            id: id,
            createdAt: .now,
            imageFilename: filename,
            query: input.query,
            origin: input.origin,
            searchID: searchID
        )
        snapshot.captures.insert(capture, at: 0)
        snapshot.captures = Array(snapshot.captures.prefix(60))
        try persist()
        return capture
    }

    func imageURL(for capture: SavedCapture) -> URL? {
        guard let filename = capture.imageFilename else { return nil }
        return capturesURL.appending(path: filename)
    }

    func search(for garmentKey: String) -> SavedProductSearch? {
        snapshot.searches.first { $0.garmentKey == garmentKey }
    }

    func chatMessages(for garmentKey: String) -> [StylezamChatMessage] {
        snapshot.chats.first { $0.id == garmentKey }?.messages ?? []
    }

    func appendChatMessages(
        _ messages: [StylezamChatMessage],
        garmentKey: String,
        scanID: UUID,
        garmentID: String
    ) throws {
        guard !messages.isEmpty else { return }
        let previousSnapshot = snapshot
        if let index = snapshot.chats.firstIndex(where: { $0.id == garmentKey }) {
            snapshot.chats[index].messages.append(contentsOf: messages)
            snapshot.chats[index].messages = Array(snapshot.chats[index].messages.suffix(60))
            snapshot.chats[index].updatedAt = .now
            let updated = snapshot.chats.remove(at: index)
            snapshot.chats.insert(updated, at: 0)
        } else {
            snapshot.chats.insert(
                StylezamChatThread(
                    id: garmentKey,
                    scanID: scanID,
                    garmentID: garmentID,
                    messages: Array(messages.suffix(60)),
                    updatedAt: .now
                ),
                at: 0
            )
        }
        snapshot.chats = Array(snapshot.chats.prefix(80))
        do {
            try persist()
        } catch {
            snapshot = previousSnapshot
            throw error
        }
    }

    func clearChat(for garmentKey: String) {
        let previousSnapshot = snapshot
        snapshot.chats.removeAll { $0.id == garmentKey }
        do {
            try persist()
        } catch {
            snapshot = previousSnapshot
            loadError = error.localizedDescription
        }
    }

    func saveSearch(_ search: SavedProductSearch) throws {
        let previousSnapshot = snapshot
        snapshot.searches.removeAll { $0.id == search.id || $0.garmentKey == search.garmentKey }
        snapshot.searches.insert(search, at: 0)
        snapshot.searches = Array(snapshot.searches.prefix(120))
        do {
            try persist()
        } catch {
            snapshot = previousSnapshot
            throw error
        }
    }

    func applyUnderstanding(
        _ understanding: GarmentUnderstanding,
        scanID: UUID,
        garmentID: String
    ) {
        guard let scanIndex = snapshot.scans.firstIndex(where: { $0.id == scanID }),
              let itemIndex = snapshot.scans[scanIndex].items.firstIndex(where: { $0.id == garmentID })
        else { return }
        snapshot.scans[scanIndex].items[itemIndex].displayName = understanding.summary
        snapshot.scans[scanIndex].items[itemIndex].category = understanding.category
        snapshot.scans[scanIndex].items[itemIndex].colors = understanding.colors
        snapshot.scans[scanIndex].items[itemIndex].materials = understanding.materials
        snapshot.scans[scanIndex].items[itemIndex].patterns = understanding.patterns
        snapshot.scans[scanIndex].labelState = .enriched
        do { try persist() } catch { loadError = error.localizedDescription }
    }

    /// Records a human correction while preserving the detector's original label and score for
    /// Developer Inspector. Existing search and try-on derivatives are invalidated so an old,
    /// incorrect category cannot survive after the source item has been corrected or rejected.
    @discardableResult
    func applyDetectionCorrection(
        _ correction: GarmentDetectionCorrection,
        scanID: UUID,
        garmentID: String
    ) throws -> SavedGarment {
        guard let scanIndex = snapshot.scans.firstIndex(where: { $0.id == scanID }),
              let itemIndex = snapshot.scans[scanIndex].items.firstIndex(where: {
                  $0.id == garmentID
              })
        else {
            throw LibraryStoreError.unavailable
        }

        let previous = snapshot
        let derivedWardrobe = snapshot.wardrobeItems.filter {
            $0.sourceScanID == scanID && $0.sourceGarmentID == garmentID
        }
        let derivedWardrobeIDs = Set(derivedWardrobe.map(\.id))

        switch correction {
        case .notFashion:
            snapshot.scans[scanIndex].items[itemIndex].accepted = false
            snapshot.scans[scanIndex].items[itemIndex].reviewState = .rejected
        case let .fashion(category, label):
            snapshot.scans[scanIndex].items[itemIndex].accepted = true
            snapshot.scans[scanIndex].items[itemIndex].reviewState = .confirmed
            snapshot.scans[scanIndex].items[itemIndex].category = category.rawValue
            snapshot.scans[scanIndex].items[itemIndex].displayName = label
        }

        snapshot.searches.removeAll { $0.scanID == scanID && $0.garmentID == garmentID }
        snapshot.chats.removeAll { $0.scanID == scanID && $0.garmentID == garmentID }
        snapshot.wardrobeItems.removeAll { derivedWardrobeIDs.contains($0.id) }
        snapshot.tryOnRail.removeAll { derivedWardrobeIDs.contains($0.wardrobeItemID) }

        do {
            try persist()
            for item in derivedWardrobe {
                removeWardrobeFiles(for: item)
                tryOnMediaCache.removeObject(forKey: item.id as NSUUID)
            }
            return snapshot.scans[scanIndex].items[itemIndex]
        } catch {
            snapshot = previous
            throw error
        }
    }

    func deleteSearch(_ search: SavedProductSearch) {
        snapshot.searches.removeAll { $0.id == search.id }
        do { try persist() } catch { loadError = error.localizedDescription }
    }

    func imageURL(for tryOn: SavedTryOn) -> URL {
        tryOnsURL.appending(path: tryOn.imageFilename)
    }

    func imageURL(for item: SavedWardrobeItem) -> URL {
        wardrobeURL.appending(path: item.imageFilename)
    }

    func tryOnReferenceURL(for item: SavedWardrobeItem) -> URL? {
        guard let filename = item.tryOnReferenceFilename else { return nil }
        return wardrobeURL.appending(path: filename)
    }

    func imageURL(for photo: SavedTryOnPersonPhoto) -> URL {
        tryOnPeopleURL.appending(path: photo.imageFilename)
    }

    func wardrobeItem(for id: UUID) -> SavedWardrobeItem? {
        snapshot.wardrobeItems.first { $0.id == id }
    }

    func tryOnTrayItems() -> [TryOnTrayItem] {
        snapshot.tryOnRail.compactMap { entry in
            guard let item = wardrobeItem(for: entry.wardrobeItemID),
                  let media = cachedTryOnMedia(for: item)
            else { return nil }
            return TryOnTrayItem(
                id: item.id,
                title: item.title,
                category: item.category,
                region: item.garmentRegion,
                imageData: media.imageData,
                referenceImageData: media.referenceData,
                isSelected: entry.isSelected,
                sourceProduct: item.sourceProduct,
                sourceWardrobeID: item.id,
                contentDigest: item.contentDigest ?? Self.digest(for: media.imageData),
                referenceContentDigest: item.tryOnReferenceDigest
                    ?? media.referenceData.map { Self.digest(for: $0) }
            )
        }
    }

    func tryOnItemSnapshots(
        appliedItemIDs: Set<UUID>? = nil
    ) -> [SavedTryOnItemSnapshot] {
        snapshot.tryOnRail.compactMap { entry in
            guard let item = wardrobeItem(for: entry.wardrobeItemID) else { return nil }
            let contentDigest = item.contentDigest
                ?? (try? Data(contentsOf: imageURL(for: item))).map { Self.digest(for: $0) }
            let referenceContentDigest = item.tryOnReferenceDigest
                ?? tryOnReferenceURL(for: item)
                    .flatMap { try? Data(contentsOf: $0) }
                    .map { Self.digest(for: $0) }
            return SavedTryOnItemSnapshot(
                id: item.id,
                title: item.title,
                category: item.category,
                garmentRegion: item.garmentRegion ?? .infer(category: item.category, title: item.title),
                wasSelected: appliedItemIDs?.contains(item.id) ?? entry.isSelected,
                sourceProduct: item.sourceProduct,
                contentDigest: contentDigest,
                referenceContentDigest: referenceContentDigest
            )
        }
    }

    @discardableResult
    func addTryOnPersonPhoto(
        imageData: Data,
        context: TryOnPhotoContext
    ) throws -> SavedTryOnPersonPhoto {
        let previous = snapshot
        let digest = Self.digest(for: imageData)
        if let index = snapshot.tryOnPersonPhotos.firstIndex(where: {
            $0.contentDigest == digest && $0.context == context
        }) {
            let existing = snapshot.tryOnPersonPhotos.remove(at: index)
            snapshot.tryOnPersonPhotos.insert(existing, at: 0)
            snapshot.activeTryOnPhotoID = existing.id
            do {
                try persist()
                return existing
            } catch {
                snapshot = previous
                throw error
            }
        }

        let id = UUID()
        let ext = imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
        let filename = "\(id.uuidString).\(ext)"
        let url = tryOnPeopleURL.appending(path: filename)
        try imageData.write(to: url, options: .atomic)
        let photo = SavedTryOnPersonPhoto(
            id: id,
            createdAt: .now,
            imageFilename: filename,
            context: context,
            contentDigest: digest,
            inferredGender: nil
        )
        snapshot.tryOnPersonPhotos.insert(photo, at: 0)
        snapshot.activeTryOnPhotoID = photo.id
        let removed = Array(snapshot.tryOnPersonPhotos.dropFirst(12))
        snapshot.tryOnPersonPhotos = Array(snapshot.tryOnPersonPhotos.prefix(12))
        do {
            try persist()
            for old in removed {
                try? FileManager.default.removeItem(at: imageURL(for: old))
            }
            return photo
        } catch {
            snapshot = previous
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func setActiveTryOnPhoto(_ photo: SavedTryOnPersonPhoto) {
        guard snapshot.tryOnPersonPhotos.contains(where: { $0.id == photo.id }) else { return }
        let previous = snapshot
        snapshot.activeTryOnPhotoID = photo.id
        do {
            try persist()
        } catch {
            snapshot = previous
            loadError = error.localizedDescription
        }
    }

    func setInferredTryOnGender(_ gender: TryOnGender, for photoID: UUID) throws {
        guard gender.isProviderValue,
              let index = snapshot.tryOnPersonPhotos.firstIndex(where: { $0.id == photoID })
        else { return }
        let previous = snapshot
        snapshot.tryOnPersonPhotos[index].inferredGender = gender
        do {
            try persist()
        } catch {
            snapshot = previous
            throw error
        }
    }

    func deleteTryOnPersonPhoto(_ photo: SavedTryOnPersonPhoto) {
        let previous = snapshot
        snapshot.tryOnPersonPhotos.removeAll { $0.id == photo.id }
        if snapshot.activeTryOnPhotoID == photo.id {
            snapshot.activeTryOnPhotoID = snapshot.tryOnPersonPhotos.first?.id
        }
        do {
            try persist()
            try? FileManager.default.removeItem(at: imageURL(for: photo))
        } catch {
            snapshot = previous
            loadError = error.localizedDescription
        }
    }

    func addWardrobeItemToTryOnRail(_ item: SavedWardrobeItem, selected: Bool = true) {
        let previous = snapshot
        if let index = snapshot.tryOnRail.firstIndex(where: { $0.wardrobeItemID == item.id }) {
            snapshot.tryOnRail[index].isSelected = selected
            snapshot.tryOnRail[index].addedAt = .now
            let entry = snapshot.tryOnRail.remove(at: index)
            snapshot.tryOnRail.insert(entry, at: 0)
        } else {
            snapshot.tryOnRail.insert(
                TryOnRailEntry(wardrobeItemID: item.id, isSelected: selected, addedAt: .now),
                at: 0
            )
        }
        do {
            try persist()
        } catch {
            snapshot = previous
            loadError = error.localizedDescription
        }
    }

    func setTryOnRailSelection(_ itemID: UUID, isSelected: Bool) {
        guard let index = snapshot.tryOnRail.firstIndex(where: { $0.wardrobeItemID == itemID }) else { return }
        let previous = snapshot
        snapshot.tryOnRail[index].isSelected = isSelected
        do {
            try persist()
        } catch {
            snapshot = previous
            loadError = error.localizedDescription
        }
    }

    func removeFromTryOnRail(_ itemID: UUID) {
        let previous = snapshot
        snapshot.tryOnRail.removeAll { $0.wardrobeItemID == itemID }
        do {
            try persist()
        } catch {
            snapshot = previous
            loadError = error.localizedDescription
        }
    }

    @discardableResult
    func addWardrobeItem(
        title: String,
        category: TryOnCategory,
        imageData: Data,
        tryOnReferenceData: Data? = nil,
        sourceProduct: ProductResultDTO? = nil,
        sourceScanID: UUID? = nil,
        sourceGarmentID: String? = nil,
        garmentRegion: TryOnGarmentRegion? = nil
    ) throws -> SavedWardrobeItem {
        let digest = Self.digest(for: imageData)
        if let sourceScanID, let sourceGarmentID {
            if let existingIndex = snapshot.wardrobeItems.firstIndex(where: { item in
                item.sourceScanID == sourceScanID && item.sourceGarmentID == sourceGarmentID
            }) {
                if let tryOnReferenceData {
                    return try attachTryOnReferenceIfNeeded(
                        at: existingIndex,
                        data: tryOnReferenceData
                    )
                }
                return snapshot.wardrobeItems[existingIndex]
            }
        } else if sourceScanID == nil, sourceGarmentID == nil {
            if let existingIndex = snapshot.wardrobeItems.firstIndex(where: { item in
                guard item.sourceScanID == nil, item.sourceGarmentID == nil else { return false }
                if let productID = sourceProduct?.id, item.sourceProduct?.id == productID {
                    return true
                }
                return item.contentDigest == digest && item.category == category
            }) {
                if let tryOnReferenceData {
                    return try attachTryOnReferenceIfNeeded(
                        at: existingIndex,
                        data: tryOnReferenceData
                    )
                }
                return snapshot.wardrobeItems[existingIndex]
            }
        }

        let previous = snapshot
        let id = UUID()
        let ext = Self.fileExtension(for: imageData)
        let filename = "\(id.uuidString).\(ext)"
        let url = wardrobeURL.appending(path: filename)
        try imageData.write(to: url, options: .atomic)
        var createdURLs = [url]
        let referenceFilename: String?
        let referenceDigest: String?
        if let tryOnReferenceData {
            let reference = Self.contentAddressedTryOnReference(for: tryOnReferenceData)
            let referenceURL = wardrobeURL.appending(path: reference.filename)
            do {
                if !FileManager.default.fileExists(atPath: referenceURL.path) {
                    try tryOnReferenceData.write(to: referenceURL, options: .atomic)
                    createdURLs.append(referenceURL)
                }
                referenceFilename = reference.filename
                referenceDigest = reference.digest
            } catch {
                for createdURL in createdURLs {
                    try? FileManager.default.removeItem(at: createdURL)
                }
                throw error
            }
        } else {
            referenceFilename = nil
            referenceDigest = nil
        }
        let item = SavedWardrobeItem(
            id: id,
            savedAt: .now,
            imageFilename: filename,
            title: title,
            category: category,
            sourceProduct: sourceProduct,
            sourceScanID: sourceScanID,
            sourceGarmentID: sourceGarmentID,
            contentDigest: digest,
            garmentRegion: garmentRegion ?? .infer(category: category, title: title),
            tryOnReferenceFilename: referenceFilename,
            tryOnReferenceDigest: referenceDigest
        )
        snapshot.wardrobeItems.insert(item, at: 0)
        let removed = Array(snapshot.wardrobeItems.dropFirst(100))
        snapshot.wardrobeItems = Array(snapshot.wardrobeItems.prefix(100))
        let removedIDs = Set(removed.map(\.id))
        snapshot.tryOnRail.removeAll { removedIDs.contains($0.wardrobeItemID) }
        do {
            try persist()
            for old in removed { removeWardrobeFiles(for: old) }
            return item
        } catch {
            snapshot = previous
            for createdURL in createdURLs {
                try? FileManager.default.removeItem(at: createdURL)
            }
            throw error
        }
    }

    @discardableResult
    func addDetectedGarmentToTryOnRail(
        scanID: UUID,
        garmentID: String,
        sourceFrameData: Data? = nil,
        activate: Bool = true
    ) throws -> SavedWardrobeItem? {
        guard let scan = snapshot.scans.first(where: { $0.id == scanID }),
              let garment = scan.items.first(where: {
                  $0.id == garmentID && $0.isPipelineEligible
              }),
              let cropURL = cropURL(for: garment),
              let data = try? Data(contentsOf: cropURL)
        else { return nil }
        let category = TryOnCategory.infer(category: garment.category, title: garment.title)
        // A human correction intentionally replaces the detector's display label. Use that
        // corrected title for YouCam's garment region as well; otherwise correcting a white
        // T-shirt that was detected as a jacket would still send `outer` to Clothes V4.
        let region = TryOnGarmentRegion.infer(category: category, title: garment.title)
        let referenceData: Data?
        if region == .lowerBody {
            // This is a best-effort candidate for YouCam's worn-garment input.
            // Detection identifies the item region, but cannot prove that a web
            // frame or photo actually shows the garment worn by one clear person.
            // Screen scans intentionally keep only a crop as their Library cover,
            // so their full frame must be handed off during the capture transaction.
            if let sourceFrameData {
                referenceData = sourceFrameData
            } else if scan.mode == .screen {
                referenceData = nil
            } else {
                referenceData = try? Data(contentsOf: imageURL(for: scan))
            }
        } else {
            referenceData = nil
        }
        let item = try addWardrobeItem(
            title: garment.title,
            category: category,
            imageData: data,
            tryOnReferenceData: referenceData,
            sourceScanID: scanID,
            sourceGarmentID: garmentID,
            garmentRegion: region
        )
        let snapshotBeforeRailUpdate = snapshot
        upsertRailEntry(
            for: item.id,
            selected: activate,
            preserveExistingSelection: !activate
        )
        do {
            try persist()
        } catch {
            snapshot = snapshotBeforeRailUpdate
            loadError = error.localizedDescription
        }
        return item
    }

    @discardableResult
    func setLowerBodyTryOnReference(
        for itemID: UUID,
        imageData: Data
    ) throws -> SavedWardrobeItem? {
        guard let index = snapshot.wardrobeItems.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }
        let item = snapshot.wardrobeItems[index]
        let region = item.garmentRegion
            ?? .infer(category: item.category, title: item.title)
        guard region == .lowerBody else { return nil }
        return try attachTryOnReferenceIfNeeded(
            at: index,
            data: imageData,
            replacingExisting: true
        )
    }

    @discardableResult
    func enrichSourceWardrobeItemInTryOnRail(
        _ product: ProductResultDTO,
        sourceScanID: UUID,
        sourceGarmentID: String,
        activate: Bool = true
    ) throws -> SavedWardrobeItem? {
        guard let index = snapshot.wardrobeItems.firstIndex(where: { item in
            item.sourceScanID == sourceScanID && item.sourceGarmentID == sourceGarmentID
        }) else { return nil }

        let previous = snapshot
        let existing = snapshot.wardrobeItems[index]
        let enriched = SavedWardrobeItem(
            id: existing.id,
            savedAt: existing.savedAt,
            imageFilename: existing.imageFilename,
            title: product.title,
            category: existing.category,
            sourceProduct: product,
            sourceScanID: existing.sourceScanID,
            sourceGarmentID: existing.sourceGarmentID,
            contentDigest: existing.contentDigest,
            garmentRegion: existing.garmentRegion,
            tryOnReferenceFilename: existing.tryOnReferenceFilename,
            tryOnReferenceDigest: existing.tryOnReferenceDigest
        )
        snapshot.wardrobeItems[index] = enriched
        upsertRailEntry(
            for: enriched.id,
            selected: activate,
            preserveExistingSelection: !activate
        )
        do {
            try persist()
            return enriched
        } catch {
            snapshot = previous
            throw error
        }
    }

    @discardableResult
    func upsertProductInTryOnRail(
        _ product: ProductResultDTO,
        imageData: Data,
        sourceScanID: UUID? = nil,
        sourceGarmentID: String? = nil,
        activate: Bool = true
    ) throws -> SavedWardrobeItem {
        if let sourceScanID, let sourceGarmentID,
           let enriched = try enrichSourceWardrobeItemInTryOnRail(
               product,
               sourceScanID: sourceScanID,
               sourceGarmentID: sourceGarmentID,
               activate: activate
           )
        {
            return enriched
        }

        let category = TryOnCategory.infer(category: product.category, title: product.title)
        let region = TryOnGarmentRegion.infer(
            category: category,
            title: product.category ?? product.title
        )
        let exactSourceIndex: Int?
        if let sourceScanID, let sourceGarmentID {
            exactSourceIndex = snapshot.wardrobeItems.firstIndex { item in
                item.sourceScanID == sourceScanID && item.sourceGarmentID == sourceGarmentID
            }
        } else {
            exactSourceIndex = nil
        }
        let productIndex = snapshot.wardrobeItems.firstIndex { item in
            item.sourceScanID == nil
                && item.sourceGarmentID == nil
                && item.sourceProduct?.id == product.id
        }
        let hasExactSourceIdentity = sourceScanID != nil && sourceGarmentID != nil
        let existingIndex = hasExactSourceIdentity ? exactSourceIndex : productIndex

        if let existingIndex {
            let previous = snapshot
            let existing = snapshot.wardrobeItems[existingIndex]
            let preservesExactSource: Bool
            if let sourceScanID, let sourceGarmentID {
                preservesExactSource = existing.sourceScanID == sourceScanID
                    && existing.sourceGarmentID == sourceGarmentID
            } else {
                preservesExactSource = false
            }
            let url = imageURL(for: existing)
            let previousData = try? Data(contentsOf: url)
            if !preservesExactSource {
                try imageData.write(to: url, options: .atomic)
            }
            let updated = SavedWardrobeItem(
                id: existing.id,
                savedAt: existing.savedAt,
                imageFilename: existing.imageFilename,
                title: product.title,
                category: preservesExactSource ? existing.category : category,
                sourceProduct: product,
                sourceScanID: sourceScanID ?? existing.sourceScanID,
                sourceGarmentID: sourceGarmentID ?? existing.sourceGarmentID,
                contentDigest: preservesExactSource
                    ? existing.contentDigest ?? previousData.map { Self.digest(for: $0) }
                    : Self.digest(for: imageData),
                garmentRegion: preservesExactSource ? existing.garmentRegion : region,
                tryOnReferenceFilename: existing.tryOnReferenceFilename,
                tryOnReferenceDigest: existing.tryOnReferenceDigest
            )
            snapshot.wardrobeItems[existingIndex] = updated
            upsertRailEntry(
                for: updated.id,
                selected: activate,
                preserveExistingSelection: !activate
            )
            do {
                try persist()
                tryOnMediaCache.removeObject(forKey: existing.id as NSUUID)
                return updated
            } catch {
                snapshot = previous
                if !preservesExactSource, let previousData {
                    try? previousData.write(to: url, options: .atomic)
                }
                throw error
            }
        }

        let item = try addWardrobeItem(
            title: product.title,
            category: category,
            imageData: imageData,
            sourceProduct: product,
            sourceScanID: sourceScanID,
            sourceGarmentID: sourceGarmentID,
            garmentRegion: region
        )
        if activate {
            addWardrobeItemToTryOnRail(item, selected: true)
        } else {
            let snapshotBeforeRailUpdate = snapshot
            upsertRailEntry(
                for: item.id,
                selected: false,
                preserveExistingSelection: true
            )
            do {
                try persist()
            } catch {
                snapshot = snapshotBeforeRailUpdate
                throw error
            }
        }
        return item
    }

    func deleteWardrobeItem(_ item: SavedWardrobeItem) {
        let previous = snapshot
        snapshot.wardrobeItems.removeAll { $0.id == item.id }
        snapshot.tryOnRail.removeAll { $0.wardrobeItemID == item.id }
        do {
            try persist()
            removeWardrobeFiles(for: item)
        } catch {
            snapshot = previous
            loadError = error.localizedDescription
        }
    }

    @discardableResult
    func addTryOn(
        jobID: String,
        product: ProductResultDTO? = nil,
        title: String? = nil,
        personPhotoID: UUID? = nil,
        photoContext: TryOnPhotoContext? = nil,
        gender: TryOnGender? = nil,
        items: [SavedTryOnItemSnapshot] = [],
        imageData: Data
    ) throws -> SavedTryOn {
        if let existing = snapshot.tryOns.first(where: { $0.id == jobID }) {
            let existingURL = imageURL(for: existing)
            if !FileManager.default.fileExists(atPath: existingURL.path) {
                try imageData.write(to: existingURL, options: .atomic)
            }
            return existing
        }
        let previous = snapshot
        let ext = imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = tryOnsURL.appending(path: filename)
        try imageData.write(
            to: destination,
            options: .atomic
        )
        let tryOn = SavedTryOn(
            id: jobID,
            createdAt: .now,
            imageFilename: filename,
            product: product,
            title: title,
            personPhotoID: personPhotoID,
            photoContext: photoContext,
            gender: gender,
            items: items
        )
        snapshot.tryOns.insert(tryOn, at: 0)
        let removed = Array(snapshot.tryOns.dropFirst(60))
        snapshot.tryOns = Array(snapshot.tryOns.prefix(60))
        do {
            try persist()
            for old in removed { try? FileManager.default.removeItem(at: imageURL(for: old)) }
            return tryOn
        } catch {
            snapshot = previous
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func deleteTryOn(_ tryOn: SavedTryOn) {
        let previous = snapshot
        snapshot.tryOns.removeAll { $0.id == tryOn.id }
        do {
            try persist()
            try? FileManager.default.removeItem(at: imageURL(for: tryOn))
        } catch {
            snapshot = previous
            loadError = error.localizedDescription
        }
    }

    func isSaved(_ product: ProductResultDTO) -> Bool {
        snapshot.products.contains { $0.id == product.id }
    }

    func toggleSaved(_ product: ProductResultDTO) {
        if let index = snapshot.products.firstIndex(where: { $0.id == product.id }) {
            snapshot.products.remove(at: index)
        } else {
            snapshot.products.insert(
                SavedProduct(id: product.id, savedAt: .now, product: product),
                at: 0
            )
        }
        do {
            try persist()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteCapture(_ capture: SavedCapture) {
        snapshot.captures.removeAll { $0.id == capture.id }
        if let imageURL = imageURL(for: capture) {
            try? FileManager.default.removeItem(at: imageURL)
        }
        do {
            try persist()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteScan(_ scan: SavedScan) {
        let previousSnapshot = snapshot
        snapshot.scans.removeAll { $0.id == scan.id }
        snapshot.searches.removeAll { $0.scanID == scan.id }
        snapshot.chats.removeAll { $0.scanID == scan.id }
        do {
            try persist()
            removeFiles(for: scan)
        } catch {
            snapshot = previousSnapshot
            loadError = error.localizedDescription
        }
    }

    func deleteBatch(
        scanIDs: Set<UUID>,
        searchIDs: Set<String>,
        wardrobeIDs: Set<UUID>,
        productIDs: Set<String>,
        tryOnIDs: Set<String>
    ) {
        let previous = snapshot
        let removedScans = snapshot.scans.filter { scanIDs.contains($0.id) }
        let removedWardrobe = snapshot.wardrobeItems.filter { wardrobeIDs.contains($0.id) }
        let removedTryOns = snapshot.tryOns.filter { tryOnIDs.contains($0.id) }

        snapshot.scans.removeAll { scanIDs.contains($0.id) }
        snapshot.searches.removeAll {
            searchIDs.contains($0.id) || scanIDs.contains($0.scanID)
        }
        snapshot.chats.removeAll { scanIDs.contains($0.scanID) }
        snapshot.wardrobeItems.removeAll { wardrobeIDs.contains($0.id) }
        snapshot.tryOnRail.removeAll { wardrobeIDs.contains($0.wardrobeItemID) }
        snapshot.products.removeAll { productIDs.contains($0.id) }
        snapshot.tryOns.removeAll { tryOnIDs.contains($0.id) }

        do {
            try persist()
            for scan in removedScans { removeFiles(for: scan) }
            for item in removedWardrobe { removeWardrobeFiles(for: item) }
            for tryOn in removedTryOns {
                try? FileManager.default.removeItem(at: imageURL(for: tryOn))
            }
        } catch {
            snapshot = previous
            loadError = error.localizedDescription
        }
    }

    @discardableResult
    func replaceSearchID(_ previousID: String, with replacementID: String) -> Bool {
        guard snapshot.captures.contains(where: { $0.searchID == previousID }) else {
            return true
        }
        snapshot.captures = snapshot.captures.map { capture in
            guard capture.searchID == previousID else { return capture }
            return SavedCapture(
                id: capture.id,
                createdAt: capture.createdAt,
                imageFilename: capture.imageFilename,
                query: capture.query,
                origin: capture.origin,
                searchID: replacementID
            )
        }
        do {
            try persist()
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    func clear() throws {
        let previousSnapshot = snapshot
        snapshot = LibrarySnapshot()
        do {
            try persist()
            for scan in previousSnapshot.scans {
                removeFiles(for: scan)
            }
            for capture in previousSnapshot.captures {
                if let filename = capture.imageFilename {
                    try? FileManager.default.removeItem(
                        at: capturesURL.appending(path: filename)
                    )
                }
            }
            for tryOn in previousSnapshot.tryOns {
                try? FileManager.default.removeItem(
                    at: tryOnsURL.appending(path: tryOn.imageFilename)
                )
            }
            for item in previousSnapshot.wardrobeItems {
                removeWardrobeFiles(for: item)
            }
            for photo in previousSnapshot.tryOnPersonPhotos {
                try? FileManager.default.removeItem(at: imageURL(for: photo))
            }
            tryOnMediaCache.removeAllObjects()
        } catch {
            snapshot = previousSnapshot
            throw error
        }
    }

    private func removeFiles(for scan: SavedScan) {
        try? FileManager.default.removeItem(at: imageURL(for: scan))
        for item in scan.items {
            if let cropURL = cropURL(for: item) {
                try? FileManager.default.removeItem(at: cropURL)
            }
        }
    }

    private func removeWardrobeFiles(for item: SavedWardrobeItem) {
        tryOnMediaCache.removeObject(forKey: item.id as NSUUID)
        try? FileManager.default.removeItem(at: imageURL(for: item))
        if let referenceFilename = item.tryOnReferenceFilename {
            removeTryOnReferenceIfUnreferenced(filename: referenceFilename)
        }
    }

    func consumePendingShare() -> SearchInput? {
        let defaults = StylezamShared.defaults
        let text = defaults.string(forKey: StylezamShared.pendingTextKey)
        let imageName = defaults.string(forKey: StylezamShared.pendingImageKey)
        let origin = defaults.string(forKey: StylezamShared.pendingOriginKey)
            .flatMap(CaptureOrigin.init(rawValue:)) ?? .shareExtension
        var imageData: Data?
        if let imageName {
            let container = StylezamShared.handoffContainerURL
            let url = container.appending(path: imageName)
            imageData = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
        }
        defaults.removeObject(forKey: StylezamShared.pendingTextKey)
        defaults.removeObject(forKey: StylezamShared.pendingImageKey)
        defaults.removeObject(forKey: StylezamShared.pendingOriginKey)
        guard imageData != nil || !(text?.isEmpty ?? true) else { return nil }
        return SearchInput(query: text, imageData: imageData, origin: origin)
    }

    private func load() throws {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshot = try decoder.decode(
            LibrarySnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )

        let wardrobeIDs = Set(snapshot.wardrobeItems.map(\.id))
        snapshot.tryOnRail.removeAll { !wardrobeIDs.contains($0.wardrobeItemID) }
        let photoIDs = Set(snapshot.tryOnPersonPhotos.map(\.id))
        if let activeID = snapshot.activeTryOnPhotoID, !photoIDs.contains(activeID) {
            snapshot.activeTryOnPhotoID = snapshot.tryOnPersonPhotos.first?.id
        }
    }

    private func upsertRailEntry(
        for itemID: UUID,
        selected: Bool,
        preserveExistingSelection: Bool = false
    ) {
        if let index = snapshot.tryOnRail.firstIndex(where: { $0.wardrobeItemID == itemID }) {
            if !preserveExistingSelection {
                snapshot.tryOnRail[index].isSelected = selected
            }
            snapshot.tryOnRail[index].addedAt = .now
            let entry = snapshot.tryOnRail.remove(at: index)
            snapshot.tryOnRail.insert(entry, at: 0)
        } else {
            snapshot.tryOnRail.insert(
                TryOnRailEntry(wardrobeItemID: itemID, isSelected: selected, addedAt: .now),
                at: 0
            )
        }
    }

    private func attachTryOnReferenceIfNeeded(
        at index: Int,
        data: Data,
        replacingExisting: Bool = false
    ) throws -> SavedWardrobeItem {
        let existing = snapshot.wardrobeItems[index]
        if !replacingExisting,
           let existingURL = tryOnReferenceURL(for: existing),
           FileManager.default.fileExists(atPath: existingURL.path)
        {
            return existing
        }

        let previous = snapshot
        let previousReferenceFilename = existing.tryOnReferenceFilename
        let reference = Self.contentAddressedTryOnReference(for: data)
        let url = wardrobeURL.appending(path: reference.filename)
        let createdReferenceFile: Bool
        if FileManager.default.fileExists(atPath: url.path) {
            createdReferenceFile = false
        } else {
            try data.write(to: url, options: .atomic)
            createdReferenceFile = true
        }
        let updated = SavedWardrobeItem(
            id: existing.id,
            savedAt: existing.savedAt,
            imageFilename: existing.imageFilename,
            title: existing.title,
            category: existing.category,
            sourceProduct: existing.sourceProduct,
            sourceScanID: existing.sourceScanID,
            sourceGarmentID: existing.sourceGarmentID,
            contentDigest: existing.contentDigest,
            garmentRegion: existing.garmentRegion,
            tryOnReferenceFilename: reference.filename,
            tryOnReferenceDigest: reference.digest
        )
        snapshot.wardrobeItems[index] = updated
        do {
            try persist()
            tryOnMediaCache.removeObject(forKey: existing.id as NSUUID)
            if let previousReferenceFilename,
               previousReferenceFilename != reference.filename
            {
                removeTryOnReferenceIfUnreferenced(filename: previousReferenceFilename)
            }
            return updated
        } catch {
            snapshot = previous
            if createdReferenceFile {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
    }

    private func removeTryOnReferenceIfUnreferenced(filename: String) {
        let remainingReferenceCount = snapshot.wardrobeItems.reduce(into: 0) { count, item in
            if item.tryOnReferenceFilename == filename {
                count += 1
            }
        }
        guard remainingReferenceCount == 0 else { return }
        try? FileManager.default.removeItem(at: wardrobeURL.appending(path: filename))
    }

    private func cachedTryOnMedia(for item: SavedWardrobeItem) -> CachedTryOnMedia? {
        let key = item.id as NSUUID
        if let cached = tryOnMediaCache.object(forKey: key),
           cached.imageFilename == item.imageFilename,
           cached.referenceFilename == item.tryOnReferenceFilename
        {
            return cached
        }

        guard let imageData = try? Data(
            contentsOf: imageURL(for: item),
            options: .mappedIfSafe
        ) else {
            return nil
        }
        let referenceData = tryOnReferenceURL(for: item).flatMap {
            try? Data(contentsOf: $0, options: .mappedIfSafe)
        }
        let cached = CachedTryOnMedia(
            imageFilename: item.imageFilename,
            referenceFilename: item.tryOnReferenceFilename,
            imageData: imageData,
            referenceData: referenceData
        )
        tryOnMediaCache.setObject(cached, forKey: key, cost: cached.memoryCost)
        return cached
    }

    private static func fileExtension(for data: Data) -> String {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
    }

    private static func digest(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func contentAddressedTryOnReference(
        for data: Data
    ) -> (filename: String, digest: String) {
        let contentDigest = Self.digest(for: data)
        return (
            filename: "tryon-reference-\(contentDigest).\(fileExtension(for: data))",
            digest: contentDigest
        )
    }

    private func persist() throws {
        guard acceptsWrites else { throw LibraryStoreError.unavailable }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
    }
}
