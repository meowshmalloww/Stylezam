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
        guard apiKey == nil else { return }
        let environment = ProcessInfo.processInfo.environment
        let value = environment["STYLEZAM_YOUCAM_API_KEY"] ?? environment["YOUCAM_API_KEY"]
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
            "Enter a YouCam API key in the Try On connection panel, or configure STYLEZAM_YOUCAM_API_KEY for this Debug build."
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

    static let none = YouCamFinishingOptions()
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

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validateConnection() async throws {
        _ = try await requestJSON(
            path: "/s2s/v2.0/credit/feature-cost",
            method: "GET"
        )
    }

    func render(
        personImage: Data,
        items: [TryOnTrayItem],
        gender: TryOnGender,
        finishing: YouCamFinishingOptions = .none,
        progress: @Sendable (Int, Int, String) async -> Void
    ) async throws -> (jobID: String, imageData: Data) {
        guard !items.isEmpty else { throw YouCamTryOnError.server("Select at least one item.") }
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
        guard !(finishing.removesBackground && finishing.changesBackground) else {
            throw YouCamTryOnError.server(
                "Choose either background removal or background change, not both."
            )
        }
        var current = personImage
        var lastTaskID = UUID().uuidString
        let totalTasks = items.count + finishing.enabledTaskCount

        for (index, item) in items.enumerated() {
            await progress(index, totalTasks, "Preparing \(item.title)")
            let endpoint = item.category.endpoint
            await progress(index, totalTasks, "Uploading your photo")
            let sourceID = try await upload(current)
            await progress(index, totalTasks, "Uploading the found piece")
            let referenceID = try await upload(referenceImages[index])
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
                    category: item.category
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
        if preserveTransparency, data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return data
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

    private func upload(_ sourceData: Data) async throws -> String {
        guard let prepared = preparedUpload(from: sourceData) else {
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
        // Perfect Corp's simplified V2 workflow documents one shared file
        // uploader for clothes, accessories, photo finishing, and video. The
        // returned file ID is then consumed by the feature-specific task path.
        let json = try await requestJSON(path: "/s2s/v2.0/file", method: "POST", body: body)
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

    private func preparedUpload(from data: Data) -> (data: Data, fileExtension: String, contentType: String)? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let maxDimension = max(image.size.width, image.size.height)
        let minDimension = min(image.size.width, image.size.height)
        let needsRendering = !isPNG || minDimension < 512 || maxDimension > 4096 || data.count >= 10_000_000
        if !needsRendering { return (data, "png", "image/png") }

        let scaleToMinimum = max(1, 512 / minDimension)
        let scaleToMaximum = 4096 / maxDimension
        let scale = min(scaleToMinimum, scaleToMaximum)
        let drawnSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let canvasSize = CGSize(width: max(512, drawnSize.width), height: max(512, drawnSize.height))
        let preserveTransparency = isPNG && data.count < 10_000_000
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
        guard nonFashion >= 0.22, nonFashion > max(0.08, relevant * 1.35) else { return }
        throw YouCamTryOnError.server(
            "\(item.title) looks more like bedding or furniture than a \(item.category.title.lowercased()). It was not uploaded or charged. Retake the piece against a plain background or choose a different crop."
        )
    }

    /// Accessory endpoints should add one localized item, not restyle the person or recreate the
    /// whole setting. A coarse perceptual signature is deliberately insensitive to small local
    /// changes but rejects the kind of full-scene replacement that can otherwise look like a
    /// valid single-item result. Clothes are excluded because replacing a full outfit is expected.
    private nonisolated static func validateSingleItemScenePreservation(
        source: Data,
        result: Data,
        category: TryOnCategory
    ) throws {
        guard category != .clothes,
              let sourceImage = UIImage(data: source)?.cgImage,
              let resultImage = UIImage(data: result)?.cgImage
        else { return }

        let sourceRatio = Double(sourceImage.width) / Double(max(1, sourceImage.height))
        let resultRatio = Double(resultImage.width) / Double(max(1, resultImage.height))
        guard abs(sourceRatio - resultRatio) <= 0.08 else {
            throw YouCamTryOnError.server(
                "YouCam changed the photo framing instead of adding only the selected \(category.title.lowercased()). Stylezam rejected that result. Use a clear front facing photo and try again."
            )
        }
        guard let sourceSignature = sceneSignature(for: sourceImage),
              let resultSignature = sceneSignature(for: resultImage)
        else { return }
        let changedBits = (sourceSignature ^ resultSignature).nonzeroBitCount
        guard changedBits <= 26 else {
            throw YouCamTryOnError.server(
                "YouCam changed too much of the person or scene for a single \(category.title.lowercased()) try on. Stylezam rejected that result instead of saving the wrong outfit. Try a clearer full person photo or another reference image."
            )
        }
    }

    private nonisolated static func sceneSignature(for image: CGImage) -> UInt64? {
        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let average = pixels.reduce(0, { $0 + Int($1) }) / pixels.count
        var signature: UInt64 = 0
        for (index, pixel) in pixels.enumerated() where Int(pixel) >= average {
            signature |= UInt64(1) << UInt64(index)
        }
        return signature
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
            var tryOnBody: [String: Any] = ["src_file_id": sourceID]
            if category.isJewelry {
                tryOnBody["ref_file_ids"] = [referenceID]
                tryOnBody["source_info"] = ["name": sourceID]
                var objectInfo: [String: Any] = ["name": referenceID]
                if let parameters = category.youCamObjectParameters {
                    objectInfo["parameter"] = parameters
                }
                tryOnBody["object_infos"] = [objectInfo]
            } else {
                tryOnBody["ref_file_id"] = referenceID
                if category == .clothes {
                    tryOnBody["garment_category"] = garmentRegion.youCamGarmentCategory
                    // Cloth V4 otherwise defaults to replacing visible shoes for
                    // full/lower-body references. A clothing rail item must not
                    // silently add another product category.
                    tryOnBody["change_shoes"] = false
                } else {
                    tryOnBody["gender"] = gender.rawValue
                    if category == .shoes {
                        tryOnBody["style"] = "random"
                    }
                }
            }
            body = tryOnBody
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
        let status = (recursiveValue(for: "task_status", in: json) as? String)?.lowercased()
        if status == "success" || status == "error" { return true }
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
            let status = recursiveValue(for: "task_status", in: json) as? String
            if status == "success" {
                guard let rawURL = recursiveValue(for: "url", in: json) as? String,
                      let url = URL(string: rawURL)
                else { throw YouCamTryOnError.invalidResponse }
                return url
            }
            if status == "error" { throw serverError(from: json) }
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
            let status = (recursiveValue(for: "task_status", in: json) as? String)?.lowercased()
            let rawURL = recursiveValue(for: "url", in: json) as? String

            if status == "error" {
                throw serverError(from: json)
            }
            if status == "success" || (status == nil && rawURL != nil) {
                guard let rawURL, let url = URL(string: rawURL) else {
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

    private func requestJSON(path: String, method: String, body: [String: Any]? = nil) async throws -> Any {
        try Task.checkCancellation()
        guard let key = Self.apiKey, !key.isEmpty, !key.contains("$(") else {
            throw YouCamTryOnError.missingAPIKey
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
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
        guard (200..<300).contains(http.statusCode) else {
            throw serverError(from: json, statusCode: http.statusCode)
        }
        return json
    }

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
            friendly = "This YouCam API key is not enabled for the requested feature. Enable it for the account or use a key with the required access."
        } else if statusCode == 401 {
            friendly = "YouCam rejected this API key. Reconnect YouCam with a valid key and try again."
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
        case .upperBody, .outerwear:
            "upper_body"
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
    var endpoint: String {
        switch self {
        case .clothes: "cloth-v4"
        case .bag: "bag"
        case .scarf: "scarf"
        case .shoes: "shoes"
        case .hat: "hat"
        case .ring: "2d-vto/ring"
        case .bracelet: "2d-vto/bracelet"
        case .earring: "2d-vto/earring"
        case .watch: "2d-vto/watch"
        case .necklace: "2d-vto/necklace"
        }
    }

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
