import Foundation

enum AppTab: Hashable {
    case home
    case search
    case looks
    case you
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

struct LibrarySnapshot: Codable, Sendable {
    var captures: [SavedCapture] = []
    var products: [SavedProduct] = []
}
