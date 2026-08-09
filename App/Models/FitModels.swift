import Foundation

// MARK: - Units

enum MeasurementDisplayUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case centimeters
    case inches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .centimeters: "cm"
        case .inches: "in"
        }
    }

    func displayValue(fromCm cm: Double) -> Double {
        switch self {
        case .centimeters: cm
        case .inches: cm / 2.54
        }
    }

    func cmValue(fromDisplay value: Double) -> Double {
        switch self {
        case .centimeters: value
        case .inches: value * 2.54
        }
    }

    func formatted(cm: Double) -> String {
        let value = displayValue(fromCm: cm)
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return "\(text) \(title)"
    }
}

// MARK: - Body measurements

/// The user's own body measurements. All values are stored in centimeters
/// and only ever kept on this device.
struct BodyMeasurements: Codable, Hashable, Sendable {
    var heightCm: Double?
    var chestCm: Double?
    var waistCm: Double?
    var hipsCm: Double?
    var shouldersCm: Double?
    var sleeveCm: Double?
    var inseamCm: Double?
    var updatedAt: Date?

    static let empty = BodyMeasurements()

    var hasAnyValue: Bool {
        [heightCm, chestCm, waistCm, hipsCm, shouldersCm, sleeveCm, inseamCm]
            .contains { $0 != nil }
    }

    /// Enough data to produce a meaningful recommendation for most garments.
    var hasCoreMeasurements: Bool {
        chestCm != nil || waistCm != nil || hipsCm != nil
    }

    func value(for dimension: GarmentDimension) -> Double? {
        switch dimension {
        case .chest: chestCm
        case .waist: waistCm
        case .hips: hipsCm
        case .shoulders: shouldersCm
        case .sleeve: sleeveCm
        case .inseam: inseamCm
        case .length: nil
        }
    }
}

// MARK: - Garment dimensions

enum GarmentDimension: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case chest
    case waist
    case hips
    case shoulders
    case length
    case sleeve
    case inseam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: "Chest / bust"
        case .waist: "Waist"
        case .hips: "Hips"
        case .shoulders: "Shoulders"
        case .length: "Length"
        case .sleeve: "Sleeve"
        case .inseam: "Inseam"
        }
    }

    var symbolName: String {
        switch self {
        case .chest: "figure.arms.open"
        case .waist: "circle.dashed"
        case .hips: "circle.circle"
        case .shoulders: "arrow.left.and.right"
        case .length: "arrow.up.and.down"
        case .sleeve: "hand.raised"
        case .inseam: "figure.walk"
        }
    }
}

// MARK: - Size chart

/// Per-size dimensions extracted from a merchant product page.
struct GarmentSizeChart: Codable, Hashable, Sendable {
    /// Whether the published numbers describe the garment itself or the body
    /// it is meant to fit. The distinction changes how ease is judged.
    enum Basis: String, Codable, Hashable, Sendable {
        case garment
        case body
        case unknown

        var explanation: String {
            switch self {
            case .garment: "The merchant lists garment measurements, taken flat on the piece itself."
            case .body: "The merchant lists body measurements each size is cut to fit."
            case .unknown: "The merchant did not state whether these are garment or body measurements."
            }
        }
    }

    let productID: String
    let sourceURL: URL
    let basis: Basis
    let sizes: [GarmentSizeSpec]
    let sourceNote: String?
    let fetchedAt: Date

    var dimensionsPresent: [GarmentDimension] {
        GarmentDimension.allCases.filter { dimension in
            sizes.contains { $0.measurements[dimension] != nil }
        }
    }
}

struct GarmentSizeSpec: Codable, Hashable, Identifiable, Sendable {
    let label: String
    /// Values in centimeters, keyed by dimension.
    let measurements: [GarmentDimension: Double]

    var id: String { label }
}

// MARK: - Fit assessment

enum FitRating: String, Codable, Hashable, Sendable, Comparable {
    case tooTight
    case snug
    case ideal
    case relaxed
    case oversized

    var title: String {
        switch self {
        case .tooTight: "Too tight"
        case .snug: "Snug"
        case .ideal: "Ideal"
        case .relaxed: "Relaxed"
        case .oversized: "Oversized"
        }
    }

    /// Score contribution used when ranking sizes.
    var score: Double {
        switch self {
        case .ideal: 1
        case .snug: 0.62
        case .relaxed: 0.68
        case .tooTight: 0.08
        case .oversized: 0.3
        }
    }

    private var order: Int {
        switch self {
        case .tooTight: 0
        case .snug: 1
        case .ideal: 2
        case .relaxed: 3
        case .oversized: 4
        }
    }

    static func < (lhs: FitRating, rhs: FitRating) -> Bool {
        lhs.order < rhs.order
    }
}

struct DimensionFit: Identifiable, Hashable, Sendable {
    let dimension: GarmentDimension
    let garmentValueCm: Double
    let bodyValueCm: Double?
    /// Garment minus body, in centimeters. Nil when there is nothing to compare.
    let easeCm: Double?
    /// Nil for purely informational rows (for example garment length when it
    /// cannot be judged against the body).
    let rating: FitRating?
    let note: String

    var id: GarmentDimension { dimension }
}

struct SizeFitAssessment: Identifiable, Hashable, Sendable {
    let sizeLabel: String
    let dimensionFits: [DimensionFit]
    /// 0...1 combined fit score across comparable dimensions.
    let score: Double
    /// Worst-offender based verdict for the size as a whole.
    let verdict: FitRating?
    let summary: String

    var id: String { sizeLabel }

    var confidencePercent: Int {
        Int((min(1, max(0, score)) * 100).rounded())
    }
}

struct SizeRecommendation: Hashable, Sendable {
    let assessments: [SizeFitAssessment]
    let recommendedSizeLabel: String?
    let note: String?

    func assessment(for label: String) -> SizeFitAssessment? {
        assessments.first { $0.sizeLabel == label }
    }
}

// MARK: - Fetch state

/// UI-facing state for one product's size-chart lookup.
enum SizeChartState: Hashable, Sendable {
    case loading
    case loaded(GarmentSizeChart)
    /// The page was read successfully but publishes no per-size dimensions.
    case notPublished(String)
    /// The lookup itself failed (network, provider, budget).
    case failed(String)
}

// MARK: - Garment class (drives ease expectations)

enum GarmentFitClass: String, Codable, Hashable, Sendable {
    case top
    case outerwear
    case dress
    case bottoms
    case skirt
    case unknown

    static func classify(category: String?, title: String) -> GarmentFitClass {
        let haystack = "\(category ?? "") \(title)".lowercased()
        let outerwearTerms = ["jacket", "coat", "parka", "blazer", "puffer", "windbreaker", "anorak", "overcoat", "trench", "bomber", "outerwear"]
        let dressTerms = ["dress", "gown", "jumpsuit", "romper", "overall"]
        let skirtTerms = ["skirt", "skort"]
        let bottomsTerms = ["jean", "pant", "trouser", "chino", "legging", "short", "jogger", "sweatpant", "cargo", "denim", "bottom"]
        let topTerms = ["shirt", "tee", "t-shirt", "top", "blouse", "sweater", "hoodie", "sweatshirt", "cardigan", "polo", "tank", "knit", "pullover", "vest"]

        if outerwearTerms.contains(where: haystack.contains) { return .outerwear }
        if dressTerms.contains(where: haystack.contains) { return .dress }
        if skirtTerms.contains(where: haystack.contains) { return .skirt }
        if bottomsTerms.contains(where: haystack.contains) { return .bottoms }
        if topTerms.contains(where: haystack.contains) { return .top }
        return .unknown
    }
}
