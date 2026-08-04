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
    var activeSearch: SearchJobDTO?
    var activeSearchImageData: Data?
    var activeSearchOrigin: CaptureOrigin = .text
    var searchResults: [ProductResultDTO] = []
    var capabilities: CapabilitiesDTO?
    var serverMessage: String?
    var lastError: String?
    var activeScanID: UUID?
    var isAnalyzingCapture = false
    var captureStatus: String?
    var latestPreviewCandidates: [GarmentCandidate] = []

    @ObservationIgnored private let activityManager = SearchActivityManager()
    @ObservationIgnored private let captureActivityManager = CaptureActivityManager()
    @ObservationIgnored private let visionEngine = GarmentVisionEngine()
    @ObservationIgnored private let duplicateGuard = GarmentDuplicateGuard()
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastCaptureRequest: Double = 0
    @ObservationIgnored private var latestCaptureActivityID: String?

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
        await refreshCapabilities()
        await modelPack.refresh(using: try? settings.client())
        handleExternalCaptureRequest()
        handlePendingNotification()
        handlePendingScanNotification()
        if let pending = library.consumePendingShare() {
            await consumePendingInput(pending)
        }
    }

    func refreshCapabilities() async {
        do {
            let client = try settings.client()
            async let health = client.health()
            async let capabilityRequest = client.capabilities()
            let (healthResponse, capabilityResponse) = try await (health, capabilityRequest)
            capabilities = capabilityResponse
            serverMessage = "Connected · API \(healthResponse.version)"
        } catch {
            capabilities = nil
            serverMessage = error.localizedDescription
        }
    }

    func presentCamera() {
        isCapturePresented = true
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
        captureStatus = "Finding pieces"
        lastError = nil
        let activityID = UUID().uuidString
        latestCaptureActivityID = activityID
        await captureActivityManager.start(
            id: activityID,
            source: mode.activityLabel,
            phase: "Finding pieces"
        )
        defer { isAnalyzingCapture = false }

        do {
            let rawDetection = try await visionEngine.analyze(
                imageData: imageData,
                modelURL: modelPack.activeModelURL,
                manifest: modelPack.manifest,
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
            captureStatus = detection.candidates.isEmpty
                ? "Saved · no distinct pieces found"
                : "Labeling \(detection.candidates.count) pieces"
            await captureActivityManager.update(
                captureID: activityID,
                phase: captureStatus ?? "Labeling pieces",
                itemCount: detection.candidates.count,
                isComplete: false,
                failed: false
            )

            guard !detection.candidates.isEmpty else {
                library.markAnalysisUnavailable(for: scan.id)
                await captureActivityManager.finish(
                    captureID: activityID,
                    itemCount: 0,
                    failed: false
                )
                if settings.notificationsEnabled,
                   await notifications.requestAuthorization()
                {
                    await notifications.captureFinished(
                        itemCount: 0,
                        scanID: scan.id,
                        detailedLabelsReady: false
                    )
                }
                return scan
            }
            Task { [weak self] in
                await self?.enrichScan(
                    id: scan.id,
                    candidates: detection.candidates,
                    activityID: activityID
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
        try await visionEngine.analyze(
            imageData: imageData,
            modelURL: modelPack.activeModelURL,
            manifest: modelPack.manifest,
            maxItems: settings.maxDetectedItems
        )
    }

    /// Sends the inspector's real segmented crops through the same authenticated
    /// endpoint used to enrich a saved Library scan, without mutating the Library.
    func inspectGarmentLabels(
        for candidates: [GarmentCandidate]
    ) async throws -> GarmentAnalysisDTO {
        let client = try settings.client()
        return try await client.analyzeGarments(candidates)
    }

    @discardableResult
    func startSearch(_ input: SearchInput, saveCapture: Bool = true) async -> String? {
        guard !input.isEmpty else { return nil }
        if let previous = activeSearch, !previous.status.isTerminal {
            searchTask?.cancel()
            if let client = try? settings.client() {
                try? await client.deleteSearch(id: previous.id)
            }
        }
        searchTask?.cancel()
        await activityManager.end()
        activeSearch = nil
        activeSearchImageData = input.imageData
        activeSearchOrigin = input.origin
        searchResults = []
        lastError = nil
        selectedTab = .search
        isCapturePresented = false
        do {
            let client = try settings.client()
            let submitted = try await client.createSearch(
                query: input.query,
                imageData: input.imageData,
                selectedRegion: input.selectedRegion
            )
            activeSearch = submitted
            if saveCapture {
                _ = try? library.addCapture(input: input, searchID: submitted.id)
            }
            await activityManager.start(for: submitted)
            searchTask = Task { [weak self] in
                await self?.pollSearch(id: submitted.id)
            }
            return submitted.id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func resetSearch() {
        searchTask?.cancel()
        searchTask = nil
        activeSearch = nil
        activeSearchImageData = nil
        activeSearchOrigin = .text
        searchResults = []
        lastError = nil
        Task { await activityManager.end() }
    }

    func cancelActiveSearchAndReset() async {
        let runningID = activeSearch.flatMap { $0.status.isTerminal ? nil : $0.id }
        searchTask?.cancel()
        searchTask = nil
        await activityManager.end()
        activeSearch = nil
        activeSearchImageData = nil
        activeSearchOrigin = .text
        searchResults = []
        lastError = nil
        guard let runningID, let client = try? settings.client() else { return }
        try? await client.deleteSearch(id: runningID)
    }

    func focusOnDetectedItem(_ item: DetectedItemDTO) async {
        guard let job = activeSearch else { return }
        var sourceData = activeSearchImageData
        if sourceData == nil, let inputImageURL = job.inputImageURL {
            do {
                let (downloaded, response) = try await URLSession.shared.data(from: inputImageURL)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else {
                    throw APIClientError.invalidResponse
                }
                sourceData = downloaded
            } catch {
                lastError = "The original capture could not be loaded for item selection."
                return
            }
        }
        guard let sourceData else {
            lastError = "The original capture is no longer available. Capture the look again to select an item."
            return
        }
        await startSearch(
            SearchInput(
                query: job.query,
                imageData: sourceData,
                origin: activeSearchOrigin,
                selectedRegion: item.box
            ),
            saveCapture: false
        )
    }

    func retryActiveSearch() async {
        guard let job = activeSearch else { return }
        var sourceData = activeSearchImageData
        if sourceData == nil, let inputImageURL = job.inputImageURL {
            do {
                let (downloaded, response) = try await URLSession.shared.data(from: inputImageURL)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else {
                    throw APIClientError.invalidResponse
                }
                sourceData = downloaded
            } catch {
                lastError = "The original capture could not be loaded for a new attempt."
                return
            }
        }
        let retryInput = SearchInput(
            query: job.query,
            imageData: sourceData,
            origin: activeSearchOrigin,
            selectedRegion: job.selectedRegion
        )
        guard !retryInput.isEmpty else {
            lastError = "The original search input is no longer available."
            return
        }
        let previousID = job.id
        if let replacementID = await startSearch(retryInput, saveCapture: false) {
            if library.replaceSearchID(previousID, with: replacementID) {
                Task {
                    guard let client = try? settings.client() else { return }
                    try? await client.deleteSearch(id: previousID)
                }
            }
        }
    }

    func deleteCapture(_ capture: SavedCapture) {
        library.deleteCapture(capture)
        Task {
            guard let client = try? settings.client() else { return }
            try? await client.deleteSearch(id: capture.searchID)
        }
    }

    func deleteScan(_ scan: SavedScan) {
        library.deleteScan(scan)
        if activeScanID == scan.id {
            activeScanID = nil
        }
    }

    func clearLibrary() {
        let searchIDs = library.captures.map(\.searchID)
        do {
            try library.clear()
        } catch {
            lastError = error.localizedDescription
            return
        }
        Task {
            guard let client = try? settings.client() else { return }
            await withTaskGroup(of: Void.self) { group in
                for id in searchIDs {
                    group.addTask { try? await client.deleteSearch(id: id) }
                }
            }
        }
    }

    func resumeSearch(id: String, imageData: Data? = nil) {
        searchTask?.cancel()
        activeSearchImageData = imageData
        activeSearchOrigin = imageData == nil ? .text : .photoLibrary
        selectedTab = .search
        searchTask = Task { [weak self] in
            await self?.pollSearch(id: id)
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
                selectedTab = .search
            }
        case "search":
            let identifier = url.pathComponents.dropFirst().first
            if let identifier { resumeSearch(id: identifier) }
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

    func handlePendingNotification(searchID suppliedID: String? = nil) {
        let defaults = StylezamShared.defaults
        let searchID = suppliedID ?? defaults.string(forKey: StylezamShared.pendingSearchIDKey)
        guard let searchID, !searchID.isEmpty else { return }
        defaults.removeObject(forKey: StylezamShared.pendingSearchIDKey)
        resumeSearch(id: searchID)
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

    private func pollSearch(id: String) async {
        do {
            let client = try settings.client()
            var pollDelay = 1.2
            while !Task.isCancelled {
                let job = try await client.search(id: id)
                let changed = activeSearch?.status != job.status
                    || activeSearch?.phase != job.phase
                    || activeSearch?.progress != job.progress
                    || activeSearch?.resultCount != job.resultCount
                    || activeSearch?.errorMessage != job.errorMessage
                if changed {
                    activeSearch = job
                    await activityManager.update(with: job)
                    pollDelay = 1.2
                } else {
                    pollDelay = min(pollDelay * 1.4, 3.2)
                }
                if job.status == .completed {
                    let page = try await client.results(searchID: id)
                    searchResults = page.results
                    if settings.notificationsEnabled {
                        let allowed = await notifications.requestAuthorization()
                        if allowed {
                            await notifications.searchFinished(
                                resultCount: page.total,
                                searchID: id
                            )
                        }
                    }
                    return
                }
                if job.status == .failed || job.status == .cancelled {
                    lastError = job.errorMessage ?? "The search could not finish."
                    return
                }
                try await Task.sleep(for: .seconds(pollDelay))
            }
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func consumePendingInput(_ input: SearchInput) async {
        if let imageData = input.imageData {
            _ = await processCapture(
                imageData: imageData,
                origin: input.origin,
                mode: input.origin == .screenCapture ? .screen : .imported
            )
        } else {
            await startSearch(input)
        }
    }

    private func enrichScan(
        id: UUID,
        candidates: [GarmentCandidate],
        activityID: String
    ) async {
        do {
            let client = try settings.client()
            let analysis = try await client.analyzeGarments(candidates)
            try library.applyAnalysis(analysis, to: id)
            guard library.scans.contains(where: { $0.id == id }) else { return }
            let acceptedCount = analysis.items.filter(\.accepted).count
            if latestCaptureActivityID == activityID {
                captureStatus = acceptedCount == 1
                    ? "1 piece ready"
                    : "\(acceptedCount) pieces ready"
            }
            await captureActivityManager.finish(
                captureID: activityID,
                itemCount: acceptedCount,
                failed: false
            )
            if settings.notificationsEnabled,
               await notifications.requestAuthorization()
            {
                await notifications.captureFinished(
                    itemCount: acceptedCount,
                    scanID: id,
                    detailedLabelsReady: true
                )
            }
        } catch {
            library.markAnalysisUnavailable(for: id)
            guard library.scans.contains(where: { $0.id == id }) else { return }
            if latestCaptureActivityID == activityID {
                captureStatus = "Saved locally · detailed labels unavailable"
                serverMessage = error.localizedDescription
            }
            await captureActivityManager.finish(
                captureID: activityID,
                itemCount: candidates.count,
                failed: false
            )
            if settings.notificationsEnabled,
               await notifications.requestAuthorization()
            {
                await notifications.captureFinished(
                    itemCount: candidates.count,
                    scanID: id,
                    detailedLabelsReady: false
                )
            }
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
