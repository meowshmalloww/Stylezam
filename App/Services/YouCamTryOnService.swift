import Foundation
import Security
import UIKit

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
        }
    }
}

actor YouCamTryOnService {
    private let baseURL = URL(string: "https://yce-api-01.makeupar.com")!
    private let session: URLSession

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
        progress: @Sendable (Int, Int, String) async -> Void
    ) async throws -> (jobID: String, imageData: Data) {
        guard !items.isEmpty else { throw YouCamTryOnError.server("Select at least one item.") }
        var current = personImage
        var lastTaskID = UUID().uuidString

        for (index, item) in items.enumerated() {
            await progress(index, items.count, "Preparing \(item.title)")
            let endpoint = item.category.endpoint
            await progress(index, items.count, "Uploading your photo")
            let sourceID = try await upload(current, endpoint: endpoint)
            await progress(index, items.count, "Uploading the found piece")
            let referenceID = try await upload(item.imageData, endpoint: endpoint)
            await progress(index, items.count, "Starting YouCam")
            lastTaskID = try await createTask(
                endpoint: endpoint,
                category: item.category,
                sourceID: sourceID,
                referenceID: referenceID,
                gender: gender
            )
            do {
                await progress(index, items.count, "Creating your try-on")
                let resultURL = try await poll(endpoint: endpoint, taskID: lastTaskID)
                await progress(index, items.count, "Downloading the result")
                let (data, response) = try await session.data(from: resultURL)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw YouCamTryOnError.server("The generated image could not be downloaded.")
                }
                guard let normalized = await ImageEncoding.normalizedJPEGAsync(from: data) else {
                    throw YouCamTryOnError.server("YouCam returned an unsupported result image.")
                }
                current = normalized
            } catch {
                try? await deleteFinishedTask(lastTaskID)
                throw error
            }
            try? await deleteFinishedTask(lastTaskID)
        }
        await progress(items.count, items.count, "Look ready")
        return (lastTaskID, current)
    }

    private func upload(_ sourceData: Data, endpoint: String) async throws -> String {
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
        let filename = "stylezam-\(UUID().uuidString).\(prepared.fileExtension)"
        let body: [String: Any] = [
            "files": [[
                "content_type": prepared.contentType,
                "file_name": filename,
                "file_size": data.count
            ]]
        ]
        let json = try await requestJSON(path: "/s2s/v2.0/file/\(endpoint)", method: "POST", body: body)
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

    private func createTask(
        endpoint: String,
        category: TryOnCategory,
        sourceID: String,
        referenceID: String,
        gender: TryOnGender
    ) async throws -> String {
        var body: [String: Any] = ["src_file_id": sourceID]
        if category.isJewelry {
            body["ref_file_ids"] = [referenceID]
        } else {
            body["ref_file_id"] = referenceID
            if category == .clothes {
                body["garment_category"] = "auto"
            } else {
                body["gender"] = gender.rawValue
                if category == .shoes {
                    body["style"] = "random"
                }
            }
        }
        let json = try await requestJSON(path: "/s2s/v2.0/task/\(endpoint)", method: "POST", body: body)
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

    private func requestJSON(path: String, method: String, body: [String: Any]? = nil) async throws -> Any {
        guard let key = Self.apiKey, !key.isEmpty, !key.contains("$(") else {
            throw YouCamTryOnError.missingAPIKey
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: request)
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

        let friendly: String
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

private extension TryOnCategory {
    var endpoint: String {
        switch self {
        case .clothes: "cloth-v3"
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
}
