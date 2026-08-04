import CryptoKit
import Foundation

actor ProductSearchService {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 9
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func understandGarment(
        imageData: Data,
        localLabel: String,
        refinement: String? = nil,
        apiKey: String,
        modelID: String
    ) async throws -> (GarmentUnderstanding, SearchProviderResponse) {
        let refinementInstruction = refinement.map {
            "The user wants this refinement: \($0). Incorporate it into the search query without inventing facts."
        } ?? ""
        let prompt = """
        Analyze only the main fashion item in this crop. The on-device detector called it \(localLabel).
        Return strict JSON with these keys:
        summary (one short factual sentence), search_query (8-16 useful shopping search words),
        suggestions (exactly 3 shorter alternative shopping queries), category (string or null),
        colors (array), materials (array), patterns (array).
        Do not invent a brand. Include visible brand/model text only when clearly readable.
        \(refinementInstruction)
        """
        let imageURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let body: [String: Any] = [
            "model": modelID,
            "reasoning_effort": "none",
            "temperature": 0.1,
            "max_tokens": 520,
            "response_format": ["type": "json_object"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": imageURL]],
                ],
            ]],
        ]
        let (data, response) = try await sendJSON(
            url: URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!,
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"],
            provider: "Fireworks"
        )
        let root = try jsonObject(data, provider: "Fireworks")
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = jsonData(fromPossiblyFenced: content),
              let decoded = try? JSONDecoder().decode(GarmentUnderstanding.self, from: contentData),
              !decoded.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ProductSearchError.invalidResponse("Fireworks")
        }
        let usage = root["usage"] as? [String: Any]
        let inputTokens = integer(usage?["prompt_tokens"])
        let outputTokens = integer(usage?["completion_tokens"])
        let requestID = response.value(forHTTPHeaderField: "x-request-id") ?? root["id"] as? String
        return (
            decoded,
            SearchProviderResponse(
                results: [],
                providerRequestID: requestID,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                diagnostic: "Fireworks returned structured garment keywords"
            )
        )
    }

    func assistantReply(
        imageData: Data,
        localLabel: String,
        question: String,
        apiKey: String,
        modelID: String
    ) async throws -> (String, SearchProviderResponse) {
        let imageURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let body: [String: Any] = [
            "model": modelID,
            "reasoning_effort": "none",
            "temperature": 0.25,
            "max_tokens": 520,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": "You are Stylezam's concise fashion search assistant. The local detector label is \(localLabel). Answer the user's question about this pictured item. Never claim an exact brand unless it is visibly readable. User: \(question)",
                    ],
                    ["type": "image_url", "image_url": ["url": imageURL]],
                ],
            ]],
        ]
        let (data, response) = try await sendJSON(
            url: URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!,
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"],
            provider: "Fireworks"
        )
        let root = try jsonObject(data, provider: "Fireworks")
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ProductSearchError.invalidResponse("Fireworks")
        }
        let usage = root["usage"] as? [String: Any]
        return (
            content.trimmingCharacters(in: .whitespacesAndNewlines),
            SearchProviderResponse(
                results: [],
                providerRequestID: response.value(forHTTPHeaderField: "x-request-id") ?? root["id"] as? String,
                inputTokens: integer(usage?["prompt_tokens"]),
                outputTokens: integer(usage?["completion_tokens"]),
                diagnostic: "Fireworks returned one assistant response"
            )
        )
    }

    func serperProducts(
        query: String,
        apiKey: String,
        country: String,
        language: String,
        limit: Int,
        searchID: String
    ) async throws -> SearchProviderResponse {
        let body: [String: Any] = [
            "q": query,
            "gl": country,
            "hl": language,
            "num": min(20, max(1, limit)),
        ]
        let (data, response) = try await sendJSON(
            url: URL(string: "https://google.serper.dev/shopping")!,
            body: body,
            headers: ["X-API-KEY": apiKey],
            provider: "Serper"
        )
        let root = try jsonObject(data, provider: "Serper")
        let objects = (root["shopping"] as? [[String: Any]])
            ?? (root["organic"] as? [[String: Any]])
            ?? []
        let results = productResults(
            objects: objects,
            provider: "Serper",
            searchID: searchID,
            limit: limit
        )
        guard !results.isEmpty else { throw ProductSearchError.noResults }
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One Serper shopping query returned \(results.count) usable results"
        )
    }

    func directImageSearch(
        provider: ImageSearchProvider,
        imageData: Data,
        targetLabel: String,
        publicImageURL: URL?,
        apiKey: String,
        brightDataZone: String,
        limit: Int,
        searchID: String
    ) async throws -> SearchProviderResponse {
        switch provider {
        case .lykdat:
            return try await lykdatSearch(
                imageData: imageData,
                targetLabel: targetLabel,
                apiKey: apiKey,
                limit: limit,
                searchID: searchID
            )
        case .searchAPI:
            guard let publicImageURL else {
                throw ProductSearchError.publicImageURLRequired(provider.title)
            }
            return try await searchAPISearch(
                imageURL: publicImageURL,
                apiKey: apiKey,
                limit: limit,
                searchID: searchID
            )
        case .serpAPI:
            guard let publicImageURL else {
                throw ProductSearchError.publicImageURLRequired(provider.title)
            }
            return try await serpAPISearch(
                imageURL: publicImageURL,
                apiKey: apiKey,
                limit: limit,
                searchID: searchID
            )
        case .brightData:
            guard let publicImageURL else {
                throw ProductSearchError.publicImageURLRequired(provider.title)
            }
            guard !brightDataZone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProductSearchError.missingBrightDataZone
            }
            return try await brightDataSearch(
                imageURL: publicImageURL,
                apiKey: apiKey,
                zone: brightDataZone,
                limit: limit,
                searchID: searchID
            )
        }
    }

    private func lykdatSearch(
        imageData: Data,
        targetLabel: String,
        apiKey: String,
        limit: Int,
        searchID: String
    ) async throws -> SearchProviderResponse {
        let boundary = "Stylezam-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipart(name: "api_key", value: apiKey, boundary: boundary)
        body.appendMultipart(
            name: "image",
            filename: "garment.jpg",
            contentType: "image/jpeg",
            data: imageData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")
        var request = URLRequest(url: URL(string: "https://cloudapi.lykdat.com/v1/global/search")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 9
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await send(request, provider: "Lykdat")
        let root = try jsonObject(data, provider: "Lykdat")
        let selectedGroup = bestLykdatGroup(in: root, targetLabel: targetLabel)
        let objects = (selectedGroup?["similar_products"] as? [[String: Any]])
            ?? selectedGroup.map(findProductObjects)
            ?? findProductObjects(in: root)
        let results = productResults(
            objects: objects,
            provider: "Lykdat",
            searchID: searchID,
            limit: limit
        )
        guard !results.isEmpty else { throw ProductSearchError.noResults }
        let detectedName = ((selectedGroup?["detected_item"] as? [String: Any])?["name"] as? String)
            ?? "fashion item"
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One Lykdat image request matched the \(detectedName) group and returned \(results.count) usable products"
        )
    }

    private func searchAPISearch(
        imageURL: URL,
        apiKey: String,
        limit: Int,
        searchID: String
    ) async throws -> SearchProviderResponse {
        var components = URLComponents(string: "https://www.searchapi.io/api/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "engine", value: "google_lens"),
            URLQueryItem(name: "search_type", value: "products"),
            URLQueryItem(name: "url", value: imageURL.absoluteString),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request, provider: "SearchAPI.io")
        let root = try jsonObject(data, provider: "SearchAPI.io")
        let objects = root["visual_matches"] as? [[String: Any]] ?? []
        let results = productResults(objects: objects, provider: "SearchAPI.io", searchID: searchID, limit: limit)
        guard !results.isEmpty else { throw ProductSearchError.noResults }
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One SearchAPI.io Google Lens request returned \(results.count) usable visual matches"
        )
    }

    private func serpAPISearch(
        imageURL: URL,
        apiKey: String,
        limit: Int,
        searchID: String
    ) async throws -> SearchProviderResponse {
        var components = URLComponents(string: "https://serpapi.com/search.json")!
        components.queryItems = [
            URLQueryItem(name: "engine", value: "google_lens"),
            URLQueryItem(name: "type", value: "products"),
            URLQueryItem(name: "url", value: imageURL.absoluteString),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        let (data, response) = try await send(URLRequest(url: components.url!), provider: "SerpApi")
        let root = try jsonObject(data, provider: "SerpApi")
        let objects = root["visual_matches"] as? [[String: Any]] ?? []
        let results = productResults(objects: objects, provider: "SerpApi", searchID: searchID, limit: limit)
        guard !results.isEmpty else { throw ProductSearchError.noResults }
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One SerpApi Google Lens request returned \(results.count) usable visual matches"
        )
    }

    private func brightDataSearch(
        imageURL: URL,
        apiKey: String,
        zone: String,
        limit: Int,
        searchID: String
    ) async throws -> SearchProviderResponse {
        var lens = URLComponents(string: "https://lens.google.com/uploadbyurl")!
        lens.queryItems = [
            URLQueryItem(name: "url", value: imageURL.absoluteString),
            URLQueryItem(name: "brd_lens", value: "products"),
            URLQueryItem(name: "brd_json", value: "1"),
        ]
        let body: [String: Any] = [
            "zone": zone,
            "url": lens.url!.absoluteString,
            "format": "json",
            "method": "GET",
            "country": "us",
            "data_format": "parsed_light",
        ]
        let (data, response) = try await sendJSON(
            url: URL(string: "https://api.brightdata.com/request")!,
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"],
            provider: "Bright Data"
        )
        let envelope = try jsonObject(data, provider: "Bright Data")
        if let innerStatus = integer(envelope["status_code"]), innerStatus != 200 {
            throw ProductSearchError.provider(
                "Bright Data reached its API, but the Google Lens request failed with HTTP \(innerStatus). Check that the configured zone is a SERP API zone with Lens access."
            )
        }
        let root: [String: Any]
        if let body = envelope["body"] as? [String: Any] {
            root = body
        } else if let text = envelope["body"] as? String,
                  let bodyData = text.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        {
            root = parsed
        } else {
            root = envelope
        }
        let objects = (root["visual_matches"] as? [[String: Any]]) ?? findProductObjects(in: root)
        let results = productResults(objects: objects, provider: "Bright Data", searchID: searchID, limit: limit)
        guard !results.isEmpty else {
            throw ProductSearchError.provider(
                "Bright Data returned the Google Lens page but no supported structured product records. Confirm that the selected zone returns parsed Google Lens JSON."
            )
        }
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One Bright Data request returned \(results.count) usable visual matches"
        )
    }

    private func sendJSON(
        url: URL,
        body: [String: Any],
        headers: [String: String],
        provider: String
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return try await send(request, provider: provider)
    }

    private func send(_ request: URLRequest, provider: String) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, rawResponse) = try await session.data(for: request)
            guard let response = rawResponse as? HTTPURLResponse else {
                throw ProductSearchError.invalidResponse(provider)
            }
            guard 200..<300 ~= response.statusCode else {
                let hint: String
                switch response.statusCode {
                case 401, 403: hint = "Check the saved credential and account access."
                case 402: hint = "The provider requires billing or has exhausted its allowance."
                case 429: hint = "The provider rate or monthly limit was reached."
                default: hint = "The provider returned HTTP \(response.statusCode)."
                }
                throw ProductSearchError.provider("\(provider): \(hint)")
            }
            return (data, response)
        } catch let error as ProductSearchError {
            throw error
        } catch {
            throw ProductSearchError.provider("\(provider): \(error.localizedDescription)")
        }
    }

    private func jsonObject(_ data: Data, provider: String) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProductSearchError.invalidResponse(provider)
        }
        return root
    }

    private func jsonData(fromPossiblyFenced text: String) -> Data? {
        if let direct = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: direct)) != nil
        {
            return direct
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    private func findProductObjects(in value: Any) -> [[String: Any]] {
        if let array = value as? [[String: Any]],
           array.contains(where: { productURLString($0) != nil })
        {
            return array
        }
        if let array = value as? [Any] {
            return array.flatMap(findProductObjects)
        }
        if let object = value as? [String: Any] {
            return object.values.flatMap(findProductObjects)
        }
        return []
    }

    private func bestLykdatGroup(
        in root: [String: Any],
        targetLabel: String
    ) -> [String: Any]? {
        guard let data = root["data"] as? [String: Any],
              let groups = data["result_groups"] as? [[String: Any]],
              !groups.isEmpty
        else { return nil }

        let targetTerms = lykdatTerms(for: targetLabel)
        return groups.max { left, right in
            lykdatGroupScore(left, targetTerms: targetTerms)
                < lykdatGroupScore(right, targetTerms: targetTerms)
        }
    }

    private func lykdatGroupScore(
        _ group: [String: Any],
        targetTerms: Set<String>
    ) -> Double {
        let detected = group["detected_item"] as? [String: Any]
        let name = string(detected?["name"])?.lowercased() ?? ""
        let category = string(detected?["category"])?.lowercased() ?? ""
        let providerTerms = Set(
            "\(name) \(category)"
                .split { !$0.isLetter }
                .map { String($0) }
        )
        let labelMatch = targetTerms.isDisjoint(with: providerTerms) ? 0.0 : 100.0
        let box = detected?["bounding_box"] as? [String: Any]
        let left = number(box?["left"]) ?? 0
        let right = number(box?["right"]) ?? 0
        let top = number(box?["top"]) ?? 0
        let bottom = number(box?["bottom"]) ?? 0
        let area = max(0, right - left) * max(0, bottom - top)
        let rank = number(group["rank_score"]) ?? number(group["max_score"]) ?? 0
        return labelMatch + area + rank
    }

    private func lykdatTerms(for localLabel: String) -> Set<String> {
        let label = localLabel.lowercased()
        if label.contains("bag") || label.contains("wallet") {
            return ["bag", "bags", "wallet", "wallets", "handbag", "handbags", "purse", "purses", "briefcase", "briefcases"]
        }
        if label.contains("dress") || label.contains("jumpsuit") {
            return ["dress", "dresses", "jumpsuit", "jumpsuits"]
        }
        if label.contains("shoe") {
            return ["shoe", "shoes", "footwear", "sneaker", "sneakers", "boot", "boots"]
        }
        if label.contains("shirt") || label.contains("top") || label.contains("sweater") || label.contains("cardigan") {
            return ["shirt", "shirts", "top", "tops", "sweater", "sweaters", "cardigan", "cardigans"]
        }
        if label.contains("jacket") || label.contains("coat") || label.contains("cape") || label.contains("vest") {
            return ["jacket", "jackets", "coat", "coats", "outerwear", "cape", "capes", "vest", "vests"]
        }
        if label.contains("pants") || label.contains("shorts") || label.contains("skirt") {
            return ["pants", "trousers", "shorts", "skirt", "skirts", "bottom", "bottoms"]
        }
        return Set(
            label.split { !$0.isLetter }.map { String($0) }
        )
    }

    private func productResults(
        objects: [[String: Any]],
        provider: String,
        searchID: String,
        limit: Int
    ) -> [ProductResultDTO] {
        var seen = Set<String>()
        return objects.enumerated().compactMap { index, object in
            guard let title = string(object["title"]) ?? string(object["name"]),
                  let link = productURLString(object),
                  let productURL = URL(string: link),
                  ["http", "https"].contains(productURL.scheme?.lowercased() ?? ""),
                  seen.insert(productURL.absoluteString).inserted
            else { return nil }
            let merchant = string(object["source"])
                ?? string(object["merchant"])
                ?? string(object["vendor"])
                ?? string(object["brand_name"])
                ?? string(object["domain"])
                ?? productURL.host()
                ?? provider
            let image = string(object["imageUrl"])
                ?? string(object["image_url"])
                ?? string(object["thumbnail"])
                ?? string(object["image"])
                ?? string(object["matching_image"])
                ?? firstString(in: object["images"])
            let priceValue = [object["reduced_price"], object["sale_price"], object["price"]]
                .compactMap { value -> Any? in
                    guard let value, !(value is NSNull) else { return nil }
                    return value
                }
                .first
            let price = money(priceValue)
            let score = min(1, max(0, number(object["score"]) ?? max(0.45, 1 - (Double(index) * 0.035))))
            let stable = SHA256.hash(data: Data("\(provider)|\(productURL.absoluteString)".utf8))
                .map { String(format: "%02x", $0) }.joined()
            return ProductResultDTO(
                id: stable,
                searchID: searchID,
                provider: provider,
                providerResultID: string(object["id"]) ?? string(object["product_id"]),
                title: title,
                brand: string(object["brand"]) ?? string(object["brand_name"]),
                category: string(object["category"]),
                color: nil,
                imageURL: image.flatMap(URL.init(string:)),
                productURL: productURL,
                merchant: merchant,
                price: price,
                matchTier: index < 3 ? .likely : .similar,
                score: score,
                rating: number(object["rating"]),
                reviewCount: integer(object["ratingCount"] ?? object["reviews"]),
                attributes: [:],
                offers: []
            )
        }.prefix(max(1, limit)).map { $0 }
    }

    private func productURLString(_ object: [String: Any]) -> String? {
        string(object["link"])
            ?? string(object["url"])
            ?? string(object["product_url"])
            ?? string(object["productUrl"])
    }

    private func money(_ value: Any?) -> MoneyDTO? {
        if let object = value as? [String: Any] {
            guard let amount = number(object["value"] ?? object["amount"]) else { return nil }
            let currency = string(object["currency"]) ?? "USD"
            return MoneyDTO(amount: amount, currency: currency, display: string(object["display"]))
        }
        guard let text = string(value) else { return nil }
        let filtered = text.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: "")
        guard let amount = Double(filtered) else { return nil }
        let currency: String
        if text.contains("£") { currency = "GBP" }
        else if text.contains("€") { currency = "EUR" }
        else if text.contains("¥") { currency = "JPY" }
        else { currency = "USD" }
        return MoneyDTO(amount: amount, currency: currency, display: text)
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func firstString(in value: Any?) -> String? {
        guard let values = value as? [Any] else { return nil }
        return values.lazy.compactMap(string).first
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipart(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendMultipart(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
}
