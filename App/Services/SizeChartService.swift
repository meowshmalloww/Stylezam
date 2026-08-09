import Foundation

/// Fetches a merchant product page and extracts the published size chart —
/// the dimensions of every offered size — into structured data. The page HTML
/// is condensed on device and only that condensed text is sent to Fireworks
/// for structured extraction; no Library media is involved.
actor SizeChartService {
    enum Outcome: Sendable {
        /// The page published a usable per-size chart.
        case chart(GarmentSizeChart)
        /// The page loaded but no per-size dimensions were published on it.
        case notPublished(String)
    }

    private struct ExtractionPayload: Decodable {
        struct Size: Decodable {
            let label: String
            let chest: Double?
            let waist: Double?
            let hips: Double?
            let shoulders: Double?
            let length: Double?
            let sleeve: Double?
            let inseam: Double?
        }

        let found: Bool
        let basis: String
        let unit: String
        let sizes: [Size]
        let note: String?
    }

    private struct CachedEntry: Codable {
        let chart: GarmentSizeChart?
        let missReason: String?
        let fetchedAt: Date
    }

    private static let cacheLifetime: TimeInterval = 14 * 24 * 3_600
    private static let maxCondensedCharacters = 22_000

    private let session: URLSession
    private let cacheURL: URL
    private var cache: [String: CachedEntry]?

    init(rootURL: URL? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 25
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        session = URLSession(configuration: configuration)
        let root = rootURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Stylezam", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cacheURL = root.appending(path: "size-charts.json")
    }

    /// Returns a cached outcome when the product page was analyzed recently,
    /// without spending any provider budget.
    func cachedOutcome(for product: ProductResultDTO) -> Outcome? {
        loadCacheIfNeeded()
        guard let entry = cache?[product.id],
              Date().timeIntervalSince(entry.fetchedAt) < Self.cacheLifetime
        else { return nil }
        if let chart = entry.chart { return .chart(chart) }
        if let reason = entry.missReason { return .notPublished(reason) }
        return nil
    }

    func extractSizeChart(
        for product: ProductResultDTO,
        apiKey: String,
        modelID: String
    ) async throws -> (Outcome, SearchProviderResponse) {
        let html = try await fetchPage(product.productURL)
        let condensed = condense(html: html)
        guard !condensed.isEmpty else {
            let reason = "The merchant page did not include readable size details."
            store(productID: product.id, chart: nil, missReason: reason)
            return (
                .notPublished(reason),
                SearchProviderResponse(
                    results: [],
                    providerRequestID: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    diagnostic: "Merchant page contained no size-related text; Fireworks was not called"
                )
            )
        }

        let (payload, response) = try await extract(
            condensed: condensed,
            product: product,
            apiKey: apiKey,
            modelID: modelID
        )

        guard payload.found, !payload.sizes.isEmpty else {
            let reason = payload.note?.isEmpty == false
                ? payload.note!
                : "This merchant page does not publish per-size measurements."
            store(productID: product.id, chart: nil, missReason: reason)
            return (.notPublished(reason), response)
        }

        let toCm: (Double?) -> Double? = { value in
            guard let value, value > 0 else { return nil }
            return payload.unit == "in" ? value * 2.54 : value
        }
        let sizes: [GarmentSizeSpec] = payload.sizes.compactMap { size in
            var measurements: [GarmentDimension: Double] = [:]
            measurements[.chest] = toCm(size.chest)
            measurements[.waist] = toCm(size.waist)
            measurements[.hips] = toCm(size.hips)
            measurements[.shoulders] = toCm(size.shoulders)
            measurements[.length] = toCm(size.length)
            measurements[.sleeve] = toCm(size.sleeve)
            measurements[.inseam] = toCm(size.inseam)
            let label = size.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !measurements.isEmpty else { return nil }
            return GarmentSizeSpec(label: label, measurements: measurements)
        }
        guard !sizes.isEmpty else {
            let reason = "The published size chart had no usable numeric measurements."
            store(productID: product.id, chart: nil, missReason: reason)
            return (.notPublished(reason), response)
        }

        let chart = GarmentSizeChart(
            productID: product.id,
            sourceURL: product.productURL,
            basis: GarmentSizeChart.Basis(rawValue: payload.basis) ?? .unknown,
            sizes: sizes,
            sourceNote: payload.note,
            fetchedAt: .now
        )
        store(productID: product.id, chart: chart, missReason: nil)
        return (.chart(chart), response)
    }

    // MARK: - Page fetch

    private func fetchPage(_ url: URL) async throws -> String {
        let (data, rawResponse): (Data, URLResponse)
        do {
            (data, rawResponse) = try await session.data(from: url)
        } catch {
            throw ProductSearchError.provider(
                "Stylezam could not load the merchant page (\(url.host() ?? "unknown host")). Check the connection and try again."
            )
        }
        guard let response = rawResponse as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            let code = (rawResponse as? HTTPURLResponse)?.statusCode ?? 0
            throw ProductSearchError.provider(
                "The merchant page refused the request (HTTP \(code)). Some stores block automated size lookups; open the page in the browser instead."
            )
        }
        let capped = data.prefix(3_000_000)
        return String(decoding: capped, as: UTF8.self)
    }

    // MARK: - HTML condensing

    /// Reduces a product page to the text most likely to contain the size
    /// chart: table contents first, then keyword-adjacent prose.
    private func condense(html: String) -> String {
        var working = html
        for tag in ["script", "style", "svg", "noscript"] {
            working = working.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        var sections: [String] = []

        // Tables carry most size charts. Convert rows and cells to a pipe grid.
        let tablePattern = "<table[^>]*>[\\s\\S]*?</table>"
        if let regex = try? NSRegularExpression(pattern: tablePattern, options: [.caseInsensitive]) {
            let range = NSRange(working.startIndex..., in: working)
            for match in regex.matches(in: working, range: range).prefix(14) {
                guard let matchRange = Range(match.range, in: working) else { continue }
                let table = String(working[matchRange])
                let grid = tableToGrid(table)
                if grid.count > 40 { sections.append("TABLE:\n" + String(grid.prefix(5_000))) }
            }
        }

        // Keyword windows catch charts rendered as definition lists or prose.
        let plain = stripTags(working)
        let keywords = [
            "size chart", "size guide", "measurement", "measurements", "fits chest",
            "bust", "chest", "waist", "hip", "inseam", "shoulder", "sleeve",
            "length", "model is wearing", "true to size",
        ]
        var covered: [Range<String.Index>] = []
        for keyword in keywords {
            var searchStart = plain.startIndex
            var found = 0
            while found < 4,
                  let hit = plain.range(of: keyword, options: .caseInsensitive, range: searchStart..<plain.endIndex)
            {
                searchStart = hit.upperBound
                found += 1
                let start = plain.index(hit.lowerBound, offsetBy: -400, limitedBy: plain.startIndex) ?? plain.startIndex
                let end = plain.index(hit.upperBound, offsetBy: 600, limitedBy: plain.endIndex) ?? plain.endIndex
                let window = start..<end
                if !covered.contains(where: { $0.overlaps(window) }) {
                    covered.append(window)
                }
            }
        }
        for window in covered.sorted(by: { $0.lowerBound < $1.lowerBound }).prefix(18) {
            sections.append("TEXT:\n" + String(plain[window]))
        }

        var result = sections.joined(separator: "\n\n")
        if result.count > Self.maxCondensedCharacters {
            result = String(result.prefix(Self.maxCondensedCharacters))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tableToGrid(_ tableHTML: String) -> String {
        var rows: [String] = []
        let rowPattern = "<tr[^>]*>([\\s\\S]*?)</tr>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.caseInsensitive]) else {
            return stripTags(tableHTML)
        }
        let range = NSRange(tableHTML.startIndex..., in: tableHTML)
        for match in rowRegex.matches(in: tableHTML, range: range).prefix(40) {
            guard let matchRange = Range(match.range(at: 1), in: tableHTML) else { continue }
            let rowHTML = String(tableHTML[matchRange])
            let cells = rowHTML
                .replacingOccurrences(
                    of: "</t[dh]>",
                    with: " | ",
                    options: [.regularExpression, .caseInsensitive]
                )
            rows.append(stripTags(cells))
        }
        return rows.joined(separator: "\n")
    }

    private func stripTags(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<br[^>]*>|</p>|</div>|</li>|</h[1-6]>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'",
            "&lt;": "<", "&gt;": ">", "&frac12;": ".5", "&frac14;": ".25", "&frac34;": ".75",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AI extraction

    private func extract(
        condensed: String,
        product: ProductResultDTO,
        apiKey: String,
        modelID: String
    ) async throws -> (ExtractionPayload, SearchProviderResponse) {
        let prompt = """
        Below is condensed text from a merchant product page for: \(product.title) (merchant: \(product.merchant)).
        Extract the size chart if one is published: the numeric dimensions of every offered size.
        Rules:
        - Only report numbers that literally appear in the text. Never estimate or invent a value.
        - If a value is a range (e.g. 96-100), report the midpoint.
        - basis is "garment" when the numbers describe the garment measured flat, "body" when they describe the body each size fits, "unknown" when unstated.
        - unit is "cm" or "in" matching the numbers you report; convert nothing.
        - Use null for any dimension a size does not list. Map bust to chest and hip to hips.
        - If the page shows no per-size measurements, return found=false, an empty sizes array, and a one-sentence note saying what the page offers instead (e.g. only S/M/L labels).

        PAGE TEXT:
        \(condensed)
        """
        let body: [String: Any] = [
            "model": modelID,
            "reasoning_effort": "none",
            "temperature": 0,
            "max_tokens": 1_400,
            "response_format": sizeChartResponseFormat(),
            "messages": [[
                "role": "user",
                "content": prompt,
            ]],
        ]

        var request = URLRequest(url: URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, rawResponse): (Data, URLResponse)
        do {
            (data, rawResponse) = try await session.data(for: request)
        } catch {
            throw ProductSearchError.provider("Stylezam AI could not be reached to read the size chart. Try again.")
        }
        guard let response = rawResponse as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw ProductSearchError.provider(
                "Stylezam AI returned HTTP \((rawResponse as? HTTPURLResponse)?.statusCode ?? 0) while reading the size chart."
            )
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let payloadData = jsonData(fromPossiblyFenced: content),
              let payload = try? JSONDecoder().decode(ExtractionPayload.self, from: payloadData)
        else {
            throw ProductSearchError.provider("Stylezam AI returned an unreadable size chart. Try again.")
        }

        let usage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["usage"] as? [String: Any]
        let providerResponse = SearchProviderResponse(
            results: [],
            providerRequestID: response.value(forHTTPHeaderField: "x-request-id") ?? root["id"] as? String,
            inputTokens: (usage?["prompt_tokens"] as? NSNumber)?.intValue,
            outputTokens: (usage?["completion_tokens"] as? NSNumber)?.intValue,
            diagnostic: payload.found
                ? "Fireworks extracted \(payload.sizes.count) sizes from the merchant page"
                : "Fireworks confirmed the merchant page publishes no per-size measurements"
        )
        return (payload, providerResponse)
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

    private func sizeChartResponseFormat() -> [String: Any] {
        let numberOrNull: [String: Any] = [
            "anyOf": [["type": "number"], ["type": "null"]],
        ]
        return [
            "type": "json_schema",
            "json_schema": [
                "name": "stylezam_size_chart",
                "schema": [
                    "type": "object",
                    "properties": [
                        "found": ["type": "boolean"],
                        "basis": ["type": "string", "enum": ["garment", "body", "unknown"]] as [String: Any],
                        "unit": ["type": "string", "enum": ["cm", "in"]] as [String: Any],
                        "sizes": [
                            "type": "array",
                            "maxItems": 14,
                            "items": [
                                "type": "object",
                                "properties": [
                                    "label": ["type": "string"],
                                    "chest": numberOrNull,
                                    "waist": numberOrNull,
                                    "hips": numberOrNull,
                                    "shoulders": numberOrNull,
                                    "length": numberOrNull,
                                    "sleeve": numberOrNull,
                                    "inseam": numberOrNull,
                                ] as [String: Any],
                                "required": [
                                    "label", "chest", "waist", "hips",
                                    "shoulders", "length", "sleeve", "inseam",
                                ],
                                "additionalProperties": false,
                            ] as [String: Any],
                        ] as [String: Any],
                        "note": [
                            "anyOf": [["type": "string"], ["type": "null"]],
                        ],
                    ] as [String: Any],
                    "required": ["found", "basis", "unit", "sizes", "note"],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    // MARK: - Cache

    private func loadCacheIfNeeded() {
        guard cache == nil else { return }
        if let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = (try? decoder.decode([String: CachedEntry].self, from: data)) ?? [:]
        } else {
            cache = [:]
        }
    }

    private func store(productID: String, chart: GarmentSizeChart?, missReason: String?) {
        loadCacheIfNeeded()
        var updated = cache ?? [:]
        updated[productID] = CachedEntry(chart: chart, missReason: missReason, fetchedAt: .now)
        // Keep the newest 200 entries so the local cache stays small.
        if updated.count > 200 {
            let sorted = updated.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(200)
            updated = Dictionary(uniqueKeysWithValues: sorted.map { ($0.key, $0.value) })
        }
        cache = updated
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try? encoder.encode(updated).write(to: cacheURL, options: .atomic)
    }
}
