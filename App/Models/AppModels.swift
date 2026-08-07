import Foundation

enum AppTab: Hashable {
    case home
    case search
    case camera
    case library
    case settings
}

enum TryOnCategory: String, Codable, CaseIterable, Sendable {
    case clothes, bag, scarf, shoes, hat, ring, bracelet, earring, watch, necklace

    var title: String {
        switch self {
        case .earring: "Earrings"
        default: rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .clothes: "tshirt"
        case .bag: "handbag"
        case .scarf: "wind"
        case .shoes: "shoe"
        case .hat: "hat.widebrim"
        case .ring: "circle"
        case .bracelet: "circle.dashed"
        case .earring: "ear"
        case .watch: "applewatch"
        case .necklace: "scribble.variable"
        }
    }
    var requiresDetailPhoto: Bool {
        switch self {
        case .ring, .bracelet, .earring, .watch, .necklace: true
        default: false
        }
    }

    static func infer(from label: String) -> TryOnCategory {
        match(from: label) ?? .clothes
    }

    static func infer(category: String?, title: String) -> TryOnCategory {
        if let category, let match = match(from: "\(category) \(title)") { return match }
        return match(from: title) ?? .clothes
    }

    private static func match(from label: String) -> TryOnCategory? {
        let words = Set(
            label.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        func containsAny(_ candidates: Set<String>) -> Bool { !words.isDisjoint(with: candidates) }

        // Specific accessory evidence wins when broad marketplace taxonomies also say
        // "clothing" or "apparel" (for example, "Apparel > Pearl Necklace").
        if containsAny(["earring", "earrings", "stud", "studs", "hoop", "hoops"]) { return .earring }
        if containsAny(["bracelet", "bracelets", "bangle", "bangles", "cuff", "cuffs"]) { return .bracelet }
        if containsAny(["watch", "watches", "timepiece"]) { return .watch }
        if containsAny(["necklace", "necklaces", "pendant", "pendants", "chain", "chains", "choker", "chokers"]) { return .necklace }
        if containsAny(["ring", "rings"]) { return .ring }
        if containsAny(["bag", "handbag", "wallet", "purse", "backpack", "tote", "clutch", "satchel"]) { return .bag }
        if containsAny(["scarf", "shawl", "wrap", "stole"]) { return .scarf }
        if containsAny(["shoe", "shoes", "boot", "boots", "sneaker", "sneakers", "sandal", "sandals", "heel", "heels", "loafer", "loafers"]) { return .shoes }
        if containsAny(["hat", "headwear", "cap", "beanie", "beret", "fedora", "visor"]) { return .hat }
        if containsAny(["dress", "sweater", "jumper", "shirt", "blouse", "top", "tee", "jacket", "coat", "hoodie", "jean", "jeans", "pants", "trousers", "skirt", "shorts", "belt", "outfit", "clothing", "apparel", "cape", "cardigan", "vest", "suit"]) { return .clothes }
        return nil
    }
}

enum TryOnGarmentRegion: String, Codable, CaseIterable, Sendable {
    case upperBody
    case lowerBody
    case fullBody
    case outerwear
    case footwear
    case accessory
    case unknown

    var title: String {
        switch self {
        case .upperBody: "Upper body"
        case .lowerBody: "Lower body"
        case .fullBody: "Full body"
        case .outerwear: "Outerwear"
        case .footwear: "Footwear"
        case .accessory: "Accessory"
        case .unknown: "Automatic"
        }
    }

    var renderPriority: Int {
        switch self {
        case .fullBody: 0
        case .lowerBody: 10
        case .upperBody: 20
        case .outerwear: 30
        case .footwear: 40
        case .accessory: 50
        case .unknown: 60
        }
    }

    static func infer(category: TryOnCategory, title: String) -> TryOnGarmentRegion {
        guard category == .clothes else {
            return category == .shoes ? .footwear : .accessory
        }
        let words = Set(
            title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        func containsAny(_ values: Set<String>) -> Bool { !words.isDisjoint(with: values) }

        if containsAny(["dress", "jumpsuit", "romper", "outfit", "bodysuit", "gown"]) {
            return .fullBody
        }
        if containsAny(["pants", "trousers", "jeans", "jean", "skirt", "shorts", "leggings", "tights", "stockings"]) {
            return .lowerBody
        }
        if containsAny(["jacket", "coat", "blazer", "cape", "parka", "overcoat", "windbreaker"]) {
            return .outerwear
        }
        if containsAny(["shirt", "blouse", "top", "tee", "tshirt", "sweater", "cardigan", "vest", "hoodie", "sweatshirt"]) {
            return .upperBody
        }
        return .unknown
    }
}

enum TryOnPhotoContext: String, Codable, CaseIterable, Identifiable, Sendable {
    case outfit, handAndWrist, faceAndNeck

    var id: String { rawValue }
    var title: String {
        switch self {
        case .outfit: "Outfit"
        case .handAndWrist: "Hand / wrist"
        case .faceAndNeck: "Face / neck"
        }
    }
    var guidance: String {
        switch self {
        case .outfit: "One person, front-facing, with the intended clothing area visible"
        case .handAndWrist: "A clear hand or wrist close-up without occlusion"
        case .faceAndNeck: "A clear front-facing face, ears, and neckline"
        }
    }
    var renderCategories: [TryOnCategory] {
        switch self {
        case .outfit: [.clothes, .bag, .scarf, .shoes, .hat, .necklace]
        case .handAndWrist: [.ring, .bracelet, .watch]
        case .faceAndNeck: [.hat, .scarf, .earring, .necklace]
        }
    }

    var categories: [TryOnCategory] { renderCategories }
}

enum TryOnGender: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, female, male
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var isProviderValue: Bool { self != .automatic }
}

struct TryOnTrayItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var category: TryOnCategory
    var region: TryOnGarmentRegion
    var imageData: Data
    var referenceImageData: Data?
    var isSelected: Bool
    var sourceProduct: ProductResultDTO?
    var sourceWardrobeID: UUID?
    var contentDigest: String?
    var referenceContentDigest: String?

    /// The media that is valid to submit as this item's YouCam reference.
    /// Lower-body clothes require the separately retained source frame; the
    /// display crop is deliberately not a fallback for that provider contract.
    var youCamReferenceImageData: Data? {
        let candidate = region == .lowerBody ? referenceImageData : imageData
        guard let candidate, !candidate.isEmpty else { return nil }
        return candidate
    }

    var isYouCamReferenceReady: Bool {
        youCamReferenceImageData != nil
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: TryOnCategory,
        region: TryOnGarmentRegion? = nil,
        imageData: Data,
        referenceImageData: Data? = nil,
        isSelected: Bool = true,
        sourceProduct: ProductResultDTO? = nil,
        sourceWardrobeID: UUID? = nil,
        contentDigest: String? = nil,
        referenceContentDigest: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.region = region ?? .infer(category: category, title: title)
        self.imageData = imageData
        self.referenceImageData = referenceImageData
        self.isSelected = isSelected
        self.sourceProduct = sourceProduct
        self.sourceWardrobeID = sourceWardrobeID
        self.contentDigest = contentDigest
        self.referenceContentDigest = referenceContentDigest
    }
}

struct PendingGarmentSearch: Identifiable, Hashable, Sendable {
    let id: UUID
    let scanID: UUID
    let garmentID: String
    let startsImmediately: Bool

    init(
        id: UUID = UUID(),
        scanID: UUID,
        garmentID: String,
        startsImmediately: Bool
    ) {
        self.id = id
        self.scanID = scanID
        self.garmentID = garmentID
        self.startsImmediately = startsImmediately
    }
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
    let id: String
    let label: String
    let data: Data?
    let perceptualHash: UInt64?
    let featurePrintData: Data?
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
    /// Durable local-only signatures used to avoid saving the same physical piece again.
    var perceptualHash: UInt64? = nil
    var featurePrintData: Data? = nil

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

struct SavedWardrobeItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let savedAt: Date
    let imageFilename: String
    let title: String
    let category: TryOnCategory
    let sourceProduct: ProductResultDTO?
    let sourceScanID: UUID?
    let sourceGarmentID: String?
    let contentDigest: String?
    let garmentRegion: TryOnGarmentRegion?
    let tryOnReferenceFilename: String?
    let tryOnReferenceDigest: String?

    init(
        id: UUID = UUID(),
        savedAt: Date = .now,
        imageFilename: String,
        title: String,
        category: TryOnCategory,
        sourceProduct: ProductResultDTO? = nil,
        sourceScanID: UUID? = nil,
        sourceGarmentID: String? = nil,
        contentDigest: String? = nil,
        garmentRegion: TryOnGarmentRegion? = nil,
        tryOnReferenceFilename: String? = nil,
        tryOnReferenceDigest: String? = nil
    ) {
        self.id = id
        self.savedAt = savedAt
        self.imageFilename = imageFilename
        self.title = title
        self.category = category
        self.sourceProduct = sourceProduct
        self.sourceScanID = sourceScanID
        self.sourceGarmentID = sourceGarmentID
        self.contentDigest = contentDigest
        self.garmentRegion = garmentRegion
        self.tryOnReferenceFilename = tryOnReferenceFilename
        self.tryOnReferenceDigest = tryOnReferenceDigest
    }
}

struct TryOnRailEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { wardrobeItemID }
    let wardrobeItemID: UUID
    var isSelected: Bool
    var addedAt: Date
}

struct SavedTryOnPersonPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let imageFilename: String
    let context: TryOnPhotoContext
    let contentDigest: String
    var inferredGender: TryOnGender?
}

struct SavedTryOnItemSnapshot: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let category: TryOnCategory
    let garmentRegion: TryOnGarmentRegion
    let wasSelected: Bool
    let sourceProduct: ProductResultDTO?
    let contentDigest: String?
    let referenceContentDigest: String?

    init(
        id: UUID,
        title: String,
        category: TryOnCategory,
        garmentRegion: TryOnGarmentRegion,
        wasSelected: Bool,
        sourceProduct: ProductResultDTO? = nil,
        contentDigest: String? = nil,
        referenceContentDigest: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.garmentRegion = garmentRegion
        self.wasSelected = wasSelected
        self.sourceProduct = sourceProduct
        self.contentDigest = contentDigest
        self.referenceContentDigest = referenceContentDigest
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, garmentRegion, wasSelected, sourceProduct, contentDigest
        case referenceContentDigest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(TryOnCategory.self, forKey: .category)
        garmentRegion = try container.decode(TryOnGarmentRegion.self, forKey: .garmentRegion)
        wasSelected = try container.decode(Bool.self, forKey: .wasSelected)
        sourceProduct = try container.decodeIfPresent(ProductResultDTO.self, forKey: .sourceProduct)
        contentDigest = try container.decodeIfPresent(String.self, forKey: .contentDigest)
        referenceContentDigest = try container.decodeIfPresent(
            String.self,
            forKey: .referenceContentDigest
        )
    }
}

struct SavedTryOn: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: Date
    let imageFilename: String
    let product: ProductResultDTO?
    let title: String?
    let personPhotoID: UUID?
    let photoContext: TryOnPhotoContext?
    let gender: TryOnGender?
    let items: [SavedTryOnItemSnapshot]

    var displayTitle: String { title ?? product?.title ?? "Styled look" }

    init(
        id: String,
        createdAt: Date,
        imageFilename: String,
        product: ProductResultDTO? = nil,
        title: String? = nil,
        personPhotoID: UUID? = nil,
        photoContext: TryOnPhotoContext? = nil,
        gender: TryOnGender? = nil,
        items: [SavedTryOnItemSnapshot] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imageFilename = imageFilename
        self.product = product
        self.title = title
        self.personPhotoID = personPhotoID
        self.photoContext = photoContext
        self.gender = gender
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, imageFilename, product, title
        case personPhotoID, photoContext, gender, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        imageFilename = try container.decode(String.self, forKey: .imageFilename)
        product = try container.decodeIfPresent(ProductResultDTO.self, forKey: .product)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        personPhotoID = try container.decodeIfPresent(UUID.self, forKey: .personPhotoID)
        photoContext = try container.decodeIfPresent(TryOnPhotoContext.self, forKey: .photoContext)
        gender = try container.decodeIfPresent(TryOnGender.self, forKey: .gender)
        items = try container.decodeIfPresent([SavedTryOnItemSnapshot].self, forKey: .items) ?? []
    }
}

struct LibrarySnapshot: Codable, Sendable {
    var scans: [SavedScan] = []
    var captures: [SavedCapture] = []
    var searches: [SavedProductSearch] = []
    var chats: [StylezamChatThread] = []
    var products: [SavedProduct] = []
    var wardrobeItems: [SavedWardrobeItem] = []
    var tryOns: [SavedTryOn] = []
    var tryOnRail: [TryOnRailEntry] = []
    var tryOnPersonPhotos: [SavedTryOnPersonPhoto] = []
    var activeTryOnPhotoID: UUID?

    private enum CodingKeys: String, CodingKey {
        case scans
        case captures
        case searches
        case chats
        case products
        case wardrobeItems
        case tryOns
        case tryOnRail
        case tryOnPersonPhotos
        case activeTryOnPhotoID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scans = try container.decodeIfPresent([SavedScan].self, forKey: .scans) ?? []
        captures = try container.decodeIfPresent([SavedCapture].self, forKey: .captures) ?? []
        searches = try container.decodeIfPresent([SavedProductSearch].self, forKey: .searches) ?? []
        chats = try container.decodeIfPresent([StylezamChatThread].self, forKey: .chats) ?? []
        products = try container.decodeIfPresent([SavedProduct].self, forKey: .products) ?? []
        wardrobeItems = try container.decodeIfPresent([SavedWardrobeItem].self, forKey: .wardrobeItems) ?? []
        tryOns = try container.decodeIfPresent([SavedTryOn].self, forKey: .tryOns) ?? []
        tryOnRail = try container.decodeIfPresent([TryOnRailEntry].self, forKey: .tryOnRail) ?? []
        tryOnPersonPhotos = try container.decodeIfPresent([SavedTryOnPersonPhoto].self, forKey: .tryOnPersonPhotos) ?? []
        activeTryOnPhotoID = try container.decodeIfPresent(UUID.self, forKey: .activeTryOnPhotoID)
    }
}
