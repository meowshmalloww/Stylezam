import Foundation

enum MatchTier: String, Codable, Sendable, CaseIterable {
    case exact
    case likely
    case similar
    case inspired

    var label: String {
        switch self {
        case .exact: "Exact evidence"
        case .likely: "Likely match"
        case .similar: "Similar"
        case .inspired: "Inspired by"
        }
    }
}

struct BoundingBoxDTO: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct ModelPackFileDTO: Codable, Hashable, Sendable {
    let path: String
    let url: URL?
    let sha256: String
    let bytes: Int

    private enum CodingKeys: String, CodingKey {
        case path
        case url
        case sha256
        case bytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        sha256 = try container.decode(String.self, forKey: .sha256)
        bytes = try container.decode(Int.self, forKey: .bytes)

        let rawURL = try container.decodeIfPresent(String.self, forKey: .url)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        url = rawURL.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(url?.absoluteString, forKey: .url)
        try container.encode(sha256, forKey: .sha256)
        try container.encode(bytes, forKey: .bytes)
    }
}

struct ModelPackManifestDTO: Codable, Hashable, Sendable {
    let modelID: String
    let version: String
    let displayName: String
    let totalBytes: Int
    let minimumIos: String
    let inputName: String
    let inputResolution: Int
    let boxOutputName: String
    let logitOutputName: String
    let maskOutputName: String
    let classNames: [String]
    let licenseName: String
    let licenseURL: URL
    let sourceURL: URL
    let sourceRevision: String
    let checkpointSHA256: String
    let datasetName: String
    let datasetLicenseName: String
    let datasetLicenseURL: URL
    let attribution: String
    let files: [ModelPackFileDTO]
}

struct MoneyDTO: Codable, Hashable, Sendable {
    let amount: Double
    let currency: String
    let display: String?

    var formatted: String {
        amount.formatted(
            .currency(code: currency.uppercased())
                .precision(.fractionLength(amount.rounded() == amount ? 0 : 2))
        )
    }
}

struct MerchantOfferDTO: Codable, Hashable, Sendable {
    let merchant: String
    let url: URL
    let price: MoneyDTO?
    let shipping: String?
    let condition: String?
}

struct ProductResultDTO: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let searchID: String
    let provider: String
    let providerResultID: String?
    let title: String
    let brand: String?
    let category: String?
    let color: String?
    let imageURL: URL?
    let productURL: URL
    let merchant: String
    let price: MoneyDTO?
    let matchTier: MatchTier
    let score: Double
    let rating: Double?
    let reviewCount: Int?
    let attributes: [String: JSONValue]
    let offers: [MerchantOfferDTO]

    var confidencePercent: Int {
        Int((min(1, max(0, score)) * 100).rounded())
    }
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
