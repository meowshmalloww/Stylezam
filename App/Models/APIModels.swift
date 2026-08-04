import Foundation

enum JobStatus: String, Codable, Sendable {
    case queued
    case processing
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

enum SearchPhase: String, Codable, Sendable {
    case queued
    case understanding
    case retrieving
    case reranking
    case completed
    case failed

    var title: String {
        switch self {
        case .queued: "Waiting to start"
        case .understanding: "Understanding the item"
        case .retrieving: "Checking product sources"
        case .reranking: "Comparing the closest matches"
        case .completed: "Matches ready"
        case .failed: "Search stopped"
        }
    }
}

enum TryOnPhase: String, Codable, Sendable {
    case queued
    case uploading
    case generating
    case saving
    case completed
    case failed

    var title: String {
        switch self {
        case .queued: "Waiting to start"
        case .uploading: "Preparing your photo"
        case .generating: "Creating your try-on"
        case .saving: "Saving the result"
        case .completed: "Try-on ready"
        case .failed: "Try-on stopped"
        }
    }
}

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

struct GarmentInputMetadataDTO: Codable, Hashable, Sendable {
    let itemID: String
    let localLabel: String
    let localConfidence: Double
    let box: BoundingBoxDTO
}

struct GarmentLabelDTO: Codable, Hashable, Sendable {
    let itemID: String
    let accepted: Bool
    let category: String?
    let displayName: String?
    let brand: String?
    let colors: [String]
    let materials: [String]
    let patterns: [String]
    let details: [String]
    let visibleText: [String]
}

struct GarmentAnalysisDTO: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let provider: String
    let model: String
    let items: [GarmentLabelDTO]
    let createdAt: Date
}

struct ModelPackFileDTO: Codable, Hashable, Sendable {
    let path: String
    let url: URL
    let sha256: String
    let bytes: Int
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

struct DetectedItemDTO: Codable, Hashable, Sendable {
    let label: String
    let confidence: Double
    let box: BoundingBoxDTO
    let cropURL: URL?
}

struct VisualAttributesDTO: Codable, Hashable, Sendable {
    let category: String?
    let subcategory: String?
    let brand: String?
    let colors: [String]
    let materials: [String]
    let patterns: [String]
    let details: [String]
    let visibleText: [String]
    let searchQuery: String?
    let detectedItems: [DetectedItemDTO]
}

struct MoneyDTO: Codable, Hashable, Sendable {
    let amount: Double
    let currency: String
    let display: String?

    var formatted: String {
        display ?? amount.formatted(.currency(code: currency))
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
        Int((score * 100).rounded())
    }
}

struct SearchJobDTO: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let status: JobStatus
    let phase: SearchPhase
    let progress: Double
    let query: String?
    let inputImageURL: URL?
    let selectedRegion: BoundingBoxDTO?
    let analysis: VisualAttributesDTO?
    let resultCount: Int
    let providerWarnings: [String]
    let errorCode: String?
    let errorMessage: String?
    let createdAt: Date
    let updatedAt: Date
}

struct SearchResultsPageDTO: Codable, Sendable {
    let searchID: String
    let results: [ProductResultDTO]
    let total: Int
}

struct TryOnJobDTO: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let status: JobStatus
    let phase: TryOnPhase
    let progress: Double
    let personImageURL: URL
    let productImageURL: URL
    let garmentCategory: String
    let resultImageURL: URL?
    let providerTaskID: String?
    let errorCode: String?
    let errorMessage: String?
    let createdAt: Date
    let updatedAt: Date
}

struct ProviderCapabilityDTO: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let capability: String
    let configured: Bool
    let monthlyLimitNote: String?
    let detail: String?
}

struct CapabilitiesDTO: Codable, Hashable, Sendable {
    let textSearch: Bool
    let imageSearch: Bool
    let imageUnderstanding: Bool
    let garmentSegmentation: Bool
    let visualReranking: Bool
    let virtualTryOn: Bool
    let publicImageIngress: Bool
    let garmentLabeling: Bool
    let modelPackAvailable: Bool
    let providers: [ProviderCapabilityDTO]
}

struct HealthDTO: Codable, Sendable {
    let status: String
    let version: String
    let environment: String
    let now: Date
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
