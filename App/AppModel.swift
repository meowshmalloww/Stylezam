import Foundation
import Observation
import OSLog
import UIKit
import WidgetKit

@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let library: LibraryStore
    let liveScreen: LiveScreenCaptureManager
    let modelPack: ModelPackManager
    let credentials: CredentialStore
    let searchUsage: SearchUsageStore
    let account: AccountSession

    var selectedTab: AppTab = .home
    var isCapturePresented = false
    var lastError: String?
    var activeScanID: UUID?
    var isAnalyzingCapture = false
    var captureStatus: String?
    var latestPreviewCandidates: [GarmentCandidate] = []
    var pendingGarmentSearch: PendingGarmentSearch?
    var pendingTryOnProducts: [ProductResultDTO] = []
    var pendingTryOnItems: [TryOnTrayItem] = []
    var isTryOnPresented = false
    var liveScreenNotice: String?

    @ObservationIgnored private let captureActivityManager = CaptureActivityManager()
    @ObservationIgnored private let visionEngine = GarmentVisionEngine()
    @ObservationIgnored private let duplicateGuard = GarmentDuplicateGuard()
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private let productSearchService = ProductSearchService()
    @ObservationIgnored private let liveScreenLogger = Logger(
        subsystem: "com.stylezam.app",
        category: "LiveScreenAutoCapture"
    )
    @ObservationIgnored private var lastCaptureRequest: Double = 0
    @ObservationIgnored private var lastLiveScreenRequest: Double = 0
    @ObservationIgnored private var liveScreenPickerTask: Task<Void, Never>?
    @ObservationIgnored private var isLiveScreenPickerPending = false
    @ObservationIgnored private var isStartupComplete = false
    @ObservationIgnored private var pendingDeepLink: URL?
    @ObservationIgnored private var pendingControlDestination: StylezamControlDestination?
    @ObservationIgnored private var liveScreenAutomaticTask: Task<Void, Never>?
    @ObservationIgnored private var liveScreenAutoCapture = LiveScreenAutoCaptureCoordinator()
    @ObservationIgnored private var liveScreenPreviewFocus: BoundingBoxDTO?
    @ObservationIgnored private var liveScreenLastContentFingerprint: LiveScreenContentFingerprint?
    @ObservationIgnored private var liveScreenSuppressedContentFingerprint: LiveScreenContentFingerprint?
    @ObservationIgnored private var liveScreenSuppressionStatus: String?
    @ObservationIgnored private var liveScreenStableContentFrames = 0
    @ObservationIgnored private var liveScreenEmptyAdaptiveAttempts = 0

    init(
        settings: SettingsStore = SettingsStore(),
        library: LibraryStore = LibraryStore(),
        liveScreen: LiveScreenCaptureManager = LiveScreenCaptureManager(),
        modelPack: ModelPackManager = ModelPackManager(),
        credentials: CredentialStore = CredentialStore(),
        searchUsage: SearchUsageStore = SearchUsageStore(),
        account: AccountSession = AccountSession()
    ) {
        self.settings = settings
        self.library = library
        self.liveScreen = liveScreen
        self.modelPack = modelPack
        self.credentials = credentials
        self.searchUsage = searchUsage
        self.account = account
    }

    func start() async {
        ControlCenter.shared.reloadAllControls()
        credentials.importDebugEnvironment()
#if DEBUG
        YouCamCredentialStore.importDebugEnvironment()
        if settings.brightDataZone.isEmpty,
           let zone = ProcessInfo.processInfo.environment["STYLEZAM_BRIGHTDATA_ZONE"],
           !zone.isEmpty
        {
            settings.brightDataZone = zone
        }
#endif
        await account.start()
        await modelPack.refresh()
        if let modelURL = modelPack.activeModelURL {
            try? await visionEngine.prepare(modelURL: modelURL)
        }
        liveScreen.setFrameHandler { [weak self] frame in
            self?.handleAutomaticLiveScreenFrame(frame)
        }
#if DEBUG
        await runDeviceVisionSmokeTestIfRequested()
#endif
        handleExternalCaptureRequest()
        handlePendingScanNotification()
        if let pending = library.consumePendingShare() {
            await consumePendingInput(pending)
        }
        isStartupComplete = true
        if let pendingDeepLink {
            self.pendingDeepLink = nil
            handleURL(pendingDeepLink)
        }
        if let pendingControlDestination {
            self.pendingControlDestination = nil
            handleControlDestination(pendingControlDestination)
        }
    }

    func presentCamera() {
        guard account.isAuthenticated else {
            lastError = "Sign in with Google before starting a capture."
            return
        }
        isCapturePresented = true
    }

    func addToTryOn(_ product: ProductResultDTO) {
        if !pendingTryOnProducts.contains(where: { $0.id == product.id }) {
            pendingTryOnProducts.append(product)
        }
        isTryOnPresented = true
    }

    func openProductSearch(
        scanID: UUID,
        garmentID: String,
        startsImmediately: Bool
    ) {
        pendingGarmentSearch = PendingGarmentSearch(
            scanID: scanID,
            garmentID: garmentID,
            startsImmediately: startsImmediately
        )
        activeScanID = nil
        selectedTab = .search
    }

    func addGarmentToTryOn(scanID: UUID, garmentID: String) {
        guard let scan = library.scans.first(where: { $0.id == scanID }),
              let garment = scan.items.first(where: { $0.id == garmentID }),
              let cropURL = library.cropURL(for: garment),
              let cropData = try? Data(contentsOf: cropURL)
        else {
            lastError = "The detected crop is unavailable. Capture the piece again or choose a product match."
            return
        }

        let category = TryOnCategory.infer(
            category: garment.category,
            title: garment.title
        )
        pendingTryOnItems.removeAll { item in
            item.title == garment.title && item.imageData == cropData
        }
        pendingTryOnItems.append(
            TryOnTrayItem(
                title: garment.title,
                category: category,
                imageData: cropData
            )
        )
        lastError = nil
        isTryOnPresented = true
    }

    @discardableResult
    func processCapture(
        imageData: Data,
        origin: CaptureOrigin,
        mode: CaptureMode,
        navigateToLibrary: Bool = true
    ) async -> SavedScan? {
        guard !isAnalyzingCapture else { return nil }
        isAnalyzingCapture = true
        latestPreviewCandidates = []
        captureStatus = "Finding pieces on this iPhone"
        lastError = nil
        let activityID = UUID().uuidString
        let usesStandaloneActivity = mode != .screen
        if usesStandaloneActivity {
            await captureActivityManager.start(
                id: activityID,
                source: mode.activityLabel,
                phase: "Finding pieces on this iPhone"
            )
        }
        defer { isAnalyzingCapture = false }

        do {
            if !modelPack.isInstalled {
                await modelPack.refresh()
            }
            guard let modelURL = modelPack.activeModelURL,
                  let manifest = modelPack.manifest
            else {
                throw ModelPackError.unavailable(
                    modelPack.lastError ?? ModelPackError.missingModel.localizedDescription
                )
            }

            let rawDetection = try await visionEngine.analyze(
                imageData: imageData,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: settings.maxDetectedItems,
                // Camera preview frames remain a single lightweight pass. Every accepted
                // still—including a stable Live Screen frame—uses bounded detail
                // tiles, with Low Power Mode, the thermal state, and the 9-second
                // processing budget deciding how many passes are safe.
                enableAdaptiveDetail: true
            )
            let detection: GarmentDetectionBatch
            var visualFingerprints: [String: GarmentVisualFingerprint] = [:]
            if mode == .live || mode == .screen {
                let history = library.garmentFingerprintSources()
                let novel = await duplicateGuard.novelCandidates(
                    rawDetection.candidates,
                    history: history
                )
                guard !rawDetection.candidates.isEmpty, !novel.isEmpty else {
                    captureStatus = rawDetection.candidates.isEmpty
                        ? "No distinct pieces found"
                        : "Already in Library"
                    if usesStandaloneActivity {
                        await captureActivityManager.finish(
                            captureID: activityID,
                            itemCount: 0,
                            failed: false
                        )
                    }
                    return nil
                }
                detection = GarmentDetectionBatch(
                    method: rawDetection.method,
                    candidates: novel.map(\.candidate),
                    metrics: rawDetection.metrics
                )
                visualFingerprints = Dictionary(
                    uniqueKeysWithValues: novel.map {
                        ($0.candidate.id, $0.fingerprint)
                    }
                )
            } else {
                detection = rawDetection
            }

            let scan = try library.addScan(
                imageData: imageData,
                origin: origin,
                mode: mode,
                detection: detection,
                visualFingerprints: visualFingerprints
            )
            activeScanID = scan.id
            if navigateToLibrary {
                selectedTab = .library
            }
            let count = detection.candidates.count
            captureStatus = count == 0
                ? "Saved · no distinct pieces found"
                : count == 1 ? "1 piece ready" : "\(count) pieces ready"
            if usesStandaloneActivity {
                await captureActivityManager.finish(
                    captureID: activityID,
                    itemCount: count,
                    failed: false
                )
            }
            if UIApplication.shared.applicationState == .active, count > 0 {
                let feedback = UINotificationFeedbackGenerator()
                feedback.prepare()
                feedback.notificationOccurred(.success)
            }
            if mode != .screen,
               settings.notificationsEnabled,
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
            if usesStandaloneActivity {
                await captureActivityManager.finish(
                    captureID: activityID,
                    itemCount: 0,
                    failed: true
                )
            }
            return nil
        }
    }

    func previewGarments(
        in imageData: Data,
        focusFrame: BoundingBoxDTO? = nil
    ) async -> LiveGarmentPreview? {
        guard let modelURL = modelPack.activeModelURL,
              let manifest = modelPack.manifest,
              !isAnalyzingCapture
        else { return nil }
        do {
            let preview = try await visionEngine.preview(
                imageData: imageData,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: settings.maxDetectedItems,
                focusFrame: focusFrame
            )
            latestPreviewCandidates = preview.candidates
            return preview
        } catch {
            return nil
        }
    }

    private func previewLiveScreenGarments(
        in imageData: Data
    ) async -> LiveGarmentPreview? {
        guard let modelURL = modelPack.activeModelURL,
              let manifest = modelPack.manifest,
              !isAnalyzingCapture
        else { return nil }
        do {
            let preview = try await visionEngine.adaptiveScreenPreview(
                imageData: imageData,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: settings.maxDetectedItems
            )
            latestPreviewCandidates = preview.candidates
            return preview
        } catch {
            liveScreenLogger.error(
                "Live-screen preview failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Runs a crop-free, detail-aware detector on throttled authorized display frames. A stable
    /// garment is promoted to `processCapture`, which creates the high-resolution crops, persists
    /// the scan, and posts the same completion notification as Live camera.
    private func handleAutomaticLiveScreenFrame(_ frame: LiveScreenFrame) {
        guard liveScreen.isCapturing else {
            liveScreenAutoCapture.reset()
            resetLiveScreenAnalysisState()
            return
        }
        guard settings.liveScreenAutoCaptureEnabled else {
            liveScreenAutoCapture.reset()
            clearLiveScreenAnalysisState()
            liveScreen.setAutomaticAnalysisIdle(true)
            liveScreen.setAutomaticAnalysisStatus(
                "Streaming is active. Automatic Live Screen saving is turned off."
            )
            return
        }
        guard modelPack.isInstalled else {
            liveScreenAutoCapture.reset()
            clearLiveScreenAnalysisState()
            liveScreen.setAutomaticAnalysisIdle(true)
            liveScreen.setAutomaticAnalysisStatus(
                "The on-device garment model is not installed."
            )
            return
        }
        guard liveScreenAutomaticTask == nil, !isAnalyzingCapture else { return }

        liveScreenAutomaticTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.liveScreenAutomaticTask = nil }

            let contentFingerprint = await Task.detached(priority: .utility) {
                LiveScreenContentFingerprint.make(imageData: frame.data)
            }.value
            guard let contentFingerprint, !Task.isCancelled else { return }

            if let suppressed = self.liveScreenSuppressedContentFingerprint,
               contentFingerprint.isVisuallySimilar(to: suppressed)
            {
                self.liveScreen.setAutomaticAnalysisIdle(true)
                self.liveScreen.setAutomaticAnalysisStatus(
                    self.liveScreenSuppressionStatus
                        ?? "This screen is already handled. Watching for a change."
                )
                return
            }

            let contentIsStable = self.liveScreenLastContentFingerprint.map {
                contentFingerprint.isVisuallySimilar(to: $0)
            } ?? false
            self.liveScreenLastContentFingerprint = contentFingerprint
            if contentIsStable {
                self.liveScreenStableContentFrames += 1
            } else {
                self.liveScreenStableContentFrames = 1
                self.liveScreenEmptyAdaptiveAttempts = 0
                self.liveScreenPreviewFocus = nil
                self.liveScreenSuppressedContentFingerprint = nil
                self.liveScreenSuppressionStatus = nil
                self.liveScreen.setAutomaticAnalysisIdle(false)
            }

            let strategy = LiveScreenAnalysisPlanner.strategy(
                contentIsStable: contentIsStable,
                stableFrameCount: self.liveScreenStableContentFrames,
                hasFocus: self.liveScreenPreviewFocus != nil
            )

            self.liveScreen.setAutomaticAnalysisFeedback(
                status: "Scanning the authorized screen on this iPhone.",
                activityPhase: "Scanning screen",
                visualState: .detecting
            )
            let preview: LiveGarmentPreview?
            switch strategy {
            case .focused:
                // Once discovery identifies a likely piece, confirmation needs only one focused
                // tensor per sampled frame instead of repeating every screen detail tile.
                preview = await self.previewGarments(
                    in: frame.data,
                    focusFrame: self.liveScreenPreviewFocus
                )
            case .adaptive:
                preview = await self.previewLiveScreenGarments(in: frame.data)
            case .global:
                preview = await self.previewGarments(in: frame.data)
            }
            guard let preview,
                  !Task.isCancelled,
                  self.liveScreen.isCapturing
            else { return }

            self.liveScreen.recordAnalysis(
                frame: frame,
                candidates: preview.candidates,
                stage: preview.candidates.isEmpty
                    ? "Analyzed · no garment in this pass"
                    : "Detected \(preview.candidates.count) garment region(s)",
                retainDebugArtifacts: true
            )

            guard let anchor = preview.candidates.max(by: { left, right in
                Self.liveScreenAnchorScore(left) < Self.liveScreenAnchorScore(right)
            }) else {
                self.liveScreenAutoCapture.reset()
                switch strategy {
                case .focused:
                    // A focused confirmation can lose the item after a small layout shift. One
                    // subsequent adaptive discovery is more reliable than retrying a stale ROI.
                    self.liveScreenPreviewFocus = nil
                    self.liveScreenEmptyAdaptiveAttempts = 0
                    self.liveScreen.setAutomaticAnalysisFeedback(
                        status: "The item moved. Rechecking the full screen.",
                        activityPhase: "Rechecking screen",
                        visualState: .watching
                    )
                case .adaptive:
                    self.liveScreenEmptyAdaptiveAttempts += 1
                    if self.liveScreenEmptyAdaptiveAttempts >= 2 {
                        self.liveScreenSuppressedContentFingerprint = contentFingerprint
                        self.liveScreenSuppressionStatus =
                            "No fashion item found on this unchanged screen. Watching for a change."
                        self.liveScreen.setAutomaticAnalysisIdle(true)
                        self.liveScreen.setAutomaticAnalysisFeedback(
                            status: self.liveScreenSuppressionStatus
                                ?? "No fashion item found. Watching for a change.",
                            activityPhase: "Watching for fashion",
                            visualState: .watching
                        )
                    } else {
                        self.liveScreen.setAutomaticAnalysisFeedback(
                            status: "Checking the stable screen once more.",
                            activityPhase: "Checking details",
                            visualState: .detecting
                        )
                    }
                case .global:
                    self.liveScreen.setAutomaticAnalysisFeedback(
                        status: "No piece in the quick pass. Pause briefly for a detailed scan.",
                        activityPhase: "Pause for detail scan",
                        visualState: .watching
                    )
                }
                return
            }
            self.liveScreenEmptyAdaptiveAttempts = 0
            if self.liveScreenPreviewFocus == nil {
                self.liveScreenPreviewFocus = Self.liveScreenConfirmationFocus(
                    around: anchor.box,
                    pixelWidth: frame.pixelWidth,
                    pixelHeight: frame.pixelHeight
                )
            }

            let fingerprint = await Task.detached(priority: .utility) {
                LiveScreenPerceptualHash.differenceHash(
                    imageData: frame.data,
                    region: anchor.box
                )
            }.value
            guard let fingerprint, !Task.isCancelled else {
                self.liveScreenAutoCapture.reset()
                return
            }

            let candidate = LiveScreenAutoCaptureCoordinator.Candidate(
                label: anchor.localLabel,
                confidence: anchor.confidence,
                box: anchor.box,
                fingerprint: fingerprint
            )
            guard self.liveScreenAutoCapture.shouldCapture(
                candidate,
                qualityScore: preview.qualityScore,
                now: frame.capturedAt
            ) else {
                self.liveScreen.setAutomaticAnalysisFeedback(
                    status: "Recognized \(anchor.localLabel). Hold it briefly for capture.",
                    activityPhase: "Found \(anchor.localLabel)",
                    visualState: .recognized,
                    itemCount: preview.candidates.count
                )
                return
            }

            self.liveScreen.setAutomaticAnalysisFeedback(
                status: "Stable \(anchor.localLabel) found. Creating full-resolution crops.",
                activityPhase: "Cropping \(anchor.localLabel)",
                visualState: .cropping,
                itemCount: preview.candidates.count
            )
            self.liveScreenLogger.notice(
                "Stable live-screen garment accepted at \(frame.pixelWidth)x\(frame.pixelHeight)"
            )
            let scan = await self.processCapture(
                imageData: frame.data,
                origin: .screenCapture,
                mode: .screen
            )
            let duplicateWasSuppressed = self.captureStatus == "Already in Library"
            self.liveScreenAutoCapture.recordCaptureResult(
                fingerprint: fingerprint,
                shouldSuppressRepeat: scan != nil || duplicateWasSuppressed
            )

            if let scan {
                let debugCandidates = scan.items.map { item in
                    GarmentCandidate(
                        id: item.id,
                        localLabel: item.localLabel,
                        confidence: item.localConfidence,
                        box: item.box,
                        boxCropData: nil,
                        cropData: nil
                    )
                }
                let debugCrops = scan.items.map { item in
                    self.library.cropURL(for: item).flatMap { try? Data(contentsOf: $0) }
                }
                self.liveScreen.recordSavedDebugSnapshot(
                    frame: frame,
                    candidates: debugCandidates,
                    cropData: debugCrops,
                    retainDebugArtifacts: true
                )
                self.liveScreenSuppressedContentFingerprint = contentFingerprint
                self.liveScreenSuppressionStatus =
                    "This screen is saved. Watching for a visual change."
                self.liveScreen.setAutomaticAnalysisIdle(true)
                self.liveScreen.recordAutomaticallySavedPieces(scan.items.count)
                self.liveScreenLogger.notice(
                    "Automatically saved \(scan.items.count) live-screen pieces"
                )
            } else if duplicateWasSuppressed {
                self.liveScreenSuppressedContentFingerprint = contentFingerprint
                self.liveScreenSuppressionStatus =
                    "This piece is already in Library. Watching for a visual change."
                self.liveScreen.setAutomaticAnalysisIdle(true)
                self.liveScreen.setAutomaticAnalysisFeedback(
                    status: self.liveScreenSuppressionStatus
                        ?? "This piece is already in Library.",
                    activityPhase: "Already in Library",
                    visualState: .saved
                )
            } else {
                self.liveScreenPreviewFocus = nil
                self.liveScreen.setAutomaticAnalysisFeedback(
                    status: "The final frame was not clear enough. Watching for a better view.",
                    activityPhase: "Waiting for a clearer view",
                    visualState: .watching
                )
            }
        }
    }

    private nonisolated static func liveScreenAnchorScore(
        _ candidate: GarmentCandidate
    ) -> Double {
        let area = max(0, candidate.box.width * candidate.box.height)
        return candidate.confidence * Foundation.sqrt(area)
    }

    private func clearLiveScreenAnalysisState() {
        liveScreenPreviewFocus = nil
        liveScreenLastContentFingerprint = nil
        liveScreenSuppressedContentFingerprint = nil
        liveScreenSuppressionStatus = nil
        liveScreenStableContentFrames = 0
        liveScreenEmptyAdaptiveAttempts = 0
    }

    private func resetLiveScreenAnalysisState() {
        clearLiveScreenAnalysisState()
        liveScreen.setAutomaticAnalysisIdle(false)
    }

    private nonisolated static func liveScreenConfirmationFocus(
        around box: BoundingBoxDTO,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> BoundingBoxDTO {
        let imageWidth = Double(max(1, pixelWidth))
        let imageHeight = Double(max(1, pixelHeight))
        let boxWidth = box.width * imageWidth
        let boxHeight = box.height * imageHeight
        let shortestSide = min(imageWidth, imageHeight)
        let side = min(
            shortestSide,
            max(shortestSide * 0.46, max(boxWidth, boxHeight) * 1.34)
        )
        let frameWidth = min(1, side / imageWidth)
        let frameHeight = min(1, side / imageHeight)
        let centerX = box.x + box.width / 2
        let centerY = box.y + box.height / 2
        return BoundingBoxDTO(
            x: min(1 - frameWidth, max(0, centerX - frameWidth / 2)),
            y: min(1 - frameHeight, max(0, centerY - frameHeight / 2)),
            width: frameWidth,
            height: frameHeight
        )
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
            throw ModelPackError.unavailable(
                modelPack.lastError ?? ModelPackError.missingModel.localizedDescription
            )
        }
        return try await visionEngine.analyze(
            imageData: imageData,
            modelURL: modelURL,
            manifest: manifest,
            maxItems: settings.maxDetectedItems,
            includeDiagnosticMasks: true
        )
    }

    func deleteCapture(_ capture: SavedCapture) {
        library.deleteCapture(capture)
    }

    func deleteScan(_ scan: SavedScan) {
        library.deleteScan(scan)
        Task { await duplicateGuard.reset() }
        if activeScanID == scan.id {
            activeScanID = nil
        }
    }

    func clearLibrary() {
        do {
            try library.clear()
            Task { await duplicateGuard.reset() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteLibraryItems(
        scanIDs: Set<UUID>,
        searchIDs: Set<String>,
        wardrobeIDs: Set<UUID>,
        productIDs: Set<String>,
        tryOnIDs: Set<String>
    ) {
        library.deleteBatch(
            scanIDs: scanIDs,
            searchIDs: searchIDs,
            wardrobeIDs: wardrobeIDs,
            productIDs: productIDs,
            tryOnIDs: tryOnIDs
        )
        if !scanIDs.isEmpty {
            Task { await duplicateGuard.reset() }
        }
    }

    func productSearch(
        scanID: UUID,
        garmentID: String,
        refinement: String? = nil,
        aiSearchIntent: AIShoppingSearchIntent? = nil,
        progress: ((ProductSearchProgress) -> Void)? = nil
    ) async throws -> SavedProductSearch {
        progress?(.preparing)
        guard let activePlan = account.account?.plan else {
            throw ProductSearchError.provider("Sign in with Google before searching.")
        }
        if let limit = activePlan.productSearchLimit,
           searchUsage.logicalCount(kind: .productSearch) >= limit
        {
            throw ProductSearchError.planLimitReached("product searches", limit)
        }
        let context = try garmentSearchContext(scanID: scanID, garmentID: garmentID)
        if refinement == nil,
           let existing = library.search(for: context.key),
           searchUsage.attempts(for: context.key) >= settings.productSearchesPerPiece
        {
            return existing
        }

        // A normal Find action is a direct visual search. Fireworks is used
        // only when the user explicitly turns an AI/chat request into a
        // similar-product text search.
        let pipeline: ProductSearchPipeline = refinement == nil
            ? .directImage
            : .privateAIText
        let providers: [String]
        var directKey: String?
        var fireworksKey: String?
        var serperKey: String?
        var publicURL: URL?

        switch pipeline {
        case .privateAIText:
            fireworksKey = try credentials.credential(for: .fireworks)
            serperKey = try credentials.credential(for: .serper)
            guard fireworksKey?.isEmpty == false else {
                throw ProductSearchError.missingCredential(SearchCredentialKind.fireworks.title)
            }
            guard serperKey?.isEmpty == false else {
                throw ProductSearchError.missingCredential(SearchCredentialKind.serper.title)
            }
            providers = ["fireworks", "serper"]
        case .directImage:
            guard let selected = activeImageSearchProvider else {
                throw ProductSearchError.provider(
                    "No visual-search route is ready. This private build needs a Lykdat or Google Cloud Vision key, or another provider key plus a public HTTPS crop URL."
                )
            }
            directKey = try credentials.credential(for: selected.credential)
            guard directKey?.isEmpty == false else {
                throw ProductSearchError.missingCredential(selected.title)
            }
            if !selected.acceptsPrivateImageData {
                let rawURL = settings.publicImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let candidate = URL(string: rawURL), candidate.scheme == "https" else {
                    throw ProductSearchError.publicImageURLRequired(selected.title)
                }
                publicURL = candidate
            }
            if selected == .brightData,
               settings.brightDataZone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                throw ProductSearchError.missingBrightDataZone
            }
            providers = [selected.rawValue]
        }

        let usageID = try searchUsage.reserveProductSearch(
            garmentKey: context.key,
            providers: providers,
            perGarmentLimit: settings.productSearchesPerPiece,
            providerMonthlyLimits: settings.monthlyRequestLimits(for: pipeline),
            fireworksBudgetUSD: settings.fireworksMonthlyBudgetUSD
        )
        let startedAt = Date()
        let searchID = UUID().uuidString

        do {
            var results: [ProductResultDTO]
            let understanding: GarmentUnderstanding?
            let providerSummary: String
            let diagnostic: String
            var estimatedCost = 0.0

            switch pipeline {
            case .privateAIText:
                progress?(.analyzingRequest)
                let (analysis, fireworkResponse) = try await productSearchService.understandGarment(
                    imageData: context.imageData,
                    localLabel: context.garmentLabel,
                    refinement: refinement,
                    searchIntent: aiSearchIntent,
                    apiKey: fireworksKey!,
                    modelID: settings.fireworksModelID
                )
                progress?(.searchingStores)
                let serperResponse = try await productSearchService.serperProducts(
                    query: analysis.searchQuery,
                    apiKey: serperKey!,
                    country: settings.searchCountry,
                    language: settings.searchLanguage,
                    limit: settings.productResultLimit,
                    searchID: searchID
                )
                results = serperResponse.results
                if aiSearchIntent == .cheaper {
                    results.sort { left, right in
                        switch (left.price, right.price) {
                        case let (leftPrice?, rightPrice?) where leftPrice.currency == rightPrice.currency:
                            if leftPrice.amount != rightPrice.amount {
                                return leftPrice.amount < rightPrice.amount
                            }
                            return left.score > right.score
                        case (_?, nil):
                            return true
                        case (nil, _?):
                            return false
                        default:
                            return left.score > right.score
                        }
                    }
                }
                understanding = analysis
                providerSummary = "AI-guided shopping"
                diagnostic = "\(fireworkResponse.diagnostic); \(serperResponse.diagnostic)"
                estimatedCost = fireworksCost(
                    inputTokens: fireworkResponse.inputTokens,
                    outputTokens: fireworkResponse.outputTokens
                )
                library.applyUnderstanding(analysis, scanID: scanID, garmentID: garmentID)
            case .directImage:
                guard let selectedRaw = providers.first,
                      let selected = ImageSearchProvider(rawValue: selectedRaw)
                else {
                    throw ProductSearchError.provider("The selected visual-search route became unavailable.")
                }
                progress?(.searchingImage(selected.title))
                let response = try await productSearchService.directImageSearch(
                    provider: selected,
                    imageData: context.imageData,
                    targetLabel: context.garmentLabel,
                    publicImageURL: publicURL,
                    apiKey: directKey!,
                    brightDataZone: settings.brightDataZone,
                    limit: settings.productResultLimit,
                    searchID: searchID
                )
                results = response.results
                understanding = nil
                providerSummary = selected == settings.imageSearchProvider
                    ? selected.title
                    : "\(selected.title) · fallback"
                diagnostic = response.diagnostic
            }

            progress?(.saving(results.count))
            let elapsed = Date().timeIntervalSince(startedAt) * 1_000
            let saved = SavedProductSearch(
                id: searchID,
                garmentKey: context.key,
                scanID: scanID,
                garmentID: garmentID,
                createdAt: .now,
                pipeline: pipeline,
                providerSummary: providerSummary,
                aiSearchIntent: aiSearchIntent,
                generatedQuery: understanding?.searchQuery,
                generatedSuggestions: understanding?.suggestions ?? [],
                results: results,
                durationMilliseconds: elapsed
            )
            try library.saveSearch(saved)
            searchUsage.complete(
                usageID,
                resultCount: results.count,
                latencyMilliseconds: elapsed,
                estimatedCostUSD: estimatedCost,
                diagnostic: diagnostic
            )
            return saved
        } catch {
            searchUsage.fail(
                usageID,
                latencyMilliseconds: Date().timeIntervalSince(startedAt) * 1_000,
                diagnostic: error.localizedDescription
            )
            throw error
        }
    }

    var eligibleImageSearchProviders: [ImageSearchProvider] {
        let publicURLIsReady: Bool = {
            let raw = settings.publicImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw) else { return false }
            return url.scheme?.lowercased() == "https"
        }()

        return ImageSearchProvider.allCases.filter { provider in
            guard credentials.hasCredential(provider.credential) else { return false }
            if provider.acceptsPrivateImageData { return true }
            guard publicURLIsReady else { return false }
            if provider == .brightData {
                return !settings.brightDataZone
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            }
            return true
        }
    }

    var activeImageSearchProvider: ImageSearchProvider? {
        let eligible = eligibleImageSearchProviders
        if eligible.contains(settings.imageSearchProvider) {
            return settings.imageSearchProvider
        }
        return searchUsage.routedImageProvider(from: eligible)
    }

    func askStylezamAI(
        scanID: UUID,
        garmentID: String,
        question: String
    ) async throws -> StylezamChatMessage {
        guard let activePlan = account.account?.plan else {
            throw ProductSearchError.provider("Sign in with Google before using the assistant.")
        }
        if let limit = activePlan.assistantQuestionLimit,
           searchUsage.logicalCount(kind: .assistant) >= limit
        {
            throw ProductSearchError.planLimitReached("AI questions", limit)
        }
        let context = try garmentSearchContext(scanID: scanID, garmentID: garmentID)
        let history = library.chatMessages(for: context.key)
        guard let key = try credentials.credential(for: .fireworks), !key.isEmpty else {
            throw ProductSearchError.missingCredential(SearchCredentialKind.fireworks.title)
        }
        let usageID = try searchUsage.reserveAuxiliary(
            kind: .assistant,
            garmentKey: context.key,
            provider: "fireworks",
            monthlyLimit: 100_000,
            fireworksBudgetUSD: settings.fireworksMonthlyBudgetUSD
        )
        let startedAt = Date()
        do {
            let (turn, response) = try await productSearchService.assistantReply(
                imageData: context.imageData,
                localLabel: context.garmentLabel,
                history: history,
                question: question,
                apiKey: key,
                modelID: settings.fireworksModelID
            )
            searchUsage.complete(
                usageID,
                resultCount: 1,
                latencyMilliseconds: Date().timeIntervalSince(startedAt) * 1_000,
                estimatedCostUSD: fireworksCost(
                    inputTokens: response.inputTokens,
                    outputTokens: response.outputTokens
                ),
                diagnostic: response.diagnostic
            )
            let userMessage = StylezamChatMessage(role: .user, text: question)
            let assistantMessage = StylezamChatMessage(
                role: .assistant,
                text: turn.answer,
                suggestedQuestions: turn.suggestedQuestions
            )
            try library.appendChatMessages(
                [userMessage, assistantMessage],
                garmentKey: context.key,
                scanID: scanID,
                garmentID: garmentID
            )
            return assistantMessage
        } catch {
            searchUsage.fail(
                usageID,
                latencyMilliseconds: Date().timeIntervalSince(startedAt) * 1_000,
                diagnostic: error.localizedDescription
            )
            throw error
        }
    }

    private func garmentSearchContext(scanID: UUID, garmentID: String) throws -> GarmentSearchContext {
        guard let scan = library.scans.first(where: { $0.id == scanID }),
              let item = scan.items.first(where: { $0.id == garmentID }),
              let cropURL = library.cropURL(for: item),
              let imageData = try? Data(contentsOf: cropURL),
              !imageData.isEmpty
        else {
            throw ProductSearchError.provider("The selected garment crop is unavailable on this iPhone.")
        }
        return GarmentSearchContext(
            scanID: scanID,
            garmentID: garmentID,
            garmentLabel: item.localLabel,
            imageData: imageData
        )
    }

    private func fireworksCost(inputTokens: Int?, outputTokens: Int?) -> Double {
        // Qwen 3.7 Plus serverless list pricing verified August 2026.
        // Count uncached input conservatively so the local safety meter never
        // understates spend when the provider omits cached-token detail.
        let input = Double(inputTokens ?? 0) * 0.5 / 1_000_000
        let output = Double(outputTokens ?? 0) * 3.0 / 1_000_000
        return input + output
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "stylezam" else { return }
        guard isStartupComplete else {
            pendingDeepLink = url
            return
        }
        switch url.host {
        case "capture":
            presentCamera()
        case "capture-request":
            captureFromControl()
        case "import":
            if let pending = library.consumePendingShare() {
                Task { await consumePendingInput(pending) }
            } else {
                selectedTab = .search
            }
        case "search":
            selectedTab = .search
            lastError = nil
        case "live-screen":
            requestLiveScreenPicker()
        case "try-on":
            isTryOnPresented = true
        case "library":
            selectedTab = .library
        default:
            break
        }
    }

    func handleControlDestination(_ destination: StylezamControlDestination) {
        guard isStartupComplete else {
            pendingControlDestination = destination
            return
        }

        switch destination {
        case .capture:
            captureFromControl()
        case .liveScreen:
            requestLiveScreenPicker()
        }
    }

    func handleExternalCaptureRequest() {
        let defaults = StylezamShared.defaults
        let liveRequestedAt = StylezamShared.defaults.double(
            forKey: StylezamShared.liveScreenRequestKey
        )
        if liveRequestedAt > lastLiveScreenRequest {
            lastLiveScreenRequest = liveRequestedAt
            defaults.removeObject(forKey: StylezamShared.liveScreenRequestKey)
            requestLiveScreenPicker()
        }
        let requestedAt = defaults.double(
            forKey: StylezamShared.captureRequestKey
        )
        if requestedAt > lastCaptureRequest {
            lastCaptureRequest = requestedAt
            defaults.removeObject(forKey: StylezamShared.captureRequestKey)
            captureFromControl()
        }
        if let pending = library.consumePendingShare() {
            Task { await consumePendingInput(pending) }
        }
    }

    func activatePendingLiveScreenPicker() {
        guard isLiveScreenPickerPending,
              UIApplication.shared.applicationState == .active
        else { return }

        liveScreenPickerTask?.cancel()
        liveScreenPickerTask = Task { @MainActor [weak self] in
            // A Control Center OpenIntent handoff can arrive a moment before the
            // application window is ready to present Apple's system picker.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled,
                  let self,
                  self.isLiveScreenPickerPending,
                  UIApplication.shared.applicationState == .active
            else { return }
            self.isLiveScreenPickerPending = false
            self.liveScreen.presentSystemPicker()
        }
    }

    private func requestLiveScreenPicker() {
        #if DEBUG
        let isLiveScreenUITest = ProcessInfo.processInfo.arguments.contains(
            "-stylezam-ui-test-live-screen"
        )
        #else
        let isLiveScreenUITest = false
        #endif
        guard account.isAuthenticated || isLiveScreenUITest else {
            liveScreenNotice = "Sign in with Google before starting Live Screen."
            return
        }
        guard ScreenCaptureAvailability.isSDKAvailable else {
            liveScreen.presentSystemPicker()
            liveScreenNotice = liveScreen.errorMessage ?? ScreenCaptureAvailability.summary
            return
        }
        liveScreenAutomaticTask?.cancel()
        liveScreenAutomaticTask = nil
        liveScreenAutoCapture.reset()
        resetLiveScreenAnalysisState()
        liveScreenNotice = nil
        isLiveScreenPickerPending = true
        activatePendingLiveScreenPicker()
    }

    private func captureFromControl() {
        guard account.isAuthenticated else {
            lastError = "Sign in with Google before capturing a look."
            selectedTab = .search
            return
        }
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
            selectedTab = .search
            lastError = "Add a fashion image so Stylezam can search the correct piece."
        }
    }
}

#if DEBUG
private extension AppModel {
    struct DeviceVisionItemReport: Encodable {
        let categoryID: Int?
        let label: String
        let confidence: Double
        let box: BoundingBoxDTO
        let boxCropFilename: String?
        let boxCropBytes: Int?
        let boxCropWidth: Int?
        let boxCropHeight: Int?
        let cropFilename: String?
        let cropBytes: Int?
        let transparentPixels: Int?
        let softEdgePixels: Int?
        let opaquePixels: Int?
    }

    struct DeviceVisionReport: Encodable {
        let createdAt: Date
        let deviceModel: String
        let systemVersion: String
        let modelID: String
        let modelVersion: String
        let inputBytes: Int
        let elapsedMilliseconds: Double
        let pipeline: GarmentPipelineMetrics?
        let detectionMethod: GarmentDetectionMethod
        let scanID: UUID
        let items: [DeviceVisionItemReport]
    }

    struct AlphaCounts {
        let transparent: Int
        let softEdge: Int
        let opaque: Int
    }

    func runDeviceVisionSmokeTestIfRequested() async {
        guard let requestedFilename = ProcessInfo.processInfo.environment[
            "STYLEZAM_DEVICE_VISION_INPUT"
        ], !requestedFilename.isEmpty else { return }
        let filename = URL(fileURLWithPath: requestedFilename).lastPathComponent
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let inputURL = documents.appending(path: filename)
        let outputDirectory = documents.appending(
            path: "StylezamVisionSmoke",
            directoryHint: .isDirectory
        )
        do {
            let input = try Data(contentsOf: inputURL)
            print(
                "STYLEZAM_DEVICE_MODEL_STATUS \(String(describing: modelPack.status)) "
                    + "url=\(modelPack.activeModelURL?.path ?? "nil") "
                    + "error=\(modelPack.lastError ?? "nil")"
            )
            guard let modelURL = modelPack.activeModelURL,
                  let manifest = modelPack.manifest
            else {
                throw ModelPackError.unavailable(
                    modelPack.lastError ?? ModelPackError.missingModel.localizedDescription
                )
            }
            let started = ProcessInfo.processInfo.systemUptime
            let detection = try await visionEngine.analyze(
                imageData: input,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: settings.maxDetectedItems
            )
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            let scan = try library.addScan(
                imageData: input,
                origin: .photoLibrary,
                mode: .imported,
                detection: detection
            )
            try? FileManager.default.removeItem(at: outputDirectory)
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            let items = try detection.candidates.enumerated().map { index, candidate in
                let boxCropFilename: String?
                if let crop = candidate.boxCropData {
                    let filename = String(format: "box-crop-%02d.jpg", index + 1)
                    try crop.write(
                        to: outputDirectory.appending(path: filename),
                        options: .atomic
                    )
                    boxCropFilename = filename
                } else {
                    boxCropFilename = nil
                }
                let boxCropImage = candidate.boxCropData.flatMap(UIImage.init(data:))
                let cropFilename: String?
                if let crop = candidate.cropData {
                    let filename = String(format: "crop-%02d.png", index + 1)
                    try crop.write(
                        to: outputDirectory.appending(path: filename),
                        options: .atomic
                    )
                    cropFilename = filename
                } else {
                    cropFilename = nil
                }
                let alpha = candidate.cropData.flatMap(Self.alphaCounts)
                return DeviceVisionItemReport(
                    categoryID: manifest.classNames.firstIndex(of: candidate.localLabel),
                    label: candidate.localLabel,
                    confidence: candidate.confidence,
                    box: candidate.box,
                    boxCropFilename: boxCropFilename,
                    boxCropBytes: candidate.boxCropData?.count,
                    boxCropWidth: boxCropImage.map { Int($0.size.width) },
                    boxCropHeight: boxCropImage.map { Int($0.size.height) },
                    cropFilename: cropFilename,
                    cropBytes: candidate.cropData?.count,
                    transparentPixels: alpha?.transparent,
                    softEdgePixels: alpha?.softEdge,
                    opaquePixels: alpha?.opaque
                )
            }
            let report = DeviceVisionReport(
                createdAt: .now,
                deviceModel: UIDevice.current.model,
                systemVersion: UIDevice.current.systemVersion,
                modelID: manifest.modelID,
                modelVersion: manifest.version,
                inputBytes: input.count,
                elapsedMilliseconds: elapsed,
                pipeline: detection.metrics,
                detectionMethod: detection.method,
                scanID: scan.id,
                items: items
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let reportURL = outputDirectory.appending(path: "report.json")
            try encoder.encode(report).write(to: reportURL, options: .atomic)
            activeScanID = scan.id
            selectedTab = .library
            print("STYLEZAM_DEVICE_VISION_REPORT \(reportURL.path)")
        } catch {
            let message = "STYLEZAM_DEVICE_VISION_ERROR \(error.localizedDescription)"
            lastError = message
            print(message)
            let bundleItems = (
                try? FileManager.default.contentsOfDirectory(
                    at: Bundle.main.bundleURL,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
            )?.map(\.lastPathComponent).sorted() ?? []
            let diagnostic = [
                message,
                "modelStatus=\(String(describing: modelPack.status))",
                "modelURL=\(modelPack.activeModelURL?.path ?? "nil")",
                "modelError=\(modelPack.lastError ?? "nil")",
                "bundleURL=\(Bundle.main.bundleURL.path)",
                "bundleItems=\(bundleItems)",
            ].joined(separator: "\n")
            try? Data(diagnostic.utf8).write(
                to: documents.appending(path: "StylezamVisionSmoke-error.txt"),
                options: .atomic
            )
        }
    }

    nonisolated static func alphaCounts(_ data: Data) -> AlphaCounts? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var transparent = 0
        var softEdge = 0
        var opaque = 0
        for alphaIndex in stride(from: 3, to: pixels.count, by: 4) {
            switch pixels[alphaIndex] {
            case 0: transparent += 1
            case 255: opaque += 1
            default: softEdge += 1
            }
        }
        return AlphaCounts(
            transparent: transparent,
            softEdge: softEdge,
            opaque: opaque
        )
    }
}
#endif

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
