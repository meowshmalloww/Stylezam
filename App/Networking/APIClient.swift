import Foundation

struct ServerErrorEnvelope: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let code: String
        let message: String
        let retryable: Bool
        let details: [String: JSONValue]
    }

    let error: Detail
}

enum APIClientError: LocalizedError, Sendable {
    case invalidBaseURL
    case insecureBaseURL
    case invalidResponse
    case untrustedDownloadURL
    case server(code: String, message: String, retryable: Bool)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter the deployed Stylezam HTTPS address in Developer Debug."
        case .insecureBaseURL:
            "Stylezam requires a deployed HTTPS service. Localhost and private HTTP addresses are not supported on iPhone."
        case .invalidResponse:
            "The Stylezam service returned an invalid response."
        case .untrustedDownloadURL:
            "The service returned a model download outside its trusted HTTPS address."
        case let .server(_, message, _):
            message
        case let .transport(message):
            "Could not reach the Stylezam service. \(message)"
        case let .decoding(message):
            "The Stylezam service response could not be read. \(message)"
        }
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    let bearerToken: String?

    init(baseURLString: String, bearerToken: String? = nil) throws {
        guard let url = URL(string: baseURLString),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased()
        else {
            throw APIClientError.invalidBaseURL
        }
        let loopbackHosts = Set(["localhost", "127.0.0.1", "::1"])
        guard scheme == "https", !loopbackHosts.contains(host) else {
            throw APIClientError.insecureBaseURL
        }
        baseURL = url
        self.bearerToken = bearerToken
    }

    func health() async throws -> HealthDTO {
        try await send(path: "v1/health")
    }

    func capabilities() async throws -> CapabilitiesDTO {
        try await send(path: "v1/capabilities")
    }

    func garmentModelPack() async throws -> ModelPackManifestDTO {
        try await send(path: "v1/model-packs/garment-segmentation")
    }

    func modelPackDownloadRequest(for url: URL) throws -> URLRequest {
        guard url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              url.host?.lowercased() == baseURL.host?.lowercased(),
              url.port == baseURL.port,
              url.path.hasPrefix("/v1/model-pack-files/")
        else {
            throw APIClientError.untrustedDownloadURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        authorize(&request)
        return request
    }

    func analyzeGarments(_ candidates: [GarmentCandidate]) async throws -> GarmentAnalysisDTO {
        let uploads = candidates.compactMap { candidate -> GarmentCandidate? in
            candidate.cropData == nil ? nil : candidate
        }
        guard !uploads.isEmpty else {
            throw APIClientError.invalidResponse
        }
        let metadata = uploads.map {
            GarmentInputMetadataDTO(
                itemID: $0.id,
                localLabel: $0.localLabel,
                localConfidence: $0.confidence,
                box: $0.box
            )
        }
        let metadataData = try JSONEncoder().encode(metadata)
        var multipart = MultipartFormData()
        multipart.addField(
            name: "metadata",
            value: String(decoding: metadataData, as: UTF8.self)
        )
        for (index, candidate) in uploads.enumerated() {
            guard let data = candidate.cropData else { continue }
            multipart.addFile(
                name: "images",
                filename: "garment-\(index + 1).png",
                contentType: "image/png",
                data: data
            )
        }
        return try await send(
            path: "v1/garment-analyses",
            method: "POST",
            body: multipart.finalizedBody(),
            contentType: multipart.contentType
        )
    }

    func createSearch(
        query: String?,
        imageData: Data?,
        selectedRegion: BoundingBoxDTO? = nil
    ) async throws -> SearchJobDTO {
        var multipart = MultipartFormData()
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            multipart.addField(name: "query", value: query)
        }
        if let selectedRegion {
            let data = try JSONEncoder().encode(selectedRegion)
            multipart.addField(
                name: "selected_region",
                value: String(decoding: data, as: UTF8.self)
            )
        }
        if let imageData {
            multipart.addFile(
                name: "image",
                filename: "capture.jpg",
                contentType: "image/jpeg",
                data: imageData
            )
        }
        return try await send(
            path: "v1/searches",
            method: "POST",
            body: multipart.finalizedBody(),
            contentType: multipart.contentType
        )
    }

    func search(id: String) async throws -> SearchJobDTO {
        try await send(path: "v1/searches/\(id)")
    }

    func results(searchID: String) async throws -> SearchResultsPageDTO {
        try await send(path: "v1/searches/\(searchID)/results")
    }

    func deleteSearch(id: String) async throws {
        try await sendWithoutResponse(path: "v1/searches/\(id)", method: "DELETE")
    }

    func createTryOn(
        productImageURL: URL,
        garmentCategory: String,
        personImageData: Data
    ) async throws -> TryOnJobDTO {
        var multipart = MultipartFormData()
        multipart.addField(name: "product_image_url", value: productImageURL.absoluteString)
        multipart.addField(name: "garment_category", value: garmentCategory)
        multipart.addFile(
            name: "person_image",
            filename: "person.jpg",
            contentType: "image/jpeg",
            data: personImageData
        )
        return try await send(
            path: "v1/try-ons",
            method: "POST",
            body: multipart.finalizedBody(),
            contentType: multipart.contentType
        )
    }

    func tryOn(id: String) async throws -> TryOnJobDTO {
        try await send(path: "v1/try-ons/\(id)")
    }

    func deleteTryOn(id: String) async throws {
        try await sendWithoutResponse(path: "v1/try-ons/\(id)", method: "DELETE")
    }

    private func sendWithoutResponse(path: String, method: String) async throws {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        authorize(&request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? Self.decoder.decode(ServerErrorEnvelope.self, from: data) {
                throw APIClientError.server(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    retryable: envelope.error.retryable
                )
            }
            throw APIClientError.server(
                code: "http_\(http.statusCode)",
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                retryable: http.statusCode >= 500
            )
        }
    }

    private func send<Response: Decodable & Sendable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = method == "POST" ? 90 : 30
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? Self.decoder.decode(ServerErrorEnvelope.self, from: data) {
                throw APIClientError.server(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    retryable: envelope.error.retryable
                )
            }
            throw APIClientError.server(
                code: "http_\(http.statusCode)",
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                retryable: http.statusCode >= 500
            )
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIClientError.decoding(error.localizedDescription)
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? Self.fractionalDateStyle.parse(value) {
                return date
            }
            if let date = try? Self.standardDateStyle.parse(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }

    private static let fractionalDateStyle = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true
    )
    private static let standardDateStyle = Date.ISO8601FormatStyle()

    private func authorize(_ request: inout URLRequest) {
        request.setValue("true", forHTTPHeaderField: "X-Daytona-Skip-Preview-Warning")
        guard let bearerToken, !bearerToken.isEmpty else { return }
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
}

private struct MultipartFormData {
    private let boundary = "Stylezam-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func finalizedBody() -> Data {
        append("--\(boundary)--\r\n")
        return body
    }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func addFile(
        name: String,
        filename: String,
        contentType: String,
        data: Data
    ) {
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    private mutating func append(_ value: String) {
        body.append(contentsOf: value.utf8)
    }
}
