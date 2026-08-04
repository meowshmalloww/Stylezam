import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let library: LibraryStore
    let liveScreen: LiveScreenCaptureManager
    let modelPack: ModelPackManager

    var selectedTab: AppTab = .home
    var isCapturePresented = false
    var lastError: String?
    var activeScanID: UUID?
    var isAnalyzingCapture = false
    var captureStatus: String?
    var latestPreviewCandidates: [GarmentCandidate] = []
    var pendingTryOnProducts: [ProductResultDTO] = []

    @ObservationIgnored private let captureActivityManager = CaptureActivityManager()
    @ObservationIgnored private let visionEngine = GarmentVisionEngine()
    @ObservationIgnored private let duplicateGuard = GarmentDuplicateGuard()
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private var lastCaptureRequest: Double = 0

    init(
        settings: SettingsStore = SettingsStore(),
        library: LibraryStore = LibraryStore(),
        liveScreen: LiveScreenCaptureManager = LiveScreenCaptureManager(),
        modelPack: ModelPackManager = ModelPackManager()
    ) {
        self.settings = settings
        self.library = library
        self.liveScreen = liveScreen
        self.modelPack = modelPack
    }

    func start() async {
        await modelPack.refresh()
        if let modelURL = modelPack.activeModelURL {
            try? await visionEngine.prepare(modelURL: modelURL)
        }
        handleExternalCaptureRequest()
        handlePendingScanNotification()
        if let pending = library.consumePendingShare() {
            await consumePendingInput(pending)
        }
    }

    func presentCamera() {
        isCapturePresented = true
    }

    func addToTryOn(_ product: ProductResultDTO) {
        if !pendingTryOnProducts.contains(where: { $0.id == product.id }) {
            pendingTryOnProducts.append(product)
        }
        selectedTab = .tryOn
    }

    @discardableResult
    func processCapture(
        imageData: Data,
        origin: CaptureOrigin,
        mode: CaptureMode
    ) async -> SavedScan? {
        guard !isAnalyzingCapture else { return nil }
        isAnalyzingCapture = true
        latestPreviewCandidates = []
        captureStatus = "Finding pieces on this iPhone"
        lastError = nil
        let activityID = UUID().uuidString
        await captureActivityManager.start(
            id: activityID,
            source: mode.activityLabel,
            phase: "Finding pieces on this iPhone"
        )
        defer { isAnalyzingCapture = false }

        do {
            if !modelPack.isInstalled {
                await modelPack.refresh()
            }
            guard let modelURL = modelPack.activeModelURL,
                  let manifest = modelPack.manifest
            else {
                throw ModelPackError.missingModel
            }

            let rawDetection = try await visionEngine.analyze(
                imageData: imageData,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: settings.maxDetectedItems
            )
            let detection: GarmentDetectionBatch
            if mode == .live || mode == .screen {
                let history = library.recentGarmentFingerprintSources(
                    since: Date.now.addingTimeInterval(-20 * 60)
                )
                let novel = await duplicateGuard.novelCandidates(
                    rawDetection.candidates,
                    history: history
                )
                guard !rawDetection.candidates.isEmpty, !novel.isEmpty else {
                    captureStatus = rawDetection.candidates.isEmpty
                        ? "No distinct pieces found"
                        : "Already in Library"
                    await captureActivityManager.finish(
                        captureID: activityID,
                        itemCount: 0,
                        failed: false
                    )
                    return nil
                }
                detection = GarmentDetectionBatch(
                    method: rawDetection.method,
                    candidates: novel
                )
            } else {
                detection = rawDetection
            }

            let scan = try library.addScan(
                imageData: imageData,
                origin: origin,
                mode: mode,
                detection: detection
            )
            activeScanID = scan.id
            selectedTab = .library
            let count = detection.candidates.count
            captureStatus = count == 0
                ? "Saved · no distinct pieces found"
                : count == 1 ? "1 piece ready" : "\(count) pieces ready"
            await captureActivityManager.finish(
                captureID: activityID,
                itemCount: count,
                failed: false
            )
            if settings.notificationsEnabled,
               await notifications.requestAuthorization()
            {
                await notifications.captureFinished(
                    itemCount: count,
                    scanID: scan.id,
                    detectionReady: true
                )
            }
            return scan
        } catch {
            lastError = error.localizedDescription
            captureStatus = nil
            await captureActivityManager.finish(
                captureID: activityID,
                itemCount: 0,
                failed: true
            )
            return nil
        }
    }

    func previewGarments(in imageData: Data) async -> LiveGarmentPreview? {
        guard let modelURL = modelPack.activeModelURL,
              let manifest = modelPack.manifest,
              !isAnalyzingCapture
        else { return nil }
        do {
            let preview = try await visionEngine.preview(
                imageData: imageData,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: settings.maxDetectedItems
            )
            latestPreviewCandidates = preview.candidates
            return preview
        } catch {
            return nil
        }
    }

    /// Runs the same detector and segmented-crop path used by a saved capture,
    /// without duplicate filtering, persistence, notifications, or navigation.
    func inspectGarments(in imageData: Data) async throws -> GarmentDetectionBatch {
        if !modelPack.isInstalled {
            await modelPack.refresh()
        }
        guard let modelURL = modelPack.activeModelURL,
              let manifest = modelPack.manifest
        else {
            throw ModelPackError.missingModel
        }
        return try await visionEngine.analyze(
            imageData: imageData,
            modelURL: modelURL,
            manifest: manifest,
            maxItems: settings.maxDetectedItems
        )
    }

    func deleteCapture(_ capture: SavedCapture) {
        library.deleteCapture(capture)
    }

    func deleteScan(_ scan: SavedScan) {
        library.deleteScan(scan)
        if activeScanID == scan.id {
            activeScanID = nil
        }
    }

    func clearLibrary() {
        do {
            try library.clear()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "stylezam" else { return }
        switch url.host {
        case "capture":
            presentCamera()
        case "import":
            if let pending = library.consumePendingShare() {
                Task { await consumePendingInput(pending) }
            } else {
                selectedTab = .tryOn
            }
        case "search":
            selectedTab = .tryOn
            lastError = "Product retrieval is not in this local build yet."
        case "library":
            selectedTab = .library
        default:
            break
        }
    }

    func handleExternalCaptureRequest() {
        let requestedAt = StylezamShared.defaults.double(
            forKey: StylezamShared.captureRequestKey
        )
        if requestedAt > lastCaptureRequest {
            lastCaptureRequest = requestedAt
            if let liveFrame = liveScreen.consumeLatestFrame() {
                Task {
                    await processCapture(
                        imageData: liveFrame,
                        origin: .screenCapture,
                        mode: .screen
                    )
                }
            } else {
                presentCamera()
            }
        }
        if let pending = library.consumePendingShare() {
            Task { await consumePendingInput(pending) }
        }
    }

    func handlePendingScanNotification(scanID suppliedID: String? = nil) {
        let defaults = StylezamShared.defaults
        let rawID = suppliedID ?? defaults.string(forKey: StylezamShared.pendingScanIDKey)
        guard let rawID,
              let scanID = UUID(uuidString: rawID),
              library.scans.contains(where: { $0.id == scanID })
        else {
            defaults.removeObject(forKey: StylezamShared.pendingScanIDKey)
            return
        }
        defaults.removeObject(forKey: StylezamShared.pendingScanIDKey)
        activeScanID = scanID
        selectedTab = .library
    }

    private func consumePendingInput(_ input: SearchInput) async {
        if let imageData = input.imageData {
            _ = await processCapture(
                imageData: imageData,
                origin: input.origin,
                mode: input.origin == .screenCapture ? .screen : .imported
            )
        } else {
            selectedTab = .tryOn
            lastError = "Text product search is not in this local build yet. Add a fashion image to detect its pieces."
        }
    }
}

private extension CaptureMode {
    var activityLabel: String {
        switch self {
        case .photo: "Camera"
        case .live: "Live camera"
        case .screen: "Live screen"
        case .imported: "Imported image"
        }
    }
}
