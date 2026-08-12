import CoreGraphics
import Foundation
import UIKit
@preconcurrency import Vision

struct GarmentVisualFingerprint: Hashable, Sendable {
    let perceptualHash: UInt64?
    let featurePrintData: Data?
}

struct NovelGarmentCandidate: Sendable {
    let candidate: GarmentCandidate
    let fingerprint: GarmentVisualFingerprint
}

/// Durable, on-device repeat protection shared by Live camera and Live Screen.
///
/// The Library persists both a tiny dHash and Apple's Vision feature print for every accepted
/// crop. The dHash catches pixel-near repeats cheaply; the feature print handles modest scale,
/// crop, and viewpoint changes. No source image or signature leaves the phone.
actor GarmentDuplicateGuard {
    private struct FeatureVector: Codable, Sendable {
        enum Source: String, Codable, Sendable {
            case vision
            case localGrid
        }

        enum ElementKind: String, Codable, Sendable {
            case float
            case double
        }

        let data: Data
        let elementCount: Int
        let elementKind: ElementKind
        let source: Source
    }

    private struct FeatureSignature: Codable, Sendable {
        let vision: FeatureVector?
        let localGrid: FeatureVector?
    }

    private struct Entry {
        let family: String
        let perceptualHash: UInt64?
        let featurePrint: FeatureSignature?
    }

    private var entries: [Entry] = []
    private var seededKeys: Set<String> = []
    private let maximumEntries = 1_200
    private let exactHashDistance = 7
    private let supportingHashDistance = 14
    private let strongFeatureDistance = 8.5
    private let supportedFeatureDistance = 12.0

    func novelCandidates(
        _ candidates: [GarmentCandidate],
        history: [GarmentFingerprintSource]
    ) async -> [NovelGarmentCandidate] {
        await seed(history)

        var accepted: [NovelGarmentCandidate] = []
        for candidate in candidates {
            // Prefer the actual foreground artwork. This stops nearby clothing and app chrome
            // from making two otherwise identical garments look unrelated to the repeat guard.
            guard let crop = candidate.cropData ?? candidate.boxCropData else {
                accepted.append(
                    NovelGarmentCandidate(
                        candidate: candidate,
                        fingerprint: GarmentVisualFingerprint(
                            perceptualHash: nil,
                            featurePrintData: nil
                        )
                    )
                )
                continue
            }

            let hash = Self.differenceHash(crop)
            let feature = await Self.makeFeatureSignature(crop)
            let family = Self.canonicalFamily(candidate.localLabel)
            let duplicate = entries.contains { entry in
                guard entry.family == family else { return false }
                return Self.matches(
                    hash: hash,
                    feature: feature,
                    existing: entry,
                    exactHashDistance: exactHashDistance,
                    supportingHashDistance: supportingHashDistance,
                    strongFeatureDistance: strongFeatureDistance,
                    supportedFeatureDistance: supportedFeatureDistance
                )
            }
            guard !duplicate else { continue }

            let featureData = feature.flatMap(Self.archiveFeaturePrint)
            accepted.append(
                NovelGarmentCandidate(
                    candidate: candidate,
                    fingerprint: GarmentVisualFingerprint(
                        perceptualHash: hash,
                        featurePrintData: featureData
                    )
                )
            )
            entries.append(
                Entry(
                    family: family,
                    perceptualHash: hash,
                    featurePrint: feature
                )
            )
        }

        trimEntries()
        return accepted
    }

    /// Deleting a Library entry deliberately lets the user forget it. Rebuild from the remaining
    /// persisted crops on the next capture instead of retaining a hidden in-memory signature.
    func reset() {
        entries = []
        seededKeys = []
    }

    private func seed(_ history: [GarmentFingerprintSource]) async {
        for source in history {
            guard seededKeys.insert(source.id).inserted else { continue }
            let feature: FeatureSignature?
            if let data = source.featurePrintData,
               let decoded = Self.unarchiveFeaturePrint(data)
            {
                feature = decoded
            } else if let crop = source.data {
                // Legacy Library items receive the inexpensive scale-normalized color grid.
                // Do not run hundreds of Vision requests during the first capture after upgrade.
                feature = FeatureSignature(
                    vision: nil,
                    localGrid: Self.fallbackFeatureVector(crop)
                )
            } else {
                feature = nil
            }
            let hash = source.perceptualHash ?? source.data.flatMap(Self.differenceHash)
            guard hash != nil || feature != nil else { continue }
            entries.append(
                Entry(
                    family: Self.canonicalFamily(source.label),
                    perceptualHash: hash,
                    featurePrint: feature
                )
            )
        }
        trimEntries()
    }

    private func trimEntries() {
        if entries.count > maximumEntries {
            entries = Array(entries.suffix(maximumEntries))
        }
    }

    private nonisolated static func matches(
        hash: UInt64?,
        feature: FeatureSignature?,
        existing: Entry,
        exactHashDistance: Int,
        supportingHashDistance: Int,
        strongFeatureDistance: Double,
        supportedFeatureDistance: Double
    ) -> Bool {
        let hashDistance = hash.flatMap { incoming in
            existing.perceptualHash.map { (incoming ^ $0).nonzeroBitCount }
        }
        if let hashDistance, hashDistance <= exactHashDistance {
            return true
        }

        guard let feature, let existingFeature = existing.featurePrint else { return false }
        let featureDistance: Double?
        if let incomingVision = feature.vision,
           let savedVision = existingFeature.vision
        {
            featureDistance = vectorDistance(incomingVision, savedVision)
        } else if let incomingGrid = feature.localGrid,
                  let savedGrid = existingFeature.localGrid
        {
            featureDistance = vectorDistance(incomingGrid, savedGrid)
        } else {
            featureDistance = nil
        }
        guard let featureDistance else { return false }
        if featureDistance <= strongFeatureDistance {
            return true
        }
        return featureDistance <= supportedFeatureDistance
            && (hashDistance ?? .max) <= supportingHashDistance
    }

    private nonisolated static func canonicalFamily(_ value: String) -> String {
        let normalized = value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let groups: [(String, [String])] = [
            ("outerwear", ["jacket", "coat", "blazer", "cardigan", "cape", "vest"]),
            ("top", ["shirt", "blouse", "top", "tee", "sweater", "hoodie", "jumper"]),
            ("bottom", ["pants", "trousers", "jeans", "shorts", "skirt"]),
            ("dress", ["dress", "gown", "jumpsuit"]),
            ("shoe", ["shoe", "boot", "sneaker", "sandal", "heel", "loafer"]),
            ("bag", ["bag", "purse", "backpack", "tote", "clutch", "satchel", "wallet"]),
            ("headwear", ["hat", "cap", "beanie", "beret", "fedora", "visor"]),
            ("watch", ["watch", "timepiece"]),
            ("ring", ["ring"]),
            ("bracelet", ["bracelet", "bangle", "cuff"]),
            ("earring", ["earring", "stud", "hoop"]),
            ("necklace", ["necklace", "pendant", "chain", "choker"]),
            ("scarf", ["scarf", "shawl", "stole"]),
        ]
        for (family, words) in groups where words.contains(where: normalized.contains) {
            return family
        }
        return normalized.replacingOccurrences(of: " ", with: "")
    }

    private nonisolated static func makeFeatureSignature(
        _ data: Data
    ) async -> FeatureSignature? {
        let localGrid = fallbackFeatureVector(data)
        do {
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(data: data)
            try handler.perform([request])
            guard let legacyObservation = request.results?.first else { return nil }
            let observation = FeaturePrintObservation(legacyObservation)
            let elementKind: FeatureVector.ElementKind
            switch observation.elementType {
            case .float: elementKind = .float
            case .double: elementKind = .double
            @unknown default: return nil
            }
            return FeatureSignature(
                vision: FeatureVector(
                    data: observation.data,
                    elementCount: observation.elementCount,
                    elementKind: elementKind,
                    source: .vision
                ),
                localGrid: localGrid
            )
        } catch {
            // Vision feature prints can be temporarily unavailable under simulator, thermal, or
            // memory pressure. A small RGB grid remains a durable on-device fallback instead of
            // silently weakening repeat protection to a single monochrome hash.
            return localGrid.map { FeatureSignature(vision: nil, localGrid: $0) }
        }
    }

    private nonisolated static func archiveFeaturePrint(
        _ feature: FeatureSignature
    ) -> Data? {
        do {
            return try JSONEncoder().encode(feature)
        } catch {
            return nil
        }
    }

    private nonisolated static func unarchiveFeaturePrint(
        _ data: Data
    ) -> FeatureSignature? {
        try? JSONDecoder().decode(FeatureSignature.self, from: data)
    }

    private nonisolated static func vectorDistance(
        _ lhs: FeatureVector,
        _ rhs: FeatureVector
    ) -> Double? {
        guard lhs.source == rhs.source,
              lhs.elementKind == rhs.elementKind,
              lhs.elementCount == rhs.elementCount,
              lhs.data.count == rhs.data.count
        else { return nil }

        switch lhs.elementKind {
        case .float:
            return lhs.data.withUnsafeBytes { leftRaw in
                rhs.data.withUnsafeBytes { rightRaw in
                    let left = leftRaw.bindMemory(to: Float.self)
                    let right = rightRaw.bindMemory(to: Float.self)
                    guard left.count >= lhs.elementCount,
                          right.count >= rhs.elementCount
                    else { return nil }
                    var sum = 0.0
                    for index in 0..<lhs.elementCount {
                        let delta = Double(left[index] - right[index])
                        sum += delta * delta
                    }
                    let distance = sum.squareRoot()
                    return lhs.source == .localGrid
                        ? distance * 100 / Double(lhs.elementCount).squareRoot()
                        : distance
                }
            }
        case .double:
            return lhs.data.withUnsafeBytes { leftRaw in
                rhs.data.withUnsafeBytes { rightRaw in
                    let left = leftRaw.bindMemory(to: Double.self)
                    let right = rightRaw.bindMemory(to: Double.self)
                    guard left.count >= lhs.elementCount,
                          right.count >= rhs.elementCount
                    else { return nil }
                    var sum = 0.0
                    for index in 0..<lhs.elementCount {
                        let delta = left[index] - right[index]
                        sum += delta * delta
                    }
                    let distance = sum.squareRoot()
                    return lhs.source == .localGrid
                        ? distance * 100 / Double(lhs.elementCount).squareRoot()
                        : distance
                }
            }
        }
    }

    private nonisolated static func fallbackFeatureVector(_ data: Data) -> FeatureVector? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let width = 12
        let height = 12
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var values: [Float] = []
        values.reserveCapacity(width * height * 3)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            values.append(Float(pixels[index]) / 255)
            values.append(Float(pixels[index + 1]) / 255)
            values.append(Float(pixels[index + 2]) / 255)
        }
        let vectorData = values.withUnsafeBytes { Data($0) }
        return FeatureVector(
            data: vectorData,
            elementCount: values.count,
            elementKind: .float,
            source: .localGrid
        )
    }

    private nonisolated static func differenceHash(_ data: Data) -> UInt64? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var fingerprint: UInt64 = 0
        var bit = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] > pixels[y * width + x + 1] {
                    fingerprint |= UInt64(1) << UInt64(bit)
                }
                bit += 1
            }
        }
        return fingerprint
    }
}
