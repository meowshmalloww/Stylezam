import Foundation

enum AppTab: Hashable {
    case home
    case search
    case camera
    case library
    case settings
}

enum CaptureLaunchMode: Hashable, Sendable {
    case chooser
    case camera
    case photos
}

enum CaptureOrigin: String, Codable, Sendable {
    case camera
    case photoLibrary
    case text
    case clipboard
    case shareExtension
    case screenCapture
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
    var captures: [SavedCapture] = []
    var products: [SavedProduct] = []
    var tryOns: [SavedTryOn] = []

    private enum CodingKeys: String, CodingKey {
        case captures
        case products
        case tryOns
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captures = try container.decodeIfPresent([SavedCapture].self, forKey: .captures) ?? []
        products = try container.decodeIfPresent([SavedProduct].self, forKey: .products) ?? []
        tryOns = try container.decodeIfPresent([SavedTryOn].self, forKey: .tryOns) ?? []
    }
}
