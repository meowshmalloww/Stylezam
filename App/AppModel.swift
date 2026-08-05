import Foundation
import Observation
import UIKit

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

    @ObservationIgnored private let captureActivityManager = CaptureActivityManager()
    @ObservationIgnored private let visionEngine = GarmentVisionEngine()
    @ObservationIgnored private let duplicateGuard = GarmentDuplicateGuard()
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private let productSearchService = ProductSearchService()
    @ObservationIgnored private var lastCaptureRequest: Double = 0
    @ObservationIgnored private var lastLiveScreenRequest: Double = 0

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
#if DEBUG
        await runDeviceVisionSmokeTestIfRequested()
#endif
        handleExternalCaptureRequest()
        handlePendingScanNotification()
        if let pending = library.consumePendingShare() {
            await consumePendingInput(pending)
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
                throw ModelPackError.unavailable(
                    modelPack.lastError ?? ModelPackError.missingModel.localizedDescription
                )
            }

            let rawDetection = try await visionEngine.analyze(
                imageData: imageData,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: settings.maxDetectedItems,
                // Live camera accepts a full-quality still after preview
                // consensus, so it benefits from the same bounded refinement
                // as Photo mode. Screen capture remains single-pass to protect
                // sustained latency and thermals.
                enableAdaptiveDetail: mode != .screen
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
                    candidates: novel,
                    metrics: rawDetection.metrics
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
            if navigateToLibrary {
                selectedTab = .library
            }
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
            selectedTab = .search
            lastError = nil
        case "live-screen":
            if account.isAuthenticated { liveScreen.presentSystemPicker() }
        case "try-on":
            isTryOnPresented = true
        case "library":
            selectedTab = .library
        default:
            break
        }
    }

    func handleExternalCaptureRequest() {
        let liveRequestedAt = StylezamShared.defaults.double(
            forKey: StylezamShared.liveScreenRequestKey
        )
        if liveRequestedAt > lastLiveScreenRequest {
            lastLiveScreenRequest = liveRequestedAt
            if account.isAuthenticated { liveScreen.presentSystemPicker() }
        }
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
