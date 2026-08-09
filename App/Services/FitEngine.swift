import Foundation

/// Deterministic size-fit scoring. Compares the user's body measurements to a
/// merchant size chart and rates every published size so the user can see how
/// each one would fit before buying. No AI is involved here: given the same
/// chart and measurements the verdicts are always reproducible.
enum FitEngine {
    /// Ideal ease (garment measurement minus body measurement, cm) per
    /// dimension for a garment-measurement chart.
    private static func idealEaseRange(
        dimension: GarmentDimension,
        fitClass: GarmentFitClass
    ) -> ClosedRange<Double>? {
        switch dimension {
        case .chest:
            switch fitClass {
            case .outerwear: return 8...20
            case .dress: return 2...10
            default: return 4...14
            }
        case .waist:
            switch fitClass {
            case .bottoms, .skirt: return 0...4
            case .dress: return 2...9
            default: return 6...22
            }
        case .hips:
            switch fitClass {
            case .bottoms, .skirt: return 2...9
            case .dress: return 2...11
            default: return 4...18
            }
        case .shoulders:
            return fitClass == .outerwear ? 0...5 : (-1)...3
        case .sleeve:
            return (-1)...4
        case .inseam:
            return (-3)...3
        case .length:
            return nil
        }
    }

    /// Body-measurement charts state the body each size fits, so the ideal
    /// delta hovers around zero regardless of garment class.
    private static let bodyBasisTolerance: ClosedRange<Double> = (-2)...3

    private static func weight(for dimension: GarmentDimension, fitClass: GarmentFitClass) -> Double {
        switch dimension {
        case .chest: fitClass == .bottoms || fitClass == .skirt ? 1 : 3
        case .waist: fitClass == .bottoms || fitClass == .skirt || fitClass == .dress ? 3 : 1.5
        case .hips: fitClass == .bottoms || fitClass == .skirt ? 3 : 1.5
        case .shoulders: 2
        case .sleeve: 1.5
        case .inseam: 2
        case .length: 0
        }
    }

    // MARK: - Public entry point

    static func recommendation(
        chart: GarmentSizeChart,
        body: BodyMeasurements,
        category: String?,
        title: String
    ) -> SizeRecommendation {
        let fitClass = GarmentFitClass.classify(category: category, title: title)
        let assessments = chart.sizes.map {
            assess(size: $0, chart: chart, body: body, fitClass: fitClass)
        }

        let comparable = assessments.filter { $0.verdict != nil }
        let best = comparable.max { left, right in
            if left.score != right.score { return left.score < right.score }
            // Prefer the smaller size on an exact tie to avoid drowning the user.
            return chartIndex(of: right.sizeLabel, in: chart) < chartIndex(of: left.sizeLabel, in: chart)
        }

        var note: String?
        if comparable.isEmpty {
            note = "Add your measurements to see a personal recommendation for each size."
        } else if let best, best.score < 0.45 {
            note = "None of the published sizes measure close to your numbers. Double-check the merchant's fit guidance before buying."
        } else if let best {
            let runnerUp = comparable
                .filter { $0.sizeLabel != best.sizeLabel }
                .max { $0.score < $1.score }
            if let runnerUp, best.score - runnerUp.score < 0.08 {
                note = "You are between \(best.sizeLabel) and \(runnerUp.sizeLabel). Compare both breakdowns below and pick the trade-off you prefer."
            }
        }

        let recommended = (best?.score ?? 0) >= 0.45 ? best?.sizeLabel : nil
        return SizeRecommendation(
            assessments: assessments,
            recommendedSizeLabel: recommended,
            note: note
        )
    }

    // MARK: - Per-size assessment

    private static func assess(
        size: GarmentSizeSpec,
        chart: GarmentSizeChart,
        body: BodyMeasurements,
        fitClass: GarmentFitClass
    ) -> SizeFitAssessment {
        var fits: [DimensionFit] = []

        for dimension in GarmentDimension.allCases {
            guard let garmentValue = size.measurements[dimension] else { continue }
            if dimension == .length {
                fits.append(lengthFit(garmentValueCm: garmentValue, body: body, fitClass: fitClass))
                continue
            }
            fits.append(
                dimensionFit(
                    dimension: dimension,
                    garmentValueCm: garmentValue,
                    body: body,
                    basis: chart.basis,
                    fitClass: fitClass
                )
            )
        }

        var weightedScore: Double = 0
        var totalWeight: Double = 0
        var worst: (rating: FitRating, dimension: GarmentDimension)?
        for fit in fits {
            guard let rating = fit.rating else { continue }
            let dimensionWeight = weight(for: fit.dimension, fitClass: fitClass)
            weightedScore += rating.score * dimensionWeight
            totalWeight += dimensionWeight
            if worst == nil || rating.score < worst!.rating.score {
                worst = (rating, fit.dimension)
            }
        }

        let score = totalWeight > 0 ? weightedScore / totalWeight : 0
        let verdict = totalWeight > 0 ? verdictRating(fits: fits) : nil
        return SizeFitAssessment(
            sizeLabel: size.label,
            dimensionFits: fits,
            score: score,
            verdict: verdict,
            summary: summary(sizeLabel: size.label, fits: fits, verdict: verdict)
        )
    }

    private static func dimensionFit(
        dimension: GarmentDimension,
        garmentValueCm: Double,
        body: BodyMeasurements,
        basis: GarmentSizeChart.Basis,
        fitClass: GarmentFitClass
    ) -> DimensionFit {
        guard let bodyValue = body.value(for: dimension) else {
            return DimensionFit(
                dimension: dimension,
                garmentValueCm: garmentValueCm,
                bodyValueCm: nil,
                easeCm: nil,
                rating: nil,
                note: "Add your \(dimension.title.lowercased()) measurement to compare."
            )
        }

        let ease = garmentValueCm - bodyValue
        let ideal: ClosedRange<Double>
        switch basis {
        case .garment:
            guard let range = idealEaseRange(dimension: dimension, fitClass: fitClass) else {
                return DimensionFit(
                    dimension: dimension,
                    garmentValueCm: garmentValueCm,
                    bodyValueCm: bodyValue,
                    easeCm: ease,
                    rating: nil,
                    note: ""
                )
            }
            ideal = range
        case .body, .unknown:
            ideal = bodyBasisTolerance
        }

        let rating = rating(ease: ease, ideal: ideal)
        return DimensionFit(
            dimension: dimension,
            garmentValueCm: garmentValueCm,
            bodyValueCm: bodyValue,
            easeCm: ease,
            rating: rating,
            note: easeNote(dimension: dimension, ease: ease, rating: rating, basis: basis)
        )
    }

    private static func rating(ease: Double, ideal: ClosedRange<Double>) -> FitRating {
        if ease < ideal.lowerBound - 4 { return .tooTight }
        if ease < ideal.lowerBound { return .snug }
        if ease <= ideal.upperBound { return .ideal }
        if ease <= ideal.upperBound + 6 { return .relaxed }
        return .oversized
    }

    private static func easeNote(
        dimension: GarmentDimension,
        ease: Double,
        rating: FitRating,
        basis: GarmentSizeChart.Basis
    ) -> String {
        let magnitude = abs(ease)
        let rounded = (magnitude * 10).rounded() / 10
        let amount = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        let comparison = basis == .garment ? "than your body" : "than this size is cut for"
        switch rating {
        case .tooTight:
            return ease < 0
                ? "\(amount) cm smaller \(comparison) — expect real pressure here."
                : "Only \(amount) cm of room — expect real pressure here."
        case .snug:
            return "Close to your measurement (\(ease >= 0 ? "+" : "−")\(amount) cm). Wears fitted."
        case .ideal:
            return "\(ease >= 0 ? "+" : "−")\(amount) cm of room. Comfortable, true-to-intent fit."
        case .relaxed:
            return "+\(amount) cm of room. Noticeably easy through the \(shortName(dimension))."
        case .oversized:
            return "+\(amount) cm of room. Will read oversized on you."
        }
    }

    private static func shortName(_ dimension: GarmentDimension) -> String {
        switch dimension {
        case .chest: "chest"
        case .waist: "waist"
        case .hips: "hips"
        case .shoulders: "shoulders"
        case .length: "length"
        case .sleeve: "sleeve"
        case .inseam: "leg"
        }
    }

    // MARK: - Length

    /// Garment length cannot be judged tight or loose; instead Stylezam
    /// estimates where the hem lands using standard body proportions.
    private static func lengthFit(
        garmentValueCm: Double,
        body: BodyMeasurements,
        fitClass: GarmentFitClass
    ) -> DimensionFit {
        guard let height = body.heightCm, height > 0 else {
            return DimensionFit(
                dimension: .length,
                garmentValueCm: garmentValueCm,
                bodyValueCm: nil,
                easeCm: nil,
                rating: nil,
                note: "Add your height to estimate where the hem lands."
            )
        }

        let note: String
        switch fitClass {
        case .bottoms:
            // Outseam measured from the natural waist (~62% of height).
            let hemFromFloor = height * 0.62 - garmentValueCm
            note = bottomsHemNote(hemFromFloor: hemFromFloor, height: height)
        case .skirt:
            let hemFromFloor = height * 0.62 - garmentValueCm
            note = lowerHemZoneNote(hemFromFloor: hemFromFloor, height: height)
        default:
            // Tops, dresses, outerwear hang from the shoulder (~82% of height).
            let hemFromFloor = height * 0.818 - garmentValueCm
            note = lowerHemZoneNote(hemFromFloor: hemFromFloor, height: height)
        }

        return DimensionFit(
            dimension: .length,
            garmentValueCm: garmentValueCm,
            bodyValueCm: nil,
            easeCm: nil,
            rating: nil,
            note: note
        )
    }

    private static func lowerHemZoneNote(hemFromFloor: Double, height: Double) -> String {
        let hip = height * 0.53
        let midThigh = height * 0.40
        let knee = height * 0.285
        let midCalf = height * 0.17
        let ankle = height * 0.055

        if hemFromFloor > hip + 6 { return "On you, the hem lands above the hip — a cropped length." }
        if hemFromFloor > midThigh { return "On you, the hem lands around the hip." }
        if hemFromFloor > knee + 4 { return "On you, the hem lands at the mid-thigh." }
        if hemFromFloor > midCalf { return "On you, the hem lands around the knee." }
        if hemFromFloor > ankle { return "On you, the hem lands at the mid-calf — a midi length." }
        return "On you, the hem reaches the ankle — a full length."
    }

    private static func bottomsHemNote(hemFromFloor: Double, height: Double) -> String {
        let knee = height * 0.285
        let midCalf = height * 0.17
        let ankle = height * 0.055

        if hemFromFloor > knee { return "On you, these end above the knee — a short length." }
        if hemFromFloor > midCalf { return "On you, these end below the knee — a cropped length." }
        if hemFromFloor > ankle + 3 { return "On you, these end above the ankle — a cropped or tapered length." }
        if hemFromFloor > -2 { return "On you, these end right at the ankle — a standard full length." }
        return "On you, these run long and may stack or need hemming."
    }

    // MARK: - Summaries

    private static func verdictRating(fits: [DimensionFit]) -> FitRating? {
        let ratings = fits.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        if let worst = ratings.min(by: { $0.score < $1.score }), worst.score <= FitRating.oversized.score {
            // A single very poor dimension defines the wearing experience.
            if worst == .tooTight || worst == .oversized { return worst }
        }
        if ratings.allSatisfy({ $0 == .ideal }) { return .ideal }
        // Otherwise report the most common non-ideal tendency.
        let nonIdeal = ratings.filter { $0 != .ideal }
        guard !nonIdeal.isEmpty else { return .ideal }
        let counts = Dictionary(grouping: nonIdeal, by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? .ideal
    }

    private static func summary(
        sizeLabel: String,
        fits: [DimensionFit],
        verdict: FitRating?
    ) -> String {
        let rated = fits.filter { $0.rating != nil }
        guard !rated.isEmpty else {
            return "Add your measurements to see how size \(sizeLabel) fits you."
        }

        let ideal = rated.filter { $0.rating == .ideal }
        if ideal.count == rated.count {
            return "Size \(sizeLabel) measures ideal in every dimension Stylezam could compare."
        }

        var phrases: [String] = []
        if !ideal.isEmpty {
            phrases.append(list(ideal.map { shortName($0.dimension) }) + " " + (ideal.count == 1 ? "is" : "are") + " ideal")
        }
        for rating in [FitRating.tooTight, .snug, .relaxed, .oversized] {
            let matching = rated.filter { $0.rating == rating }
            guard !matching.isEmpty else { continue }
            let names = list(matching.map { shortName($0.dimension) })
            let verb = matching.count == 1 ? "runs" : "run"
            switch rating {
            case .tooTight: phrases.append("\(names) \(verb) too tight")
            case .snug: phrases.append("\(names) \(verb) snug")
            case .relaxed: phrases.append("\(names) \(verb) relaxed")
            case .oversized: phrases.append("\(names) \(verb) oversized")
            case .ideal: break
            }
        }

        let joined = phrases.joined(separator: "; ")
        return "In size \(sizeLabel), \(joined)."
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
    }

    private static func chartIndex(of label: String, in chart: GarmentSizeChart) -> Int {
        chart.sizes.firstIndex { $0.label == label } ?? Int.max
    }
}
