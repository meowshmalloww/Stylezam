import CryptoKit
import Foundation

actor ProductSearchService {
    private enum ScoreFallback: Equatable {
        case none
        case queryOverlap
    }

    private struct TryOnPresentationPayload: Decodable {
        let presentation: String
    }

    private struct AssistantPayload: Decodable {
        let answer: String
        let suggestedQuestions: [String]

        private enum CodingKeys: String, CodingKey {
            case answer
            case suggestedQuestions = "suggested_questions"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            answer = try container.decode(String.self, forKey: .answer)
            suggestedQuestions = try container.decodeIfPresent(
                [String].self,
                forKey: .suggestedQuestions
            ) ?? []
        }
    }

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
        searchIntent: AIShoppingSearchIntent? = nil,
        ownedWardrobeContext: [String] = [],
        apiKey: String,
        modelID: String
    ) async throws -> (GarmentUnderstanding, SearchProviderResponse) {
        let refinementInstruction = refinement.map {
            "The user wants this refinement: \($0). Incorporate it into the search query without inventing facts."
        } ?? ""
        let intentInstruction: String
        switch searchIntent {
        case .similar:
            intentInstruction = "Optimize the query for visually similar alternatives. Preserve the visible category, silhouette, color, pattern, and construction details that make this piece distinctive."
        case .cheaper:
            intentInstruction = "Optimize the query for lower-priced alternatives. Keep the visible category and defining style details, use budget-oriented terms only when useful, and never invent a price."
        case nil:
            intentInstruction = "Optimize the query for useful shopping matches to the visible item."
        }
        let prompt = """
        Analyze only the main fashion item in this crop. The on-device detector called it \(localLabel).
        Return strict JSON with these keys:
        summary (one short factual sentence), search_query (6-14 useful shopping search words),
        suggestions (exactly 3 shorter alternative shopping queries), category (string or null),
        colors (array), materials (array), patterns (array).
        Do not invent a brand. Include visible brand/model text only when clearly readable.
        \(intentInstruction)
        \(refinementInstruction)
        \(ownedWardrobeContext.isEmpty ? "" : "The user owns these relevant pieces: \(ownedWardrobeContext.prefix(4).joined(separator: "; ")). Make the shopping query coordinate with them when that helps the request, but do not search for the owned pieces themselves.")
        """
        let imageURL = imageDataURL(for: imageData)
        let body: [String: Any] = [
            "model": modelID,
            "reasoning_effort": "none",
            "temperature": 0.1,
            "max_tokens": 520,
            "response_format": garmentResponseFormat(),
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
        let choices = root["choices"] as? [[String: Any]] ?? []
        guard let message = choices.first?["message"] as? [String: Any],
              let content = messageText(message),
              let decoded = decodeGarmentUnderstanding(content)
        else {
            let finishReason = choices.first?["finish_reason"] as? String
            if finishReason == "length" {
                throw ProductSearchError.provider(
                    "Stylezam AI reached its response limit before it could prepare the shopping search. Try the action again."
                )
            }
            throw ProductSearchError.provider(
                "Stylezam AI returned incomplete shopping details. Try the action again."
            )
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
        libraryContext: [StylezamAssistantContextItem],
        history: [StylezamChatMessage],
        question: String,
        apiKey: String,
        modelID: String
    ) async throws -> (StylezamAssistantTurn, SearchProviderResponse) {
        let imageURL = imageDataURL(for: imageData)
        let boundedLibraryContext = Array(libraryContext.prefix(4))
        let systemPrompt = """
        You are Stylezam AI, a careful, useful fashion shopping assistant. Maintain context across the conversation and reason from the selected garment plus the few Library pieces retrieved on device for this question.

        Be direct and conversational. Explain visible construction, color, silhouette, styling, likely material, care, fit, and shopping terminology when relevant. Clearly distinguish what is visible from what is only likely. Never claim an exact brand, model, material, authenticity, store price, or availability unless it is explicit in the image or supplied conversation. If the user wants products or current prices, explain that Stylezam can perform a live shopping search.

        Library context is private owned-wardrobe context, not live inventory. Mention an owned piece only when relevant and call it "in your Library." Never imply that Bright Data or a shopping provider can browse the private Library.

        Return strict JSON with exactly these keys:
        answer: a useful answer, usually 1-4 short paragraphs.
        suggested_questions: 2 or 3 concise, relevant follow-up questions the user could ask next. Do not put product-search buttons in this list; the app provides Find similar and Find cheaper separately.
        """
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            [
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": "This is the selected fashion item for the conversation. The on-device detector label is \(localLabel). Use the image as persistent visual context, but do not overstate uncertain details.",
                    ],
                    ["type": "image_url", "image_url": ["url": imageURL]],
                ],
            ],
            [
                "role": "assistant",
                "content": "I’ll use this selected item as the visual context for our conversation.",
            ],
        ]
        if !boundedLibraryContext.isEmpty {
            var content: [[String: Any]] = [[
                "type": "text",
                "text": "On-device metadata retrieval selected these relevant owned pieces for this question. Only use what helps: " + boundedLibraryContext.map { "\($0.title) (\($0.category))" }.joined(separator: "; "),
            ]]
            // Keep the privacy/cost bound hard: selected crop plus at most two additional crops.
            for item in boundedLibraryContext.filter({ $0.imageData != nil }).prefix(2) {
                content.append([
                    "type": "text",
                    "text": "Relevant Library piece: \(item.title) (\(item.category))",
                ])
                content.append([
                    "type": "image_url",
                    "image_url": ["url": imageDataURL(for: item.imageData!)],
                ])
            }
            messages.append(["role": "user", "content": content])
            messages.append([
                "role": "assistant",
                "content": "I’ll use only the relevant Library pieces supplied for this question.",
            ])
        }
        for turn in boundedChatHistory(history) {
            messages.append([
                "role": turn.role == .user ? "user" : "assistant",
                "content": turn.text,
            ])
        }
        messages.append(["role": "user", "content": question])
        let body: [String: Any] = [
            "model": modelID,
            // Qwen 3.7 Plus can emit its analysis in the message body when a
            // constrained JSON answer exhausts a thinking budget. Non-thinking
            // mode is both faster and more reliable for this conversational UI.
            "reasoning_effort": "none",
            "temperature": 0.3,
            "max_tokens": 900,
            "response_format": assistantResponseFormat(),
            "messages": messages,
        ]
        let (data, response) = try await sendJSON(
            url: URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!,
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"],
            provider: "Fireworks"
        )
        let root = try jsonObject(data, provider: "Fireworks")
        let choices = root["choices"] as? [[String: Any]] ?? []
        guard let message = choices.first?["message"] as? [String: Any],
              let content = messageText(message),
              let turn = decodeAssistantTurn(content)
        else {
            let finishReason = choices.first?["finish_reason"] as? String
            if finishReason == "length" {
                throw ProductSearchError.provider(
                    "Stylezam AI reached its response limit before finishing. Try a shorter question."
                )
            }
            throw ProductSearchError.provider(
                "Stylezam AI returned an empty answer. Try the question again."
            )
        }
        let usage = root["usage"] as? [String: Any]
        return (
            turn,
            SearchProviderResponse(
                results: [],
                providerRequestID: response.value(forHTTPHeaderField: "x-request-id") ?? root["id"] as? String,
                inputTokens: integer(usage?["prompt_tokens"]),
                outputTokens: integer(usage?["completion_tokens"]),
                diagnostic: "Fireworks returned one contextual assistant turn"
            )
        )
    }

    func inferTryOnPresentation(
        imageData: Data,
        apiKey: String,
        modelID: String
    ) async throws -> (TryOnGender, SearchProviderResponse) {
        let body: [String: Any] = [
            "model": modelID,
            "reasoning_effort": "none",
            "temperature": 0,
            "max_tokens": 40,
            "response_format": tryOnPresentationResponseFormat(),
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": "Choose the YouCam binary presentation parameter that best preserves the visible person's current presentation in this photo. This is an image-rendering control, not a claim about identity. Return male or female only in the required JSON schema.",
                    ],
                    ["type": "image_url", "image_url": ["url": imageDataURL(for: imageData)]],
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
        let choices = root["choices"] as? [[String: Any]] ?? []
        guard let message = choices.first?["message"] as? [String: Any],
              let content = messageText(message),
              let json = jsonData(fromPossiblyFenced: content),
              let payload = try? JSONDecoder().decode(TryOnPresentationPayload.self, from: json),
              let gender = TryOnGender(rawValue: payload.presentation.lowercased()),
              gender.isProviderValue
        else {
            throw ProductSearchError.provider(
                "Automatic presentation could not be determined. Choose Male or Female and try again."
            )
        }
        let usage = root["usage"] as? [String: Any]
        return (
            gender,
            SearchProviderResponse(
                results: [],
                providerRequestID: response.value(forHTTPHeaderField: "x-request-id")
                    ?? root["id"] as? String,
                inputTokens: integer(usage?["prompt_tokens"]),
                outputTokens: integer(usage?["completion_tokens"]),
                diagnostic: "Fireworks selected the YouCam presentation parameter"
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
            limit: limit,
            targetLabel: query,
            scoreFallback: .queryOverlap
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

    func keywordProducts(
        provider: KeywordSearchProvider,
        query: String,
        apiKey: String,
        brightDataZone: String,
        country: String,
        language: String,
        limit: Int,
        searchID: String,
        cheaperFirst: Bool
    ) async throws -> SearchProviderResponse {
        switch provider {
        case .serper:
            return try await serperProducts(
                query: query,
                apiKey: apiKey,
                country: country,
                language: language,
                limit: limit,
                searchID: searchID
            )
        case .searchAPI:
            return try await searchAPIShopping(
                query: query,
                apiKey: apiKey,
                country: country,
                language: language,
                limit: limit,
                searchID: searchID,
                cheaperFirst: cheaperFirst
            )
        case .serpAPI:
            return try await serpAPIShopping(
                query: query,
                apiKey: apiKey,
                country: country,
                language: language,
                limit: limit,
                searchID: searchID,
                cheaperFirst: cheaperFirst
            )
        case .brightData:
            guard !brightDataZone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProductSearchError.missingBrightDataZone
            }
            return try await brightDataShopping(
                query: query,
                apiKey: apiKey,
                zone: brightDataZone,
                country: country,
                language: language,
                limit: limit,
                searchID: searchID
            )
        }
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
        case .googleVision:
            return try await googleVisionWebSearch(
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
                searchID: searchID,
                targetLabel: targetLabel
            )
        case .serpAPI:
            guard let publicImageURL else {
                throw ProductSearchError.publicImageURLRequired(provider.title)
            }
            return try await serpAPISearch(
                imageURL: publicImageURL,
                apiKey: apiKey,
                limit: limit,
                searchID: searchID,
                targetLabel: targetLabel
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
                searchID: searchID,
                targetLabel: targetLabel
            )
        }
    }

    private func googleVisionWebSearch(
        imageData: Data,
        targetLabel: String,
        apiKey: String,
        limit: Int,
        searchID: String
    ) async throws -> SearchProviderResponse {
        // One image and exactly one feature keeps this Stylezam action to one
        // Google Cloud Vision billable unit. Do not add LABEL/TEXT/LOGO features
        // to this request without revisiting the unit budget.
        let body: [String: Any] = [
            "requests": [[
                "image": ["content": imageData.base64EncodedString()],
                "features": [[
                    "type": "WEB_DETECTION",
                    "maxResults": min(20, max(1, limit)),
                ]],
            ]],
        ]
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.stylezam.app"
        let (data, response) = try await sendJSON(
            url: URL(string: "https://vision.googleapis.com/v1/images:annotate")!,
            body: body,
            headers: [
                "X-Goog-Api-Key": apiKey,
                "X-Ios-Bundle-Identifier": bundleIdentifier,
            ],
            provider: "Google Cloud Vision"
        )
        let root = try jsonObject(data, provider: "Google Cloud Vision")
        guard let responses = root["responses"] as? [[String: Any]],
              let annotation = responses.first
        else {
            throw ProductSearchError.invalidResponse("Google Cloud Vision")
        }
        if let error = annotation["error"] as? [String: Any] {
            let message = string(error["message"])
                ?? "Google Cloud Vision could not analyze this crop."
            throw ProductSearchError.provider("Google Cloud Vision: \(message)")
        }
        guard let web = annotation["webDetection"] as? [String: Any] else {
            throw ProductSearchError.noResults
        }

        let bestGuess = (web["bestGuessLabels"] as? [[String: Any]])?
            .compactMap { string($0["label"]) }
            .first
        let topEntity = (web["webEntities"] as? [[String: Any]])?
            .sorted { (number($0["score"]) ?? 0) > (number($1["score"]) ?? 0) }
            .compactMap { string($0["description"]) }
            .first
        let subject = bestGuess ?? topEntity ?? targetLabel
        let pages = web["pagesWithMatchingImages"] as? [[String: Any]] ?? []
        let fullImages = web["fullMatchingImages"] as? [[String: Any]] ?? []
        let partialImages = web["partialMatchingImages"] as? [[String: Any]] ?? []
        let similarImages = web["visuallySimilarImages"] as? [[String: Any]] ?? []

        var candidates: [ProductResultDTO] = []
        var seenURLs: Set<String> = []

        for page in pages {
            guard let rawURL = string(page["url"]),
                  let pageURL = webURL(rawURL),
                  seenURLs.insert(pageURL.absoluteString).inserted
            else { continue }
            let pageFullImages = page["fullMatchingImages"] as? [[String: Any]] ?? []
            let pagePartialImages = page["partialMatchingImages"] as? [[String: Any]] ?? []
            let matchingImage = (pageFullImages + pagePartialImages).first
            let imageURL = string(matchingImage?["url"]).flatMap(webURL)
            let hasFullMatch = !pageFullImages.isEmpty
            let rawScore = number(page["score"]) ?? number(matchingImage?["score"])
            let score = boundedGoogleVisionScore(
                rawScore,
                evidence: hasFullMatch ? .exact : .likely
            )
            let rawTitle = string(page["pageTitle"])
            let title = rawTitle.map(cleanWebTitle)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? "\(subject) on \(pageURL.host() ?? "the web")"
            candidates.append(
                googleVisionResult(
                    searchID: searchID,
                    pageURL: pageURL,
                    imageURL: imageURL,
                    title: title,
                    evidence: hasFullMatch ? "Full matching image page" : "Partial matching image page",
                    matchTier: hasFullMatch ? .exact : .likely,
                    score: score,
                    scoreIsMeasured: rawScore != nil
                )
            )
        }

        let standalone: [(objects: [[String: Any]], evidence: String, tier: MatchTier)] = [
            (fullImages, "Full matching web image", .exact),
            (partialImages, "Partial matching web image", .likely),
            (similarImages, "Visually similar web image", .similar),
        ]
        for group in standalone {
            for object in group.objects {
                guard let rawURL = string(object["url"]),
                      let imageURL = webURL(rawURL),
                      seenURLs.insert(imageURL.absoluteString).inserted
                else { continue }
                let host = imageURL.host() ?? "the web"
                let rawScore = number(object["score"])
                candidates.append(
                    googleVisionResult(
                        searchID: searchID,
                        pageURL: imageURL,
                        imageURL: imageURL,
                        title: "\(subject) · \(host)",
                        evidence: group.evidence,
                        matchTier: group.tier,
                        score: boundedGoogleVisionScore(rawScore, evidence: group.tier),
                        scoreIsMeasured: rawScore != nil
                    )
                )
            }
        }

        let results = Array(
            candidates
                .sorted { left, right in
                    if left.matchTier != right.matchTier {
                        return googleVisionTierRank(left.matchTier) > googleVisionTierRank(right.matchTier)
                    }
                    return left.score > right.score
                }
                .prefix(max(1, limit))
        )
        guard !results.isEmpty else { throw ProductSearchError.noResults }
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-guploader-uploadid")
                ?? response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One Google Web Detection unit returned \(results.count) usable matching pages or images"
        )
    }

    private func googleVisionResult(
        searchID: String,
        pageURL: URL,
        imageURL: URL?,
        title: String,
        evidence: String,
        matchTier: MatchTier,
        score: Double,
        scoreIsMeasured: Bool
    ) -> ProductResultDTO {
        let provider = "Google Cloud Vision"
        let stable = SHA256.hash(data: Data("\(provider)|\(pageURL.absoluteString)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return ProductResultDTO(
            id: stable,
            searchID: searchID,
            provider: provider,
            providerResultID: nil,
            title: title,
            brand: nil,
            category: nil,
            color: nil,
            imageURL: imageURL,
            productURL: pageURL,
            merchant: pageURL.host() ?? provider,
            price: nil,
            matchTier: matchTier,
            score: score,
            rating: nil,
            reviewCount: nil,
            attributes: [
                "webEvidence": .string(evidence),
                "scoreBasis": scoreIsMeasured ? .string("provider") : .null,
            ],
            offers: []
        )
    }

    private func boundedGoogleVisionScore(_ score: Double?, evidence: MatchTier) -> Double {
        if let score { return min(1, max(0, score)) }
        // Some Web Detection response surfaces omit their score. Keep a neutral
        // ordering value rather than fabricating provider precision.
        switch evidence {
        case .exact: return 0.5
        case .likely: return 0.49
        case .similar: return 0.48
        case .inspired: return 0.47
        }
    }

    private func googleVisionTierRank(_ tier: MatchTier) -> Int {
        switch tier {
        case .exact: 4
        case .likely: 3
        case .similar: 2
        case .inspired: 1
        }
    }

    private func webURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    private func cleanWebTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            limit: limit,
            targetLabel: targetLabel
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
        searchID: String,
        targetLabel: String
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
        let results = productResults(
            objects: objects,
            provider: "SearchAPI.io",
            searchID: searchID,
            limit: limit,
            targetLabel: targetLabel
        )
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
        searchID: String,
        targetLabel: String
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
        let results = productResults(
            objects: objects,
            provider: "SerpApi",
            searchID: searchID,
            limit: limit,
            targetLabel: targetLabel
        )
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
        searchID: String,
        targetLabel: String
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
        let results = productResults(
            objects: objects,
            provider: "Bright Data",
            searchID: searchID,
            limit: limit,
            targetLabel: targetLabel
        )
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

    private func searchAPIShopping(
        query: String,
        apiKey: String,
        country: String,
        language: String,
        limit: Int,
        searchID: String,
        cheaperFirst: Bool
    ) async throws -> SearchProviderResponse {
        var components = URLComponents(string: "https://www.searchapi.io/api/v1/search")!
        var queryItems = [
            URLQueryItem(name: "engine", value: "google_shopping"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "gl", value: country),
            URLQueryItem(name: "hl", value: language),
        ]
        if cheaperFirst {
            queryItems.append(URLQueryItem(name: "sort_by", value: "price_low_to_high"))
        }
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request, provider: "SearchAPI.io")
        let root = try jsonObject(data, provider: "SearchAPI.io")
        let objects = (root["shopping_results"] as? [[String: Any]])
            ?? (root["shopping_ads"] as? [[String: Any]])
            ?? (root["inline_shopping"] as? [[String: Any]])
            ?? []
        let results = productResults(
            objects: objects,
            provider: "SearchAPI.io",
            searchID: searchID,
            limit: limit,
            targetLabel: query,
            scoreFallback: .queryOverlap
        )
        guard !results.isEmpty else { throw ProductSearchError.noResults }
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One SearchAPI.io Shopping query returned \(results.count) usable results"
        )
    }

    private func serpAPIShopping(
        query: String,
        apiKey: String,
        country: String,
        language: String,
        limit: Int,
        searchID: String,
        cheaperFirst: Bool
    ) async throws -> SearchProviderResponse {
        var components = URLComponents(string: "https://serpapi.com/search.json")!
        var queryItems = [
            URLQueryItem(name: "engine", value: "google_shopping"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "gl", value: country),
            URLQueryItem(name: "hl", value: language),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        if cheaperFirst {
            queryItems.append(URLQueryItem(name: "sort_by", value: "1"))
        }
        components.queryItems = queryItems
        let (data, response) = try await send(
            URLRequest(url: components.url!),
            provider: "SerpApi"
        )
        let root = try jsonObject(data, provider: "SerpApi")
        let objects = (root["shopping_results"] as? [[String: Any]])
            ?? (root["inline_shopping"] as? [[String: Any]])
            ?? []
        let results = productResults(
            objects: objects,
            provider: "SerpApi",
            searchID: searchID,
            limit: limit,
            targetLabel: query,
            scoreFallback: .queryOverlap
        )
        guard !results.isEmpty else { throw ProductSearchError.noResults }
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One SerpApi Shopping query returned \(results.count) usable results"
        )
    }

    private func brightDataShopping(
        query: String,
        apiKey: String,
        zone: String,
        country: String,
        language: String,
        limit: Int,
        searchID: String
    ) async throws -> SearchProviderResponse {
        var target = URLComponents(string: "https://www.google.com/search")!
        target.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: language),
            URLQueryItem(name: "gl", value: country),
            URLQueryItem(name: "udm", value: "28"),
        ]
        let body: [String: Any] = [
            "zone": zone,
            "url": target.url!.absoluteString,
            "format": "json",
            "method": "GET",
            "country": country,
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
                "Bright Data reached its API, but Shopping returned HTTP \(innerStatus). Check the configured SERP zone."
            )
        }
        let root = nestedJSONBody(in: envelope)
        let objects = (root["shopping"] as? [[String: Any]])
            ?? (root["shopping_results"] as? [[String: Any]])
            ?? (root["products"] as? [[String: Any]])
            ?? findProductObjects(in: root)
        let results = productResults(
            objects: objects,
            provider: "Bright Data",
            searchID: searchID,
            limit: limit,
            targetLabel: query,
            scoreFallback: .queryOverlap
        )
        guard !results.isEmpty else {
            throw ProductSearchError.provider(
                "Bright Data returned Shopping data but no supported product records. Confirm that the zone returns parsed JSON."
            )
        }
        return SearchProviderResponse(
            results: results,
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id"),
            inputTokens: nil,
            outputTokens: nil,
            diagnostic: "One Bright Data Shopping query returned \(results.count) usable results"
        )
    }

    private func nestedJSONBody(in envelope: [String: Any]) -> [String: Any] {
        if let body = envelope["body"] as? [String: Any] {
            return body
        }
        if let text = envelope["body"] as? String,
           let data = text.data(using: .utf8),
           let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return body
        }
        return envelope
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
                if provider == "Google Cloud Vision",
                   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = root["error"] as? [String: Any],
                   let message = string(error["message"])
                {
                    let normalized = message.lowercased()
                    if normalized.contains("billing") {
                        hint = "Google requires billing to be linked even for the first 1,000 free Vision units each month. In Google Cloud Console, open the API key's project, link a Billing account, enable Cloud Vision API, then restrict the key to Cloud Vision API and the iOS app com.stylezam.app. This failed request did not affect local detection, crops, Library, or Try On. Tap Search again to use the next ready visual provider. Stylezam stops sending Google requests at its local 1,000-unit limit."
                    } else if normalized.contains("has not been used") || normalized.contains("is disabled") {
                        hint = "Enable Cloud Vision API on the key's Google Cloud project, then wait for the setting to propagate."
                    } else {
                        hint = message
                    }
                } else {
                    switch response.statusCode {
                    case 401, 403: hint = "The developer-managed credential or account access needs attention."
                    case 402: hint = "The provider requires billing or has exhausted its allowance."
                    case 429: hint = "The provider rate or monthly limit was reached."
                    default: hint = "The provider returned HTTP \(response.statusCode)."
                    }
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

    private func boundedChatHistory(_ history: [StylezamChatMessage]) -> [StylezamChatMessage] {
        var result: [StylezamChatMessage] = []
        var characterCount = 0
        for message in history.suffix(18).reversed() {
            let length = message.text.count
            guard characterCount + length <= 8_000 || result.isEmpty else { break }
            result.insert(message, at: 0)
            characterCount += length
        }
        return result
    }

    private func decodeAssistantTurn(_ content: String) -> StylezamAssistantTurn? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = jsonData(fromPossiblyFenced: trimmed),
           let json = try? JSONSerialization.jsonObject(with: data),
           json is [String: Any]
        {
            guard let payload = try? JSONDecoder().decode(AssistantPayload.self, from: data),
                  !payload.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }

            var seen: Set<String> = []
            let suggestions = payload.suggestedQuestions.compactMap { raw -> String? in
                let suggestion = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let identity = suggestion.lowercased()
                guard suggestion.count >= 4,
                      suggestion.count <= 100,
                      seen.insert(identity).inserted
                else { return nil }
                return suggestion
            }
            return StylezamAssistantTurn(
                answer: payload.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                suggestedQuestions: Array(suggestions.prefix(3))
            )
        }

        return StylezamAssistantTurn(answer: trimmed, suggestedQuestions: [])
    }

    private func decodeGarmentUnderstanding(_ content: String) -> GarmentUnderstanding? {
        guard let data = jsonData(fromPossiblyFenced: content),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = string(object["search_query"])
                ?? string(object["searchQuery"])
                ?? string(object["query"]),
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        func strings(_ value: Any?) -> [String] {
            guard let values = value as? [Any] else { return [] }
            return values.compactMap(string)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return GarmentUnderstanding(
            summary: string(object["summary"]) ?? "Shopping terms prepared from the selected piece.",
            searchQuery: query.trimmingCharacters(in: .whitespacesAndNewlines),
            suggestions: Array(strings(object["suggestions"]).prefix(3)),
            category: string(object["category"]),
            colors: strings(object["colors"]),
            materials: strings(object["materials"]),
            patterns: strings(object["patterns"])
        )
    }

    private func messageText(_ message: [String: Any]) -> String? {
        if let content = string(message["content"]),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return content
        }
        guard let parts = message["content"] as? [[String: Any]] else { return nil }
        let text = parts.compactMap { part in
            string(part["text"]) ?? string(part["content"])
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func imageDataURL(for data: Data) -> String {
        let isPNG = data.count >= 8 && Array(data.prefix(8)) == [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ]
        let mediaType = isPNG ? "image/png" : "image/jpeg"
        return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }

    private func garmentResponseFormat() -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": "stylezam_garment_search",
                "schema": [
                    "type": "object",
                    "properties": [
                        "summary": ["type": "string"],
                        "search_query": ["type": "string"],
                        "suggestions": [
                            "type": "array",
                            "items": ["type": "string"],
                        ] as [String: Any],
                        "category": [
                            "anyOf": [
                                ["type": "string"],
                                ["type": "null"],
                            ],
                        ],
                        "colors": ["type": "array", "items": ["type": "string"]],
                        "materials": ["type": "array", "items": ["type": "string"]],
                        "patterns": ["type": "array", "items": ["type": "string"]],
                    ] as [String: Any],
                    "required": [
                        "summary", "search_query", "suggestions", "category",
                        "colors", "materials", "patterns",
                    ],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    private func assistantResponseFormat() -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": "stylezam_assistant_turn",
                "schema": [
                    "type": "object",
                    "properties": [
                        "answer": ["type": "string"],
                        "suggested_questions": [
                            "type": "array",
                            "items": ["type": "string"],
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": ["answer", "suggested_questions"],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    private func tryOnPresentationResponseFormat() -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": "stylezam_try_on_presentation",
                "schema": [
                    "type": "object",
                    "properties": [
                        "presentation": [
                            "type": "string",
                            "enum": ["male", "female"],
                        ],
                    ] as [String: Any],
                    "required": ["presentation"],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
        ]
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
        limit: Int,
        targetLabel: String? = nil,
        scoreFallback: ScoreFallback = .none
    ) -> [ProductResultDTO] {
        let targetTerms = normalizedTerms(targetLabel ?? "")
        let candidates = objects.enumerated().compactMap { index, object -> ProductResultDTO? in
            guard let title = string(object["title"]) ?? string(object["name"]),
                  let link = productURLString(object),
                  let productURL = URL(string: link),
                  ["http", "https"].contains(productURL.scheme?.lowercased() ?? "")
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
            let titleTerms = normalizedTerms(
                [title, string(object["category"]), string(object["brand"])]
                    .compactMap { $0 }
                    .joined(separator: " ")
            )
            let overlap = targetTerms.isEmpty
                ? 0
                : Double(targetTerms.intersection(titleTerms).count) / Double(targetTerms.count)
            let rawProviderScore = number(object["score"])
                ?? number(object["similarity"])
            let providerScore = rawProviderScore.map { $0 > 1 ? $0 / 100 : $0 }
            let score: Double
            let scoreBasis: String?
            if let providerScore {
                score = min(1, max(0, providerScore))
                scoreBasis = "provider"
            } else if scoreFallback == .queryOverlap, !targetTerms.isEmpty {
                score = min(1, max(0, overlap))
                scoreBasis = "query"
            } else {
                // Preserve the provider's result order without presenting an
                // invented similarity percentage to the user.
                score = max(0, 0.001 - (Double(index) * 0.000_001))
                scoreBasis = nil
            }
            let tier: MatchTier
            if scoreBasis == nil {
                tier = .similar
            } else {
                tier = score >= 0.58 ? .similar : .inspired
            }
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
                matchTier: tier,
                score: score,
                rating: number(object["rating"]),
                reviewCount: integer(object["ratingCount"] ?? object["reviews"]),
                attributes: scoreBasis.map { ["scoreBasis": .string($0)] } ?? [:],
                offers: []
            )
        }
        .sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }

        var grouped: [ProductResultDTO] = []
        var groupIndexByIdentity: [String: Int] = [:]

        for candidate in candidates {
            let identities = productIdentities(for: candidate)
            let duplicateIndex = identities.lazy.compactMap { groupIndexByIdentity[$0] }.first
            if let duplicateIndex {
                let primary = grouped[duplicateIndex]
                guard primary.productURL != candidate.productURL,
                      !primary.offers.contains(where: { $0.url == candidate.productURL })
                else { continue }
                var offers = primary.offers
                offers.append(
                    MerchantOfferDTO(
                        merchant: candidate.merchant,
                        url: candidate.productURL,
                        price: candidate.price,
                        shipping: nil,
                        condition: nil
                    )
                )
                grouped[duplicateIndex] = ProductResultDTO(
                    id: primary.id,
                    searchID: primary.searchID,
                    provider: primary.provider,
                    providerResultID: primary.providerResultID,
                    title: primary.title,
                    brand: primary.brand,
                    category: primary.category,
                    color: primary.color,
                    imageURL: primary.imageURL,
                    productURL: primary.productURL,
                    merchant: primary.merchant,
                    price: primary.price,
                    matchTier: primary.matchTier,
                    score: max(primary.score, candidate.score),
                    rating: primary.rating,
                    reviewCount: primary.reviewCount,
                    attributes: primary.attributes,
                    offers: offers
                )
                for identity in identities { groupIndexByIdentity[identity] = duplicateIndex }
            } else {
                let newIndex = grouped.count
                grouped.append(candidate)
                for identity in identities { groupIndexByIdentity[identity] = newIndex }
            }
        }

        return Array(grouped.prefix(max(1, limit)))
    }

    private func productIdentities(for product: ProductResultDTO) -> [String] {
        var identities: [String] = []
        if let imageURL = product.imageURL,
           var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false)
        {
            components.query = nil
            components.fragment = nil
            if let normalized = components.string?.lowercased() {
                identities.append("image:\(normalized)")
            }
        }
        let title = normalizedTerms(product.title).sorted().joined(separator: "-")
        if title.count >= 10 { identities.append("title:\(title)") }
        var productComponents = URLComponents(url: product.productURL, resolvingAgainstBaseURL: false)
        productComponents?.query = nil
        productComponents?.fragment = nil
        if let normalized = productComponents?.string?.lowercased() {
            identities.append("url:\(normalized)")
        }
        return identities
    }

    private func normalizedTerms(_ text: String) -> Set<String> {
        let ignored: Set<String> = [
            "a", "an", "and", "at", "by", "for", "from", "in", "of", "on", "the", "to",
            "us", "uk", "au", "nz", "new", "sale", "women", "womens", "men", "mens",
        ]
        return Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 1 && !ignored.contains($0) }
        )
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
