import Foundation
import ImageIO
import Security
import UIKit
import Vision

enum YouCamCredentialStore {
    private static let service = "com.stylezam.youcam"
    private static let account = "api-key"

    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var isConfigured: Bool {
        if let apiKey, !apiKey.isEmpty { return true }
        if let value = ProcessInfo.processInfo.environment["STYLEZAM_YOUCAM_API_KEY"], !value.isEmpty { return true }
        if let value = ProcessInfo.processInfo.environment["YOUCAM_API_KEY"], !value.isEmpty { return true }
        return false
    }

#if DEBUG
    static func importDebugEnvironment() {
        let environment = ProcessInfo.processInfo.environment
        let value = environment["STYLEZAM_YOUCAM_API_KEY"] ?? environment["YOUCAM_API_KEY"]
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // A developer install must replace an older device-only credential. Keeping the first
        // imported value forever made a newly provisioned .env key appear broken after reinstall.
        try? save(value)
    }
#endif

    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(lookup as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var item = lookup
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw YouCamTryOnError.server("The API key could not be saved securely.") }
    }
}

enum YouCamTryOnError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case server(String)
    case timedOut
    case videoTimedOut

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "YouCam is not provisioned in this build. Ask the developer to configure STYLEZAM_YOUCAM_API_KEY or the credential gateway."
        case .invalidResponse:
            "YouCam returned an unreadable response."
        case let .server(message):
            message
        case .timedOut:
            "YouCam is still processing this look. Try again in a moment."
        case .videoTimedOut:
            "YouCam is still creating the motion preview. Try again in a moment."
        }
    }
}

struct YouCamVideoResult: Sendable {
    let jobID: String
    let videoData: Data
}

enum YouCamVideoResolution: String, CaseIterable, Identifiable, Sendable {
    case p480 = "480"
    case p720 = "720"
    case p1080 = "1080"

    var id: String { rawValue }
    var title: String { "\(rawValue)p" }
}

struct YouCamFinishingOptions: Sendable, Equatable {
    var removesBackground = false
    var changesBackground = false
    var backgroundPrompt = "Clean neutral editorial studio with soft natural shadows"
    var improvesLighting = false
    var enhancesPhoto = false

    var enabledTaskCount: Int {
        [removesBackground, changesBackground, improvesLighting, enhancesPhoto]
            .filter { $0 }
            .count
    }

    /// Exact feature-catalog endpoints used by the optional finishing pipeline. Keeping this
    /// beside the switches prevents the UI task count and provider routing from drifting apart.
    var enabledTasks: [(endpoint: String, title: String)] {
        var tasks: [(String, String)] = []
        if enhancesPhoto { tasks.append(("enhance", "detail enhancement")) }
        if improvesLighting { tasks.append(("lighting", "lighting")) }
        if changesBackground { tasks.append(("bg-replace", "background change")) }
        if removesBackground { tasks.append(("sod", "background removal")) }
        return tasks
    }

    static let none = YouCamFinishingOptions()
}

struct YouCamFeatureEntitlement: Identifiable, Sendable {
    let category: TryOnCategory
    let endpoint: String
    let description: String?
    let unitCost: Double?
    let unit: String?
    let isEntitled: Bool

    var id: String { category.rawValue }
}

struct YouCamEntitlementReport: Sendable {
    let checkedAt: Date
    let features: [YouCamFeatureEntitlement]
    let entitledEndpoints: Set<String>

    var missingCategories: [TryOnCategory] {
        features.filter { !$0.isEntitled }.map(\.category)
    }

    var supportsEveryStylezamCategory: Bool { missingCategories.isEmpty }
}

private enum YouCamTaskCreationRequest: Sendable {
    case tryOn(
        endpoint: String,
        category: TryOnCategory,
        garmentRegion: TryOnGarmentRegion,
        sourceID: String,
        referenceID: String,
        gender: TryOnGender
    )
    case video(endpoint: String, sourceID: String, resolution: YouCamVideoResolution)

    var endpoint: String {
        switch self {
        case let .tryOn(endpoint, _, _, _, _, _), let .video(endpoint, _, _):
            endpoint
        }
    }
}

/// Relays an uncancelled task-creation request back to its caller. Cancellation resumes the
/// local waiter immediately, while a request that was already dispatched remains alive long
/// enough to recover its task ID for remote cleanup.
private actor YouCamTaskCreationRelay {
    private enum State {
        case pending
        case waiting(CheckedContinuation<String, any Error>)
        case succeeded(String)
        case failed(any Error)
        case cancelled
    }

    private var state: State = .pending

    func beginRequest() -> Bool {
        if case .cancelled = state { return false }
        return true
    }

    func value() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            switch state {
            case .pending:
                state = .waiting(continuation)
            case let .succeeded(taskID):
                continuation.resume(returning: taskID)
            case let .failed(error):
                continuation.resume(throwing: error)
            case .cancelled:
                continuation.resume(throwing: CancellationError())
            case .waiting:
                continuation.resume(
                    throwing: YouCamTryOnError.server("YouCam task creation was already being observed.")
                )
            }
        }
    }

    /// Returns true when the caller already cancelled and this task now needs detached cleanup.
    func succeed(_ taskID: String) -> Bool {
        switch state {
        case .pending:
            state = .succeeded(taskID)
            return false
        case let .waiting(continuation):
            state = .succeeded(taskID)
            continuation.resume(returning: taskID)
            return false
        case .cancelled:
            return true
        case .succeeded, .failed:
            return false
        }
    }

    func fail(_ error: any Error) {
        switch state {
        case .pending:
            state = .failed(error)
        case let .waiting(continuation):
            state = .failed(error)
            continuation.resume(throwing: error)
        case .cancelled, .succeeded, .failed:
            break
        }
    }

    /// Returns an accepted task ID when creation won the race with cancellation.
    func cancel() -> String? {
        switch state {
        case .pending:
            state = .cancelled
            return nil
        case let .waiting(continuation):
            state = .cancelled
            continuation.resume(throwing: CancellationError())
            return nil
        case let .succeeded(taskID):
            state = .cancelled
            return taskID
        case .failed:
            state = .cancelled
            return nil
        case .cancelled:
            return nil
        }
    }
}

actor YouCamTryOnService {
    private static let videoEndpoint = "image-to-video/youcam"
    private static let remoteCleanupPollLimit = 120
    private static let remoteCleanupFailureLimit = 3
    private static let videoPrompt = "Keep the person, face, body, outfit, accessories, colors, textures, lighting, and background consistent. Add only subtle fashion-view motion: slowly turn a few degrees to one side, then gently return toward the camera. Use a fixed camera and natural fabric movement."
    private static let videoNegativePrompt = "changed clothing, missing accessories, altered colors, altered logos, added garments, body distortion, face distortion, extra limbs, extra fingers, camera cuts, zoom, fast motion, blur, flicker, low quality"

    private let baseURL = URL(string: "https://yce-api-01.makeupar.com")!
    private let session: URLSession
    private var scheduledCleanupTaskIDs: Set<String> = []
    private var entitlementCache: (report: YouCamEntitlementReport, expiresAt: Date)?

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Each supported Perfect Corp try-on task creates both source and reference
    /// file IDs through the documented shared File API before starting its
    /// category-specific task. Keep this pure so it is testable without credentials.
    nonisolated static func uploadPath(for _: TryOnCategory) -> String {
        "/s2s/v2.0/file"
    }

    func validateConnection() async throws {
        let report = try await entitlementReport()
        guard report.features.contains(where: \.isEntitled) else {
            throw YouCamTryOnError.server("This YouCam account is connected but no supported Stylezam try-on task is entitled.")
        }
    }

    /// Reads the account's paginated feature catalog. This verifies entitlement without
    /// uploading an image, creating a task, or consuming a generated-result unit.
    func entitlementReport(forceRefresh: Bool = false) async throws -> YouCamEntitlementReport {
        if !forceRefresh,
           let entitlementCache,
           entitlementCache.expiresAt > Date()
        {
            return entitlementCache.report
        }
        var token: String?
        var entitled: [String: (description: String?, amount: Double?, unit: String?)] = [:]

        repeat {
            let queryItems = token.map { [URLQueryItem(name: "starting_token", value: $0)] } ?? []
            let json = try await requestJSON(
                path: "/s2s/v2.0/credit/feature-cost",
                method: "GET",
                queryItems: queryItems
            )
            guard let root = json as? [String: Any],
                  let result = root["result"] as? [String: Any]
            else { throw YouCamTryOnError.invalidResponse }

            for sku in result["skus"] as? [[String: Any]] ?? [] {
                guard let rawURL = sku["run_task_url"] as? String,
                      let url = URL(string: rawURL)
                else { continue }
                let endpoint = url.path
                    .replacingOccurrences(of: "/s2s/v2.0/task/", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                entitled[endpoint] = (
                    sku["description"] as? String,
                    (sku["amount"] as? NSNumber)?.doubleValue,
                    sku["unit"] as? String
                )
            }
            token = result["next_token"] as? String
        } while token?.isEmpty == false

        let features = TryOnCategory.allCases.map { category in
            let feature = entitled[category.youCamEndpoint]
            return YouCamFeatureEntitlement(
                category: category,
                endpoint: category.youCamEndpoint,
                description: feature?.description,
                unitCost: feature?.amount,
                unit: feature?.unit,
                isEntitled: feature != nil
            )
        }
        let report = YouCamEntitlementReport(
            checkedAt: Date(),
            features: features,
            entitledEndpoints: Set(entitled.keys)
        )
        entitlementCache = (report, Date().addingTimeInterval(15 * 60))
        return report
    }

    func render(
        personImage: Data,
        items: [TryOnTrayItem],
        gender: TryOnGender,
        finishing: YouCamFinishingOptions = .none,
        progress: @Sendable (Int, Int, String) async -> Void
    ) async throws -> (jobID: String, imageData: Data) {
        guard !items.isEmpty else { throw YouCamTryOnError.server("Select at least one item.") }
        guard !(finishing.removesBackground && finishing.changesBackground) else {
            throw YouCamTryOnError.server(
                "Choose either background removal or background change, not both."
            )
        }
        let entitlement = try await entitlementReport()
        let missing = Set(items.map(\.category)).filter { category in
            !entitlement.features.contains { $0.category == category && $0.isEntitled }
        }
        guard missing.isEmpty else {
            let names = missing.map(\.title).sorted().joined(separator: ", ")
            throw YouCamTryOnError.server(
                "This build's YouCam account is not entitled for the selected task: \(names)."
            )
        }
        let missingFinishes = finishing.enabledTasks.filter {
            !entitlement.entitledEndpoints.contains($0.endpoint)
        }
        guard missingFinishes.isEmpty else {
            let names = missingFinishes.map(\.title).joined(separator: ", ")
            throw YouCamTryOnError.server(
                "This YouCam account is not entitled for \(names). Turn that finish off or enable its Perfect Corp task before trying again. Nothing was uploaded."
            )
        }
        let requiresGender = items.contains {
            [.bag, .scarf, .shoes, .hat].contains($0.category)
        }
        guard !requiresGender || gender.isProviderValue else {
            throw YouCamTryOnError.server(
                "Choose Automatic, Male, or Female again before starting this accessory try-on."
            )
        }
        let referenceImages = try items.map { item -> Data in
            guard item.region == .lowerBody else { return item.imageData }
            guard let referenceImageData = item.referenceImageData,
                  !referenceImageData.isEmpty
            else {
                throw YouCamTryOnError.server(
                    "\(item.title) needs a photo showing the garment worn for lower-body try-on. Use the worn-reference action in the try-on rail, then try again."
                )
            }
            return referenceImageData
        }
        for (item, referenceImage) in zip(items, referenceImages) {
            try Self.validateReferenceImage(referenceImage, for: item)
        }
        var current = personImage
        var lastTaskID = UUID().uuidString
        let totalTasks = items.count + finishing.enabledTaskCount

        for (index, item) in items.enumerated() {
            await progress(index, totalTasks, "Preparing \(item.title)")
            let endpoint = item.category.youCamEndpoint
            await progress(index, totalTasks, "Uploading your photo")
            let sourceID = try await upload(current)
            await progress(index, totalTasks, "Uploading the found piece")
            // Library crops retain their alpha channel locally so the user sees the isolated
            // garment. Perfect Corp's reference-image models are more reliable with the same
            // garment composited onto a neutral opaque canvas, so flatten only the copy leaving
            // the phone for this opted-in provider task—not the Library original.
            let referenceID = try await upload(
                referenceImages[index],
                flattenTransparency: true
            )
            await progress(index, totalTasks, "Starting YouCam")
            let taskID = try await createTask(
                endpoint: endpoint,
                category: item.category,
                garmentRegion: item.region,
                sourceID: sourceID,
                referenceID: referenceID,
                gender: gender
            )
            lastTaskID = taskID
            do {
                await progress(index, totalTasks, "Creating your try-on")
                let resultURL = try await poll(endpoint: endpoint, taskID: taskID)
                await progress(index, totalTasks, "Downloading the result")
                let rendered = try await downloadProcessedImage(
                    from: resultURL,
                    preserveTransparency: false
                )
                try Self.validateSingleItemScenePreservation(
                    source: current,
                    result: rendered,
                    category: item.category,
                    garmentRegion: item.region
                )
                current = rendered
            } catch {
                scheduleRemoteCleanup(endpoint: endpoint, taskID: taskID)
                throw error
            }
            await deleteFinishedTaskIgnoringCancellation(taskID)
        }

        var completed = items.count
        if finishing.enhancesPhoto {
            await progress(completed, totalTasks, "Enhancing detail")
            let output = try await processPhoto(
                current,
                endpoint: "enhance",
                parameters: ["scale": 1],
                preserveTransparency: false
            )
            try Self.validateFinishingSubjectPreservation(
                source: current,
                result: output.imageData,
                operation: "detail enhancement",
                allowsBackgroundChange: false
            )
            current = output.imageData
            lastTaskID = output.taskID
            completed += 1
        }
        if finishing.improvesLighting {
            await progress(completed, totalTasks, "Balancing light")
            let output = try await processPhoto(
                current,
                endpoint: "lighting",
                preserveTransparency: false
            )
            try Self.validateFinishingSubjectPreservation(
                source: current,
                result: output.imageData,
                operation: "lighting",
                allowsBackgroundChange: false
            )
            current = output.imageData
            lastTaskID = output.taskID
            completed += 1
        }
        if finishing.changesBackground {
            await progress(completed, totalTasks, "Changing background")
            var parameters: [String: Any] = ["type": "prompt"]
            let prompt = finishing.backgroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty { parameters["prompt"] = prompt }
            let output = try await processPhoto(
                current,
                endpoint: "bg-replace",
                parameters: parameters,
                preserveTransparency: false
            )
            try Self.validateFinishingSubjectPreservation(
                source: current,
                result: output.imageData,
                operation: "background change",
                allowsBackgroundChange: true
            )
            current = output.imageData
            lastTaskID = output.taskID
            completed += 1
        }
        if finishing.removesBackground {
            await progress(completed, totalTasks, "Removing background")
            let output = try await processPhoto(
                current,
                endpoint: "sod",
                preserveTransparency: true
            )
            try Self.validateFinishingSubjectPreservation(
                source: current,
                result: output.imageData,
                operation: "background removal",
                allowsBackgroundChange: true
            )
            current = output.imageData
            lastTaskID = output.taskID
            completed += 1
        }
        await progress(totalTasks, totalTasks, "Look ready")
        return (lastTaskID, current)
    }

    private func processPhoto(
        _ imageData: Data,
        endpoint: String,
        parameters: [String: Any] = [:],
        preserveTransparency: Bool
    ) async throws -> (taskID: String, imageData: Data) {
        let sourceID = try await upload(imageData)
        var body = parameters
        body["src_file_id"] = sourceID
        let json = try await requestJSON(
            path: "/s2s/v2.0/task/\(endpoint)",
            method: "POST",
            body: body
        )
        guard let taskID = recursiveValue(for: "task_id", in: json) as? String else {
            throw serverError(from: json)
        }
        do {
            let resultURL = try await poll(endpoint: endpoint, taskID: taskID)
            let result = try await downloadProcessedImage(
                from: resultURL,
                preserveTransparency: preserveTransparency
            )
            await deleteFinishedTaskIgnoringCancellation(taskID)
            return (taskID, result)
        } catch {
            scheduleRemoteCleanup(endpoint: endpoint, taskID: taskID)
            throw error
        }
    }

    private func downloadProcessedImage(
        from url: URL,
        preserveTransparency: Bool
    ) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty,
              data.count < 30_000_000,
              UIImage(data: data) != nil
        else {
            throw YouCamTryOnError.server("The generated image could not be downloaded.")
        }
        if preserveTransparency {
            guard let image = UIImage(data: data),
                  let png = image.pngData(),
                  Self.hasUsefulTransparency(png)
            else {
                throw YouCamTryOnError.server(
                    "YouCam finished background removal but returned an opaque image. Stylezam rejected it instead of showing the old background. Try the removal again or keep the original background."
                )
            }
            return png
        }
        guard let normalized = await ImageEncoding.normalizedJPEGAsync(from: data) else {
            throw YouCamTryOnError.server("YouCam returned an unsupported result image.")
        }
        return normalized
    }

    func animate(imageData: Data) async throws -> YouCamVideoResult {
        try await animate(imageData: imageData, resolution: .p480, progress: { _ in })
    }

    func animate(
        imageData: Data,
        resolution: YouCamVideoResolution = .p480,
        progress: @Sendable (String) async -> Void
    ) async throws -> YouCamVideoResult {
        try Task.checkCancellation()
        await progress("Preparing motion preview")
        let sourceID = try await uploadVideoSource(imageData)
        try Task.checkCancellation()

        await progress("Starting YouCam video")
        let taskID = try await createVideoTask(sourceID: sourceID, resolution: resolution)

        do {
            await progress("Creating motion preview")
            let resultURL = try await pollVideo(taskID: taskID)
            try Task.checkCancellation()

            await progress("Downloading motion preview")
            let videoData = try await downloadVideo(from: resultURL)
            try Task.checkCancellation()

            await deleteFinishedTaskIgnoringCancellation(taskID)
            await progress("Motion preview ready")
            return YouCamVideoResult(jobID: taskID, videoData: videoData)
        } catch {
            scheduleRemoteCleanup(endpoint: Self.videoEndpoint, taskID: taskID)
            throw error
        }
    }

    private func upload(
        _ sourceData: Data,
        flattenTransparency: Bool = false
    ) async throws -> String {
        guard let prepared = preparedUpload(
            from: sourceData,
            flattenTransparency: flattenTransparency
        ) else {
            throw YouCamTryOnError.server("The selected image could not be prepared for try-on.")
        }
        let data = prepared.data
        guard data.count < 10_000_000 else {
            throw YouCamTryOnError.server("Each try-on image must be smaller than 10 MB.")
        }
        guard let image = UIImage(data: data),
              min(image.size.width, image.size.height) >= 512,
              max(image.size.width, image.size.height) <= 4096
        else {
            throw YouCamTryOnError.server("Try-on images must be readable, at least 512 pixels per side, and no larger than 4096 pixels on the longest side.")
        }
        return try await uploadPrepared(prepared)
    }

    private func uploadVideoSource(_ sourceData: Data) async throws -> String {
        guard let prepared = preparedUpload(from: sourceData) else {
            throw YouCamTryOnError.server("The finished try-on could not be prepared for video.")
        }
        let data = prepared.data
        guard data.count < 10_000_000 else {
            throw YouCamTryOnError.server("The image for the motion preview must be smaller than 10 MB.")
        }
        guard let image = UIImage(data: data),
              image.size.width > 0,
              image.size.height > 0,
              max(image.size.width, image.size.height) <= 4096
        else {
            throw YouCamTryOnError.server("The image for the motion preview must be readable and no larger than 4096 pixels on the longest side.")
        }
        let aspectRatio = max(image.size.width, image.size.height) / min(image.size.width, image.size.height)
        guard aspectRatio <= 2.5 else {
            throw YouCamTryOnError.server("The image is too wide or tall for YouCam video. Choose a portrait or landscape photo with less empty space.")
        }
        return try await uploadPrepared(prepared)
    }

    private func uploadPrepared(
        _ prepared: (data: Data, fileExtension: String, contentType: String)
    ) async throws -> String {
        try Task.checkCancellation()
        let data = prepared.data
        let filename = "stylezam-\(UUID().uuidString).\(prepared.fileExtension)"
        let body: [String: Any] = [
            "files": [[
                "content_type": prepared.contentType,
                "file_name": filename,
                "file_size": data.count
            ]]
        ]
        // All selected categories start with the same documented File API. Keeping file
        // creation separate from task routing prevents a selected hat, shoe, bag, scarf, or
        // garment from being uploaded into an unsupported category-specific namespace.
        let json = try await requestJSON(
            path: "/s2s/v2.0/file",
            method: "POST",
            body: body
        )
        guard let file = firstDictionary(named: "files", in: json),
              let fileID = file["file_id"] as? String,
              let uploadRequest = firstDictionary(named: "requests", in: file),
              let rawURL = uploadRequest["url"] as? String,
              let uploadURL = URL(string: rawURL)
        else { throw YouCamTryOnError.invalidResponse }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = (uploadRequest["method"] as? String) ?? "PUT"
        if let headers = uploadRequest["headers"] as? [String: Any] {
            headers.forEach { request.setValue(String(describing: $1), forHTTPHeaderField: $0) }
        }
        let (_, response) = try await session.upload(for: request, from: data)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YouCamTryOnError.server("YouCam rejected an image upload.")
        }
        return fileID
    }

    private func preparedUpload(
        from data: Data,
        flattenTransparency: Bool = false
    ) -> (data: Data, fileExtension: String, contentType: String)? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let maxDimension = max(image.size.width, image.size.height)
        let minDimension = min(image.size.width, image.size.height)
        let needsRendering = flattenTransparency
            || !isPNG
            || minDimension < 512
            || maxDimension > 4096
            || data.count >= 10_000_000
        if !needsRendering { return (data, "png", "image/png") }

        let scaleToMinimum = max(1, 512 / minDimension)
        let scaleToMaximum = 4096 / maxDimension
        let scale = min(scaleToMinimum, scaleToMaximum)
        let drawnSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let canvasSize = CGSize(width: max(512, drawnSize.width), height: max(512, drawnSize.height))
        let preserveTransparency = isPNG && data.count < 10_000_000 && !flattenTransparency
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !preserveTransparency
        let rendered = UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            if !preserveTransparency {
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: canvasSize))
            }
            let origin = CGPoint(x: (canvasSize.width - drawnSize.width) / 2, y: (canvasSize.height - drawnSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawnSize))
        }
        if preserveTransparency, let png = rendered.pngData(), png.count < 10_000_000 {
            return (png, "png", "image/png")
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else { return nil }
        return (jpeg, "jpg", "image/jpg")
    }

    /// The provider will faithfully generate from whatever reference it receives, even when the
    /// Fashionpedia detector mistook bedding for a bag or coat. Reject only strong conflicting
    /// on-device evidence before spending YouCam units. Ambiguous and small accessories remain
    /// allowed because the broad system classifier is not a replacement for the garment model.
    private nonisolated static func validateReferenceImage(
        _ data: Data,
        for item: TryOnTrayItem
    ) throws {
        guard [.clothes, .bag, .scarf, .shoes, .hat].contains(item.category),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 768,
                ] as CFDictionary
              )
        else { return }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return
        }
        var scores: [String: Double] = [:]
        for result in (request.results ?? []).prefix(45) {
            let identifier = result.identifier.lowercased()
            let confidence = Double(result.confidence)
            let aliases = Set(
                [identifier]
                    + identifier
                        .split(whereSeparator: { $0 == "," || $0 == ";" })
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    + identifier
                        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                        .map(String.init)
            )
            for alias in aliases where !alias.isEmpty {
                scores[alias] = max(scores[alias] ?? 0, confidence)
            }
        }
        func score(_ labels: Set<String>) -> Double {
            scores.reduce(0) { current, pair in
                labels.contains(pair.key) ? max(current, pair.value) : current
            }
        }
        let nonFashion = score([
            "bedding", "pillow", "bed", "blanket", "comforter", "duvet", "quilt",
            "furniture", "sofa", "couch", "curtain", "towel", "rug", "carpet",
        ])
        let relevant: Double
        switch item.category {
        case .bag:
            relevant = score([
                "bag", "handbag", "purse", "wallet", "backpack", "back pack",
                "rucksack", "haversack", "luggage", "suitcase", "duffel", "holdall", "kitbag",
            ])
        case .shoes:
            relevant = score(["shoe", "footwear", "sneaker", "boot", "sandal", "loafer"])
        case .hat:
            relevant = score(["hat", "headwear", "cap", "beanie"])
        case .scarf:
            relevant = score(["scarf", "clothing", "apparel", "textile"])
        case .clothes:
            relevant = score([
                "clothing", "apparel", "jeans", "pants", "trousers", "shorts", "skirt",
                "dress", "shirt", "blouse", "t-shirt", "sweater", "cardigan", "jacket",
                "coat", "vest", "suit", "jersey",
            ])
        default:
            return
        }
        guard nonFashion >= 0.16, nonFashion > max(0.07, relevant * 1.18) else { return }
        throw YouCamTryOnError.server(
            "\(item.title) looks more like bedding or furniture than a \(item.category.title.lowercased()). It was not uploaded or charged. Retake the piece against a plain background or choose a different crop."
        )
    }

    /// A completed task is not automatically a valid try-on. Perfect Corp's generative bag,
    /// scarf, shoes, and hat tasks may create a styled outfit and background, while Stylezam's
    /// contract is to apply only the selected piece. We deliberately look only for an obvious
    /// whole-scene replacement here. Earlier versions used a tiny image hash and thresholds
    /// strict enough to reject normal provider tone, relighting, and compression differences.
    nonisolated static func validateSingleItemScenePreservation(
        source: Data,
        result: Data,
        category: TryOnCategory,
        garmentRegion: TryOnGarmentRegion
    ) throws {
        guard let sourceImage = normalizedSceneImage(from: source),
              let resultImage = normalizedSceneImage(from: result)
        else {
            throw YouCamTryOnError.server(
                "Stylezam could not verify that YouCam preserved your original photo, so the result was rejected instead of being saved."
            )
        }

        let sourceRatio = Double(sourceImage.width) / Double(max(1, sourceImage.height))
        let resultRatio = Double(resultImage.width) / Double(max(1, resultImage.height))
        guard abs(sourceRatio - resultRatio) <= 0.12 else {
            throw YouCamTryOnError.server(
                "YouCam changed the photo framing instead of adding only the selected \(category.title.lowercased()). Stylezam rejected that result. Use a clear front facing photo and try again."
            )
        }
        let faceRects = detectedFaceRects(in: sourceImage)
        let allowedChanges = allowedChangeRects(
            category: category,
            garmentRegion: garmentRegion
        )
        guard let protectedDifference = alignedSceneDifference(
                  source: sourceImage,
                  result: resultImage,
                  excludedAreas: allowedChanges,
                  alwaysIncludedAreas: faceRects,
                  minimumSamples: 180
              ),
              let borderDifference = alignedSceneDifference(
                  source: sourceImage,
                  result: resultImage,
                  includedAreas: sceneBorderRects,
                  minimumSamples: 180
              )
        else {
            throw YouCamTryOnError.server(
                "Stylezam could not complete its person and scene integrity check, so the try-on result was not saved."
            )
        }
        let faceDifference = faceRects.isEmpty
            ? nil
            : alignedSceneDifference(
                source: sourceImage,
                result: resultImage,
                includedAreas: faceRects,
                minimumSamples: 18
            )
        // A genuine scene replacement changes both the protected person/background pixels and
        // the outer frame. A valid VTO result can still make modest global changes through
        // JPEG recompression, relighting, or diffusion denoising, so do not reject it for that.
        let appearsToReplaceWholeScene = protectedDifference > 0.34 && borderDifference > 0.30
        let faceWasSubstantiallyRewritten = faceDifference.map { $0 > 0.38 } ?? false
        guard !appearsToReplaceWholeScene,
              !faceWasSubstantiallyRewritten
        else {
            throw YouCamTryOnError.server(
                "YouCam returned a full scene replacement instead of a focused \(category.title.lowercased()) try-on. Stylezam kept your original photo safe and did not save that result. Try a clear front-facing photo and a tightly cropped product image."
            )
        }
    }

    /// Optional photo finishes run after the selected pieces and therefore must preserve the
    /// finished person and outfit. Detail and lighting tasks are also required to preserve the
    /// scene; background tasks may replace only the background. This guard prevents an otherwise
    /// successful provider response from becoming a second, unrequested outfit generation.
    nonisolated static func validateFinishingSubjectPreservation(
        source: Data,
        result: Data,
        operation: String,
        allowsBackgroundChange: Bool
    ) throws {
        guard let sourceImage = normalizedSceneImage(from: source),
              let resultImage = normalizedSceneImage(from: result)
        else {
            throw YouCamTryOnError.server(
                "Stylezam could not verify the \(operation) result, so it kept the previous try-on instead."
            )
        }

        let sourceRatio = Double(sourceImage.width) / Double(max(1, sourceImage.height))
        let resultRatio = Double(resultImage.width) / Double(max(1, resultImage.height))
        guard abs(sourceRatio - resultRatio) <= 0.12 else {
            throw YouCamTryOnError.server(
                "YouCam changed the photo framing during \(operation). Stylezam rejected that finish and kept the previous try-on safe."
            )
        }

        let sourceFaces = detectedFaceRects(in: sourceImage)
        let resultFaces = detectedFaceRects(in: resultImage)
        if !sourceFaces.isEmpty {
            guard !resultFaces.isEmpty,
                  sourceFaces.contains(where: { sourceFace in
                      resultFaces.contains { faceIntersectionOverUnion(sourceFace, $0) >= 0.18 }
                  })
            else {
                throw YouCamTryOnError.server(
                    "YouCam changed or removed the person during \(operation). Stylezam rejected that finish and kept the previous try-on safe."
                )
            }

            let faceDifference = alignedSceneDifference(
                source: sourceImage,
                result: resultImage,
                includedAreas: sourceFaces,
                minimumSamples: 18
            )
            guard faceDifference.map({ $0 <= 0.42 }) ?? false else {
                throw YouCamTryOnError.server(
                    "YouCam substantially changed the face during \(operation). Stylezam rejected that finish and kept the previous try-on safe."
                )
            }
        }

        if !allowsBackgroundChange {
            let fullSceneDifference = alignedSceneDifference(
                source: sourceImage,
                result: resultImage,
                alwaysIncludedAreas: sourceFaces,
                minimumSamples: 180
            )
            guard fullSceneDifference.map({ $0 <= 0.24 }) ?? false else {
                throw YouCamTryOnError.server(
                    "YouCam replaced the scene or outfit during \(operation). Stylezam rejected that finish and kept the previous try-on safe."
                )
            }
        }
    }

    private nonisolated static func faceIntersectionOverUnion(
        _ first: CGRect,
        _ second: CGRect
    ) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = first.width * first.height + second.width * second.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    private struct SceneRaster {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    /// Applies EXIF orientation while downsampling. Camera JPEGs often store their orientation
    /// as metadata; comparing their raw CGImage against YouCam's upright output causes false
    /// scene-change failures and wastes memory on multi-megapixel photos.
    private nonisolated static func normalizedSceneImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Vision observations use a lower-left origin; the scene raster uses top-left coordinates.
    /// The face itself is never a legal edit area, even for hat, scarf, or full-body tasks.
    private nonisolated static func detectedFaceRects(in image: CGImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation in
            let box = observation.boundingBox
            let converted = CGRect(
                x: box.minX,
                y: 1 - box.maxY,
                width: box.width,
                height: box.height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return converted.isNull || converted.isEmpty ? nil : converted
        }
    }

    private nonisolated static func rgbaRaster(
        for image: CGImage,
        width: Int,
        height: Int
    ) -> SceneRaster? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.interpolationQuality = .medium
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return SceneRaster(width: width, height: height, pixels: pixels)
    }

    private nonisolated static func alignedSceneDifference(
        source: CGImage,
        result: CGImage,
        includedAreas: [CGRect]? = nil,
        excludedAreas: [CGRect] = [],
        alwaysIncludedAreas: [CGRect] = [],
        minimumSamples: Int
    ) -> Double? {
        guard let sourceRaster = rgbaRaster(for: source, width: 48, height: 64),
              let resultRaster = rgbaRaster(for: result, width: 48, height: 64)
        else { return nil }

        func difference(offsetX: Int, offsetY: Int) -> Double? {
            var total = 0.0
            var samples = 0
            for y in 0..<sourceRaster.height {
                for x in 0..<sourceRaster.width {
                    let normalized = CGPoint(
                        x: (Double(x) + 0.5) / Double(sourceRaster.width),
                        y: (Double(y) + 0.5) / Double(sourceRaster.height)
                    )
                    let explicitlyIncluded = alwaysIncludedAreas.contains {
                        $0.contains(normalized)
                    }
                    let inRequestedArea = includedAreas?.contains {
                        $0.contains(normalized)
                    } ?? true
                    let excluded = excludedAreas.contains { $0.contains(normalized) }
                    guard inRequestedArea, explicitlyIncluded || !excluded else { continue }
                    let resultX = x + offsetX
                    let resultY = y + offsetY
                    guard resultX >= 0, resultX < resultRaster.width,
                          resultY >= 0, resultY < resultRaster.height
                    else { continue }
                    let sourceIndex = (y * sourceRaster.width + x) * 4
                    let resultIndex = (resultY * resultRaster.width + resultX) * 4
                    for channel in 0..<3 {
                        total += abs(
                            Double(sourceRaster.pixels[sourceIndex + channel])
                                - Double(resultRaster.pixels[resultIndex + channel])
                        ) / 255
                        samples += 1
                    }
                }
            }
            guard samples >= minimumSamples else { return nil }
            return total / Double(samples)
        }

        return (-1...1).flatMap { y in
            (-1...1).compactMap { x in difference(offsetX: x, offsetY: y) }
        }.min()
    }

    private nonisolated static func allowedChangeRects(
        category: TryOnCategory,
        garmentRegion: TryOnGarmentRegion
    ) -> [CGRect] {
        switch category {
        case .clothes:
            switch garmentRegion {
            case .upperBody:
                [CGRect(x: 0.16, y: 0.23, width: 0.68, height: 0.52)]
            case .outerwear:
                [CGRect(x: 0.10, y: 0.20, width: 0.80, height: 0.64)]
            case .lowerBody:
                [CGRect(x: 0.10, y: 0.44, width: 0.80, height: 0.55)]
            case .fullBody:
                [CGRect(x: 0.08, y: 0.16, width: 0.84, height: 0.83)]
            case .footwear:
                [CGRect(x: 0.08, y: 0.70, width: 0.84, height: 0.29)]
            case .accessory, .unknown:
                [CGRect(x: 0.10, y: 0.20, width: 0.80, height: 0.76)]
            }
        case .hat:
            [CGRect(x: 0.18, y: 0, width: 0.64, height: 0.40)]
        case .scarf, .necklace:
            [CGRect(x: 0.18, y: 0.12, width: 0.64, height: 0.48)]
        case .bag:
            [CGRect(x: 0.06, y: 0.28, width: 0.88, height: 0.70)]
        case .shoes:
            [CGRect(x: 0.06, y: 0.68, width: 0.88, height: 0.31)]
        case .ring, .bracelet, .watch:
            [CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)]
        case .earring:
            [CGRect(x: 0.12, y: 0.04, width: 0.76, height: 0.62)]
        }
    }

    /// The outer image frame is the least ambiguous evidence that a provider changed a whole
    /// scene. It intentionally avoids the centre, where a valid garment may occupy most of a
    /// portrait photo.
    private nonisolated static let sceneBorderRects: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1, height: 0.14),
        CGRect(x: 0, y: 0.86, width: 1, height: 0.14),
        CGRect(x: 0, y: 0.14, width: 0.12, height: 0.72),
        CGRect(x: 0.88, y: 0.14, width: 0.12, height: 0.72),
    ]

    nonisolated static func hasUsefulTransparency(_ data: Data) -> Bool {
        guard let image = UIImage(data: data)?.cgImage,
              let raster = rgbaRaster(for: image, width: 32, height: 32)
        else { return false }
        let alphas = stride(from: 3, to: raster.pixels.count, by: 4).map {
            raster.pixels[$0]
        }
        let clear = alphas.filter { $0 <= 32 }.count
        let translucent = alphas.filter { $0 < 248 }.count
        return clear >= 8 && translucent >= 20
    }

    private func createTask(
        endpoint: String,
        category: TryOnCategory,
        garmentRegion: TryOnGarmentRegion = .unknown,
        sourceID: String,
        referenceID: String,
        gender: TryOnGender
    ) async throws -> String {
        try await createTaskCapturingAcceptedResponse(
            .tryOn(
                endpoint: endpoint,
                category: category,
                garmentRegion: garmentRegion,
                sourceID: sourceID,
                referenceID: referenceID,
                gender: gender
            )
        )
    }

    private func createVideoTask(
        sourceID: String,
        resolution: YouCamVideoResolution
    ) async throws -> String {
        try await createTaskCapturingAcceptedResponse(
            .video(endpoint: Self.videoEndpoint, sourceID: sourceID, resolution: resolution)
        )
    }

    private func createTaskCapturingAcceptedResponse(
        _ creationRequest: YouCamTaskCreationRequest
    ) async throws -> String {
        let relay = YouCamTaskCreationRelay()

        Task.detached(priority: .userInitiated) { [self] in
            guard await relay.beginRequest() else { return }
            do {
                let taskID = try await submitTask(creationRequest)
                if await relay.succeed(taskID) {
                    await scheduleRemoteCleanup(
                        endpoint: creationRequest.endpoint,
                        taskID: taskID
                    )
                }
            } catch {
                await relay.fail(error)
            }
        }

        let taskID = try await withTaskCancellationHandler {
            try await relay.value()
        } onCancel: { [self] in
            Task.detached(priority: .utility) {
                if let acceptedTaskID = await relay.cancel() {
                    await self.scheduleRemoteCleanup(
                        endpoint: creationRequest.endpoint,
                        taskID: acceptedTaskID
                    )
                }
            }
        }
        try Task.checkCancellation()
        return taskID
    }

    private func submitTask(_ creationRequest: YouCamTaskCreationRequest) async throws -> String {
        let endpoint = creationRequest.endpoint
        let body: [String: Any]

        switch creationRequest {
        case let .tryOn(_, category, garmentRegion, sourceID, referenceID, gender):
            body = Self.tryOnTaskBody(
                category: category,
                garmentRegion: garmentRegion,
                sourceID: sourceID,
                referenceID: referenceID,
                gender: gender
            )
        case let .video(_, sourceID, resolution):
            body = [
                "src_file_id": sourceID,
                "resolution": resolution.rawValue,
                "dst_duration": 5,
                "prompt": Self.videoPrompt,
                "negative_prompt": Self.videoNegativePrompt,
                "model": "youcam-video-v2"
            ]
        }

        let json = try await requestJSON(
            path: "/s2s/v2.0/task/\(endpoint)",
            method: "POST",
            body: body
        )
        guard let taskID = recursiveValue(for: "task_id", in: json) as? String else {
            throw serverError(from: json)
        }
        return taskID
    }

    /// A single source of truth for the documented payload of every entitled YouCam task.
    /// Keeping this pure also lets integration tests prove that a hat can never be sent to
    /// Clothes V4, and that corrected outerwear uses the V4 `outer` value rather than `upper_body`.
    nonisolated static func tryOnTaskBody(
        category: TryOnCategory,
        garmentRegion: TryOnGarmentRegion,
        sourceID: String,
        referenceID: String,
        gender: TryOnGender
    ) -> [String: Any] {
        var body: [String: Any] = ["src_file_id": sourceID]
        if category.isJewelry {
            body["ref_file_ids"] = [referenceID]
            body["source_info"] = ["name": sourceID]
            var objectInfo: [String: Any] = ["name": referenceID]
            if let parameters = category.youCamObjectParameters {
                objectInfo["parameter"] = parameters
            }
            body["object_infos"] = [objectInfo]
            return body
        }

        body["ref_file_id"] = referenceID
        if category == .clothes {
            body["garment_category"] = garmentRegion.youCamGarmentCategory
            // Clothes V4 defaults to changing shoes for full/lower-body references. A clothing
            // rail item must never add another product category unless the user selected shoes.
            body["change_shoes"] = false
        } else {
            body["gender"] = gender.rawValue
            if [.bag, .scarf, .shoes, .hat].contains(category) {
                // These category APIs require a style selection. `random` is their documented
                // neutral/default choice; post-result scene validation still prevents a full
                // background or person replacement from being saved as a single-item try-on.
                body["style"] = "random"
            }
        }
        return body
    }

    private func deleteFinishedTask(_ taskID: String) async throws {
        _ = try await requestJSON(
            path: "/s2s/v2.0/task/delete",
            method: "POST",
            body: ["task_id": taskID]
        )
    }

    private func deleteFinishedTaskIgnoringCancellation(_ taskID: String) async {
        let cleanup = Task.detached(priority: .utility) { [self] in
            _ = await deleteFinishedTaskWithRetries(taskID)
        }
        await cleanup.value
    }

    /// Cancellation is local and immediate. The detached monitor keeps the provider task alive
    /// only long enough to reach a deletable terminal state, then removes its inputs and outputs.
    /// If polling or deletion remains unavailable after the bounds below, YouCam's documented
    /// automatic retention period remains the fallback.
    private func scheduleRemoteCleanup(endpoint: String, taskID: String) {
        guard scheduledCleanupTaskIDs.insert(taskID).inserted else { return }
        Task.detached(priority: .utility) { [self] in
            await waitForTerminalStateAndDelete(endpoint: endpoint, taskID: taskID)
            await finishScheduledCleanup(taskID)
        }
    }

    private func finishScheduledCleanup(_ taskID: String) {
        scheduledCleanupTaskIDs.remove(taskID)
    }

    private func waitForTerminalStateAndDelete(endpoint: String, taskID: String) async {
        if await deleteFinishedTaskWithRetries(taskID, attempts: 1) { return }

        var consecutiveFailures = 0
        for _ in 0..<Self.remoteCleanupPollLimit {
            do {
                let json = try await requestJSON(
                    path: "/s2s/v2.0/task/\(endpoint)/\(taskID)",
                    method: "GET"
                )
                consecutiveFailures = 0
                if taskIsTerminal(json) {
                    _ = await deleteFinishedTaskWithRetries(taskID)
                    return
                }
                try? await Task.sleep(for: pollingDelay(from: json))
            } catch {
                consecutiveFailures += 1
                guard consecutiveFailures < Self.remoteCleanupFailureLimit else { return }
                try? await Task.sleep(for: .seconds(3))
            }
        }

        // The task may have crossed into a terminal state just after the final status poll.
        _ = await deleteFinishedTaskWithRetries(taskID)
    }

    private func taskIsTerminal(_ json: Any) -> Bool {
        let status = (recursiveValue(for: "task_status", in: json) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if status == "success" || Self.failureStatuses.contains(status ?? "") { return true }
        return status == nil && recursiveValue(for: "url", in: json) != nil
    }

    private func deleteFinishedTaskWithRetries(
        _ taskID: String,
        attempts: Int = 3
    ) async -> Bool {
        for attempt in 0..<max(1, attempts) {
            do {
                try await deleteFinishedTask(taskID)
                return true
            } catch {
                if attempt + 1 < max(1, attempts) {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        return false
    }

    private func poll(endpoint: String, taskID: String) async throws -> URL {
        for _ in 0..<60 {
            try Task.checkCancellation()
            let json = try await requestJSON(path: "/s2s/v2.0/task/\(endpoint)/\(taskID)", method: "GET")
            let status = (recursiveValue(for: "task_status", in: json) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let rawURL = recursiveValue(for: "url", in: json) as? String
            if status == "success" || (status == nil && rawURL != nil) {
                guard let rawURL,
                      let url = URL(string: rawURL), url.scheme == "https"
                else { throw YouCamTryOnError.invalidResponse }
                return url
            }
            if Self.failureStatuses.contains(status ?? "") { throw serverError(from: json) }
            try await Task.sleep(for: .seconds(3))
        }
        throw YouCamTryOnError.timedOut
    }

    private func pollVideo(taskID: String) async throws -> URL {
        for _ in 0..<100 {
            try Task.checkCancellation()
            let json = try await requestJSON(
                path: "/s2s/v2.0/task/\(Self.videoEndpoint)/\(taskID)",
                method: "GET"
            )
            let status = (recursiveValue(for: "task_status", in: json) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let rawURL = recursiveValue(for: "url", in: json) as? String

            if Self.failureStatuses.contains(status ?? "") {
                throw serverError(from: json)
            }
            if status == "success" || (status == nil && rawURL != nil) {
                guard let rawURL, let url = URL(string: rawURL), url.scheme == "https" else {
                    throw YouCamTryOnError.invalidResponse
                }
                return url
            }

            try await Task.sleep(for: pollingDelay(from: json))
        }
        throw YouCamTryOnError.videoTimedOut
    }

    private func pollingDelay(from json: Any) -> Duration {
        let value = recursiveValue(for: "polling_interval", in: json)
        let seconds: Double
        if let number = value as? NSNumber {
            seconds = number.doubleValue
        } else if let string = value as? String, let number = Double(string) {
            seconds = number
        } else {
            seconds = 3
        }
        return .milliseconds(Int(min(5, max(1, seconds)) * 1_000))
    }

    private func downloadVideo(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.setValue("video/mp4,video/*;q=0.9,application/octet-stream;q=0.5", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YouCamTryOnError.server("The generated motion preview could not be downloaded.")
        }
        guard !data.isEmpty, data.count < 100_000_000, isMP4(data) else {
            throw YouCamTryOnError.server("YouCam returned an unsupported motion-preview file.")
        }
        return data
    }

    private func isMP4(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return Data(data.dropFirst(4).prefix(4)) == Data("ftyp".utf8)
    }

    private func requestJSON(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> Any {
        try Task.checkCancellation()
        guard let key = Self.apiKey, !key.isEmpty, !key.contains("$(") else {
            throw YouCamTryOnError.missingAPIKey
        }
        let endpointURL = baseURL.appending(path: path)
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw YouCamTryOnError.invalidResponse
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw YouCamTryOnError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let maximumAttempts = method == "GET" ? 3 : 1
        for attempt in 0..<maximumAttempts {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            let json: Any
            if data.isEmpty {
                json = [String: Any]()
            } else if let decoded = try? JSONSerialization.jsonObject(with: data) {
                json = decoded
            } else {
                json = ["message": String(data: data, encoding: .utf8) ?? "YouCam returned an unreadable response."]
            }
            guard let http = response as? HTTPURLResponse else {
                throw YouCamTryOnError.invalidResponse
            }
            if (200..<300).contains(http.statusCode) { return json }

            let isTransient = http.statusCode == 429 || (500...599).contains(http.statusCode)
            if isTransient, attempt + 1 < maximumAttempts {
                try await Task.sleep(for: retryDelay(response: http, attempt: attempt))
                continue
            }
            throw serverError(from: json, statusCode: http.statusCode)
        }
        throw YouCamTryOnError.invalidResponse
    }

    private func retryDelay(response: HTTPURLResponse, attempt: Int) -> Duration {
        if let raw = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(raw)
        {
            return .milliseconds(Int(min(8, max(1, seconds)) * 1_000))
        }
        return .seconds(min(6, 2 << attempt))
    }

    private static let failureStatuses: Set<String> = [
        "error", "failed", "failure", "cancelled", "canceled",
    ]

    private static var apiKey: String? {
        if let value = YouCamCredentialStore.apiKey, !value.isEmpty { return value }
        if let value = ProcessInfo.processInfo.environment["STYLEZAM_YOUCAM_API_KEY"], !value.isEmpty { return value }
        if let value = ProcessInfo.processInfo.environment["YOUCAM_API_KEY"], !value.isEmpty { return value }
        return nil
    }

    private func serverError(from json: Any, statusCode: Int? = nil) -> YouCamTryOnError {
        let code = (recursiveValue(for: "error_code", in: json) as? String)
            ?? (recursiveValue(for: "code", in: json) as? String)
        let providerMessage = (recursiveValue(for: "message", in: json) as? String)
            ?? (recursiveValue(for: "error", in: json) as? String)
        let diagnostic = [code, providerMessage]
            .compactMap {
                $0?.lowercased()
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
            }
            .joined(separator: " ")

        let friendly: String
        if statusCode == 429
            || diagnostic.contains("rate limit")
            || diagnostic.contains("too many request")
            || diagnostic.contains("toomanyrequest")
            || diagnostic.contains("qps")
            || diagnostic.contains("concurr")
            || diagnostic.contains("quota exceeded")
        {
            friendly = "YouCam is handling too many requests for this account. Wait a moment, then try again."
        } else if statusCode == 402
            || diagnostic.contains("insufficient credit")
            || diagnostic.contains("insufficient unit")
            || diagnostic.contains("not enough credit")
            || diagnostic.contains("not enough unit")
        {
            friendly = "This YouCam account does not have enough API units for the requested feature. Check the account allowance before trying again."
        } else if statusCode == 403
            || diagnostic.contains("not entitled")
            || diagnostic.contains("not enabled")
            || diagnostic.contains("feature unavailable")
            || diagnostic.contains("permission denied")
            || diagnostic.contains("forbidden")
        {
            friendly = "This build's YouCam account is not entitled to the requested feature. The developer must enable that task for the account."
        } else if statusCode == 401 {
            friendly = "YouCam rejected this build's credential. The developer must update the configured credential."
        } else {
            switch code?.lowercased() {
            case "error_invalid_src", "error_no_face", "photo_detection_fail", "photo_check_invalid":
                friendly = "YouCam could not detect one clear person in your photo. Retake it facing forward with the requested body area visible."
            case "object_detection_fail", "input_object_image_empty":
                friendly = "YouCam could not recognize the found product image. Try another result or add a clearer product photo."
            case "exceed_max_filesize":
                friendly = "One of the try-on images is too large for YouCam."
            case "invalid_parameter":
                friendly = "YouCam rejected this category or image combination. Confirm the piece category and try again."
            case "error_nsfw_content_detected":
                friendly = "YouCam declined this image under its content policy."
            default:
                if let providerMessage, !providerMessage.isEmpty {
                    friendly = providerMessage
                } else if let statusCode {
                    friendly = "YouCam returned HTTP \(statusCode). Check the API allowance and try again."
                } else {
                    friendly = "YouCam could not generate this try-on. Check the person photo and product image."
                }
            }
        }

        guard let code, !friendly.localizedCaseInsensitiveContains(code) else {
            return .server(friendly)
        }
        return .server("\(friendly) (\(code))")
    }

    private func recursiveValue(for key: String, in value: Any) -> Any? {
        if let dictionary = value as? [String: Any] {
            if let found = dictionary[key] { return found }
            for child in dictionary.values {
                if let found = recursiveValue(for: key, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = recursiveValue(for: key, in: child) { return found }
            }
        }
        return nil
    }

    private func firstDictionary(named key: String, in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let array = dictionary[key] as? [[String: Any]] { return array.first }
            for child in dictionary.values {
                if let found = firstDictionary(named: key, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstDictionary(named: key, in: child) { return found }
            }
        }
        return nil
    }
}

private extension TryOnGarmentRegion {
    var youCamGarmentCategory: String {
        switch self {
        case .upperBody:
            "upper_body"
        case .outerwear:
            "outer"
        case .lowerBody:
            "lower_body"
        case .fullBody:
            "full_body"
        case .footwear, .accessory, .unknown:
            "auto"
        }
    }
}

private extension TryOnCategory {
    var isJewelry: Bool {
        switch self {
        case .ring, .bracelet, .earring, .watch, .necklace: true
        default: false
        }
    }

    var youCamObjectParameters: [String: Any]? {
        switch self {
        case .ring:
            [
                "ring_need_remove_background": true,
                "ring_wearing_finger": NSNull(),
                "ring_wearing_location": NSNull(),
                "ring_shadow_intensity": 0.15,
                "ring_ambient_light_intensity": 1.0
            ]
        case .bracelet:
            [
                "bracelet_need_remove_background": true,
                "bracelet_wearing_location": NSNull(),
                "bracelet_shadow_intensity": 0.3,
                "bracelet_ambient_light_intensity": 1.0
            ]
        case .earring:
            [
                "earring_need_remove_background": true,
                "earring_is_right_ear": true,
                "earring_occluded_type": 0,
                "earring_shadow_intensity": 0.5,
                "earring_ambient_light_intensity": 0.5
            ]
        case .watch:
            [
                "watch_need_remove_background": true,
                "watch_wearing_location": NSNull(),
                "watch_shadow_intensity": 0.3,
                "watch_ambient_light_intensity": 1.0
            ]
        case .necklace:
            [
                "necklace_need_remove_background": true,
                "necklace_shadow_intensity": 0.5,
                "necklace_ambient_light_intensity": 0.5
            ]
        default: nil
        }
    }
}
