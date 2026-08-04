import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private(set) var snapshot = LibrarySnapshot()
    private(set) var loadError: String?

    private let rootURL: URL
    private let capturesURL: URL
    private let garmentsURL: URL
    private let tryOnsURL: URL
    private let snapshotURL: URL

    init() {
        let fallback = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        rootURL = (StylezamShared.containerURL ?? fallback)
            .appending(path: "Stylezam", directoryHint: .isDirectory)
        capturesURL = rootURL.appending(path: "Captures", directoryHint: .isDirectory)
        garmentsURL = rootURL.appending(path: "Garments", directoryHint: .isDirectory)
        tryOnsURL = rootURL.appending(path: "TryOns", directoryHint: .isDirectory)
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
            try load()
        } catch {
            loadError = error.localizedDescription
        }
    }

    var scans: [SavedScan] { snapshot.scans }
    var captures: [SavedCapture] { snapshot.captures }
    var products: [SavedProduct] { snapshot.products }
    var tryOns: [SavedTryOn] { snapshot.tryOns }

    @discardableResult
    func addScan(
        imageData: Data,
        origin: CaptureOrigin,
        mode: CaptureMode,
        detection: GarmentDetectionBatch
    ) throws -> SavedScan {
        let previousSnapshot = snapshot
        let id = UUID()
        let imageFilename = "\(id.uuidString).jpg"
        var createdURLs: [URL] = []

        do {
            let captureURL = capturesURL.appending(path: imageFilename)
            createdURLs.append(captureURL)
            try imageData.write(to: captureURL, options: .atomic)

            let items = try detection.candidates.map { candidate in
                var cropFilename: String?
                if let cropData = candidate.cropData {
                    let filename = "\(id.uuidString)-\(candidate.id).png"
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
                    visibleText: []
                )
            }
            let scan = SavedScan(
                id: id,
                createdAt: .now,
                imageFilename: imageFilename,
                origin: origin,
                mode: mode,
                detectionMethod: detection.method,
                labelState: .local,
                items: items
            )
            snapshot.scans.insert(scan, at: 0)
            let removed = Array(snapshot.scans.dropFirst(60))
            snapshot.scans = Array(snapshot.scans.prefix(60))
            try persist()

            // Delete trimmed media only after the new snapshot is durable.
            for oldScan in removed {
                removeFiles(for: oldScan)
            }
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

    func cropURL(for item: SavedGarment) -> URL? {
        guard let filename = item.cropFilename else { return nil }
        return garmentsURL.appending(path: filename)
    }

    func recentGarmentFingerprintSources(
        since cutoff: Date,
        limit: Int = 40
    ) -> [GarmentFingerprintSource] {
        var values: [GarmentFingerprintSource] = []
        for scan in snapshot.scans where scan.createdAt >= cutoff {
            guard scan.mode == .live || scan.mode == .screen else { continue }
            for item in scan.items {
                guard let url = cropURL(for: item),
                      let data = try? Data(contentsOf: url)
                else { continue }
                values.append(
                    GarmentFingerprintSource(
                        label: item.localLabel,
                        data: data,
                        createdAt: scan.createdAt
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

    func imageURL(for tryOn: SavedTryOn) -> URL {
        tryOnsURL.appending(path: tryOn.imageFilename)
    }

    @discardableResult
    func addTryOn(
        jobID: String,
        product: ProductResultDTO,
        imageData: Data
    ) throws -> SavedTryOn {
        if let existing = snapshot.tryOns.first(where: { $0.id == jobID }) {
            return existing
        }
        let filename = "\(jobID).jpg"
        try imageData.write(
            to: tryOnsURL.appending(path: filename),
            options: .atomic
        )
        let tryOn = SavedTryOn(
            id: jobID,
            createdAt: .now,
            imageFilename: filename,
            product: product
        )
        snapshot.tryOns.insert(tryOn, at: 0)
        snapshot.tryOns = Array(snapshot.tryOns.prefix(60))
        try persist()
        return tryOn
    }

    func deleteTryOn(_ tryOn: SavedTryOn) {
        snapshot.tryOns.removeAll { $0.id == tryOn.id }
        try? FileManager.default.removeItem(at: imageURL(for: tryOn))
        do {
            try persist()
        } catch {
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
        do {
            try persist()
            removeFiles(for: scan)
        } catch {
            snapshot = previousSnapshot
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
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
    }
}
