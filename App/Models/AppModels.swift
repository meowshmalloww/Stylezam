import Foundation

enum AppTab: Hashable {
    case home
    case search
    case camera
    case library
    case settings
}

enum CaptureOrigin: String, Codable, Sendable {
    case camera
    case photoLibrary
    case text
    case clipboard
    case shareExtension
    case screenCapture
}

enum CaptureMode: String, Codable, Sendable {
    case photo
    case live
    case screen
    case imported
}

enum GarmentDetectionMethod: String, Codable, Sendable {
    case coreML = "coreml"
    case foregroundInstance = "foreground-instance"
}

enum ScanLabelState: String, Codable, Sendable {
    case local
    case enriched
    case unavailable
}

struct GarmentCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let localLabel: String
    let confidence: Double
    let box: BoundingBoxDTO
    /// Reliable, unmasked pixels from the detector's bounding box.
    let boxCropData: Data?
    /// Experimental transparent segmentation output retained for diagnostics.
    let cropData: Data?
}

struct GarmentDetectionBatch: Hashable, Sendable {
    let method: GarmentDetectionMethod
    let candidates: [GarmentCandidate]
    let metrics: GarmentPipelineMetrics?
}

struct GarmentPipelineMetrics: Codable, Hashable, Sendable {
    let sourceWidth: Int
    let sourceHeight: Int
    let modelInputResolution: Int
    let modelLoadMilliseconds: Double
    let decodeMilliseconds: Double
    let inputPreparationMilliseconds: Double
    let inferenceMilliseconds: Double
    let outputDecodingMilliseconds: Double
    let cropEncodingMilliseconds: Double
    let totalMilliseconds: Double
    /// One full-frame prediction plus any bounded high-detail tile predictions.
    let inferencePassCount: Int?
    /// Approximate long-edge detector detail after tile projection. Each model
    /// invocation still uses the model's fixed tensor size.
    let effectiveDetectionResolution: Int?
    let inferenceStrategy: String?
    let processingBudgetMilliseconds: Double?
    let budgetLimited: Bool?
    let thermalState: String?
    let lowPowerMode: Bool?

    var sourceMegapixels: Double {
        Double(sourceWidth * sourceHeight) / 1_000_000
    }
}

enum LiveCaptureGuidance: String, Hashable, Sendable {
    case aimAtFashion
    case moveCloser
    case centerItem
    case moreLight
    case holdStill
    case ready

    var title: String {
        switch self {
        case .aimAtFashion: "Aim at a fashion item"
        case .moveCloser: "Move closer"
        case .centerItem: "Keep the whole item in frame"
        case .moreLight: "Find more light"
        case .holdStill: "Hold still"
        case .ready: "Good view"
        }
    }

    var symbol: String {
        switch self {
        case .aimAtFashion: "viewfinder"
        case .moveCloser: "arrow.up.left.and.arrow.down.right"
        case .centerItem: "rectangle.inset.filled"
        case .moreLight: "sun.max"
        case .holdStill: "hand.raised"
        case .ready: "checkmark"
        }
    }
}

struct LiveGarmentPreview: Hashable, Sendable {
    let candidates: [GarmentCandidate]
    let qualityScore: Double
    let guidance: LiveCaptureGuidance
}

struct GarmentFingerprintSource: Sendable {
    let label: String
    let data: Data
    let createdAt: Date
}

struct SavedGarment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let cropFilename: String?
    let localLabel: String
    let localConfidence: Double
    let box: BoundingBoxDTO
    var accepted: Bool
    var category: String?
    var displayName: String?
    var brand: String?
    var colors: [String]
    var materials: [String]
    var patterns: [String]
    var details: [String]
    var visibleText: [String]

    var title: String {
        displayName ?? localLabel
    }
}

struct SavedScan: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let imageFilename: String
    let origin: CaptureOrigin
    let mode: CaptureMode
    let detectionMethod: GarmentDetectionMethod
    let visionMetrics: GarmentPipelineMetrics?
    var labelState: ScanLabelState
    var items: [SavedGarment]
}

struct SearchInput: Sendable {
    var query: String?
    var imageData: Data?
    var origin: CaptureOrigin
    var selectedRegion: BoundingBoxDTO? = nil

    var isEmpty: Bool {
        imageData == nil && (query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

struct SavedCapture: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let imageFilename: String?
    let query: String?
    let origin: CaptureOrigin
    let searchID: String
}

struct SavedProduct: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let savedAt: Date
    let product: ProductResultDTO
}

struct SavedTryOn: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: Date
    let imageFilename: String
    let product: ProductResultDTO
}

struct LibrarySnapshot: Codable, Sendable {
    var scans: [SavedScan] = []
    var captures: [SavedCapture] = []
    var searches: [SavedProductSearch] = []
    var products: [SavedProduct] = []
    var tryOns: [SavedTryOn] = []

    private enum CodingKeys: String, CodingKey {
        case scans
        case captures
        case searches
        case products
        case tryOns
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scans = try container.decodeIfPresent([SavedScan].self, forKey: .scans) ?? []
        captures = try container.decodeIfPresent([SavedCapture].self, forKey: .captures) ?? []
        searches = try container.decodeIfPresent([SavedProductSearch].self, forKey: .searches) ?? []
        products = try container.decodeIfPresent([SavedProduct].self, forKey: .products) ?? []
        tryOns = try container.decodeIfPresent([SavedTryOn].self, forKey: .tryOns) ?? []
    }
}
