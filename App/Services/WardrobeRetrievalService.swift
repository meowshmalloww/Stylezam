import Foundation

struct WardrobeContextItem: Identifiable, Hashable, Sendable {
    var id: String { "\(scanID.uuidString):\(garmentID)" }
    let scanID: UUID
    let garmentID: String
    let title: String
    let category: String
    let createdAt: Date
    let cropURL: URL?
    let score: Double

    var promptSummary: String {
        let categoryText = category.isEmpty ? "fashion item" : category
        return "\(title) (\(categoryText))"
    }
}

/// A small, deterministic metadata embedding. It is deliberately computed on device and avoids
/// another paid embedding endpoint. Vision crops remain local until the bounded retrieval step
/// has chosen at most a few relevant pieces.
enum StylezamMetadataEmbedding {
    static let dimensions = 256

    static func vector(for text: String) -> [Float] {
        let terms = expandedTerms(in: text)
        guard !terms.isEmpty else { return Array(repeating: 0, count: dimensions) }
        var result = Array(repeating: Float.zero, count: dimensions)
        for term in terms {
            let hash = stableHash(term)
            let index = Int(hash % UInt64(dimensions))
            let sign: Float = (hash & (1 << 63)) == 0 ? 1 : -1
            result[index] += sign
        }
        let magnitude = sqrt(result.reduce(Float.zero) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return result }
        return result.map { $0 / magnitude }
    }

    static func postgresVector(for text: String) -> String {
        "[" + vector(for: text).map { String(format: "%.6f", $0) }.joined(separator: ",") + "]"
    }

    static func cosine(_ left: [Float], _ right: [Float]) -> Double {
        guard left.count == right.count else { return 0 }
        return Double(zip(left, right).reduce(Float.zero) { $0 + ($1.0 * $1.1) })
    }

    static func expandedTerms(in text: String) -> [String] {
        var terms = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        let synonyms: [String: [String]] = [
            "trousers": ["pants"], "pants": ["trousers"], "tee": ["shirt"],
            "sneakers": ["shoes"], "trainers": ["shoes", "sneakers"],
            "purse": ["bag"], "handbag": ["bag"], "coat": ["jacket"],
            "cheap": ["affordable", "price"], "cheaper": ["affordable", "price"],
            "match": ["outfit", "wear"], "style": ["outfit", "wear"],
        ]
        let baseTerms = terms
        for term in baseTerms {
            terms.append(contentsOf: synonyms[term] ?? [])
        }
        return terms
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { current, byte in
            (current ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

enum WardrobeRetrievalService {
    static func relevantItems(
        question: String,
        selectedScanID: UUID,
        selectedGarmentID: String,
        scans: [SavedScan],
        cropURL: (SavedGarment) -> URL?,
        limit: Int = 4
    ) -> [WardrobeContextItem] {
        let selected = scans.first(where: { $0.id == selectedScanID })?
            .items.first(where: { $0.id == selectedGarmentID })
        let selectedCategory = selected.map(searchableText(for:)) ?? ""
        let queryVector = StylezamMetadataEmbedding.vector(
            for: question + " " + selectedCategory
        )
        let now = Date()

        return scans.flatMap { scan in
            scan.items.compactMap { item -> WardrobeContextItem? in
                guard item.isPipelineEligible else { return nil }
                let text = searchableText(for: item)
                let semantic = StylezamMetadataEmbedding.cosine(
                    queryVector,
                    StylezamMetadataEmbedding.vector(for: text)
                )
                let sameCategory = selected.flatMap { selectedItem in
                    let lhs = selectedItem.category ?? selectedItem.localLabel
                    let rhs = item.category ?? item.localLabel
                    return lhs.caseInsensitiveCompare(rhs) == .orderedSame ? 0.22 : 0
                } ?? 0
                let isSelected = scan.id == selectedScanID && item.id == selectedGarmentID
                let ageDays = max(0, now.timeIntervalSince(scan.createdAt) / 86_400)
                let recency = max(0, 0.08 - min(0.08, ageDays / 4_000))
                return WardrobeContextItem(
                    scanID: scan.id,
                    garmentID: item.id,
                    title: item.title,
                    category: item.category ?? item.localLabel,
                    createdAt: scan.createdAt,
                    cropURL: cropURL(item),
                    score: semantic + sameCategory + recency + (isSelected ? 0.32 : 0)
                )
            }
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.createdAt > $1.createdAt
        }
        .prefix(max(1, min(limit, 6)))
        .map { $0 }
    }

    static func searchableText(for item: SavedGarment) -> String {
        ([item.title, item.localLabel, item.category, item.brand]
            .compactMap { $0 }
            + item.colors
            + item.materials
            + item.patterns
            + item.details
            + item.visibleText)
            .joined(separator: " ")
    }
}
