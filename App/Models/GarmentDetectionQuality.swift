import Foundation

enum GarmentReviewState: String, Codable, Sendable {
    case confirmed
    case rejected
}

enum GarmentDetectionCorrection: Sendable {
    case notFashion
    case fashion(category: TryOnCategory, label: String)
}

enum GarmentDetectionQualityPolicy {
    /// These broad silhouettes are where the Fashionpedia detector most often confuses
    /// bedding, cushions, and folded fabric with something wearable. Its raw sigmoid score is
    /// useful in Developer Inspector, but it is not a calibrated probability for end users.
    private static let highRiskLabels = [
        "bag", "wallet", "purse", "backpack", "jacket", "coat", "cape",
        "pants", "trouser", "jeans", "shorts", "skirt", "dress",
    ]

    static func needsReview(label: String, confidence: Double) -> Bool {
        let normalized = label.lowercased()
        // A raw 78% bag result is still ambiguous; strong second-opinion evidence can lift a
        // genuinely supported result above this gate without exposing an uncalibrated score.
        let threshold = highRiskLabels.contains(where: normalized.contains) ? 0.82 : 0.72
        return confidence < threshold
    }

    static func isPipelineEligible(_ garment: SavedGarment) -> Bool {
        guard garment.accepted, garment.reviewState != .rejected else { return false }
        if garment.reviewState == .confirmed { return true }
        return !needsReview(label: garment.localLabel, confidence: garment.localConfidence)
    }

    static func status(for garment: SavedGarment) -> String {
        switch garment.reviewState {
        case .confirmed:
            "Confirmed"
        case .rejected:
            "Not fashion"
        case nil where needsReview(
            label: garment.localLabel,
            confidence: garment.localConfidence
        ):
            "Needs confirmation"
        case nil:
            "Detected on device"
        }
    }

    static func liveLabel(label: String, confidence: Double) -> String {
        let cleaned = label
            .split(separator: ",")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized ?? "Fashion item"
        return needsReview(label: label, confidence: confidence)
            ? "Possible \(cleaned)"
            : cleaned
    }

    static func reviewReason(for garment: SavedGarment) -> String {
        let category = garment.localLabel
            .replacingOccurrences(of: ",", with: " or")
            .lowercased()
        return "This may be \(category), but the on-device result is not certain enough to search or try on yet. Confirm it with one tap."
    }
}

extension SavedGarment {
    var needsUserReview: Bool {
        accepted
            && reviewState == nil
            && GarmentDetectionQualityPolicy.needsReview(
                label: localLabel,
                confidence: localConfidence
            )
    }

    var isPipelineEligible: Bool {
        GarmentDetectionQualityPolicy.isPipelineEligible(self)
    }

    var userFacingDetectionStatus: String {
        GarmentDetectionQualityPolicy.status(for: self)
    }
}
