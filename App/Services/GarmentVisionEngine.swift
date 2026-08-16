import CoreGraphics
import CoreML
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import Vision

enum GarmentVisionError: LocalizedError {
    case invalidImage
    case invalidModelOutput

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The captured image could not be read."
        case .invalidModelOutput: "The installed garment model returned an invalid result."
        }
    }
}

actor GarmentVisionEngine {
    private struct FrameMetrics {
        let sharpness: Double
        let luminance: Double
    }

    private struct RawDetection {
        let queryIndex: Int
        let classID: Int?
        let label: String
        let confidence: Double
        let box: BoundingBoxDTO
        let maskWidth: Int
        let maskHeight: Int
        let mask: [UInt8]
        /// Region of the accepted source represented by the mask tensor.
        let maskFrame: BoundingBoxDTO
    }

    private struct CoreMLDetectionResult {
        let detections: [RawDetection]
        let modelLoadMilliseconds: Double
        let inputPreparationMilliseconds: Double
        let inferenceMilliseconds: Double
        let outputDecodingMilliseconds: Double
    }

    private struct AdaptiveInferencePlan {
        let tileFrames: [BoundingBoxDTO]
        let thermalState: String
        let lowPowerMode: Bool
    }

    private struct ClassificationEvidence {
        let scores: [String: Double]

        func score(for identifiers: Set<String>) -> Double {
            scores.reduce(0) { current, pair in
                guard identifiers.contains(pair.key) else { return current }
                return max(current, pair.value)
            }
        }
    }

    private struct CachedClassificationEvidence {
        let signature: UInt64
        let createdAt: ContinuousClock.Instant
        let evidence: ClassificationEvidence
    }

    private static let acceptedCaptureBudgetMilliseconds = 9_000.0
    private static let cropReserveMilliseconds = 750.0

    private var loadedModelURL: URL?
    private var loadedModel: MLModel?
    private var classificationCache: [CachedClassificationEvidence] = []

    func prepare(modelURL: URL) throws {
        _ = try model(at: modelURL)
    }

#if DEBUG
    func debugClassificationEvidence(
        imageData: Data,
        boxes: [BoundingBoxDTO]
    ) -> [[String: Double]] {
        guard let image = Self.normalizedImage(from: imageData, maximumPixelSize: 5_120) else {
            return []
        }
        return boxes.map { box in
            guard let crop = Self.crop(image: image, to: box),
                  let evidence = classificationEvidenceForVerification(for: crop)
            else { return [:] }
            return Dictionary(
                uniqueKeysWithValues: evidence.scores
                    .filter { $0.value >= 0.01 }
                    .sorted { $0.value > $1.value }
                    .prefix(16)
                    .map { ($0.key, $0.value) }
            )
        }
    }
#endif

    func analyze(
        imageData: Data,
        modelURL: URL?,
        manifest: ModelPackManifestDTO?,
        maxItems: Int,
        includeCrops: Bool = true,
        includeDiagnosticMasks: Bool = false,
        enableAdaptiveDetail: Bool = true,
        verifyAllCandidateFamilies: Bool = true
    ) async throws -> GarmentDetectionBatch {
        // A saved garment needs its segmentation mask, not merely the rectangular detection
        // box. `includeDiagnosticMasks` is retained for call-site compatibility with the
        // inspector, but production captures now create the same usable transparent crop.
        _ = includeDiagnosticMasks
        let includesSegmentedCrops = includeCrops
        let totalStarted = Self.now
        let decodeStarted = Self.now
        guard let cgImage = Self.normalizedImage(
            from: imageData,
            maximumPixelSize: 5_120
        ) else {
            throw GarmentVisionError.invalidImage
        }
        let decodeMilliseconds = Self.milliseconds(since: decodeStarted)
        let itemLimit = min(12, max(1, maxItems))
        // Preserve a small pool of alternates until on-device verification has rejected
        // non-fashion lookalikes. Previously the top five raw boxes were verified in place;
        // a pillow, caption overlay, or duplicate class could consume the whole final budget
        // and hide valid garments lower in a busy live-screen frame.
        let discoveryLimit = min(12, max(itemLimit + 4, itemLimit * 2))
        let method: GarmentDetectionMethod
        let detections: [RawDetection]
        let modelInputResolution: Int
        let modelLoadMilliseconds: Double
        let inputPreparationMilliseconds: Double
        let inferenceMilliseconds: Double
        let outputDecodingMilliseconds: Double
        let inferencePassCount: Int
        let effectiveDetectionResolution: Int
        let inferenceStrategy: String
        let budgetLimited: Bool
        let thermalState: String
        let lowPowerMode: Bool
        if let modelURL, let manifest {
            method = .coreML
            let fullFrameResult = try coreMLDetections(
                image: cgImage,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: discoveryLimit,
                includeMasks: includesSegmentedCrops
            )
            let plan = Self.adaptiveInferencePlan(
                image: cgImage,
                enabled: enableAdaptiveDetail
            )
            var combined = fullFrameResult.detections
            var executedFrames = [Self.unitBox]
            var loadTime = fullFrameResult.modelLoadMilliseconds
            var preparationTime = fullFrameResult.inputPreparationMilliseconds
            var inferenceTime = fullFrameResult.inferenceMilliseconds
            var decodingTime = fullFrameResult.outputDecodingMilliseconds
            var didReachBudget = false
            let firstPassEstimate = max(
                120,
                (
                    fullFrameResult.inputPreparationMilliseconds
                        + fullFrameResult.inferenceMilliseconds
                        + fullFrameResult.outputDecodingMilliseconds
                ) * 1.6
            )

            for frame in plan.tileFrames {
                let elapsed = Self.milliseconds(since: totalStarted)
                guard elapsed + firstPassEstimate + Self.cropReserveMilliseconds
                    < Self.acceptedCaptureBudgetMilliseconds
                else {
                    didReachBudget = true
                    break
                }
                let currentThermalState = ProcessInfo.processInfo.thermalState
                guard currentThermalState != .serious, currentThermalState != .critical else {
                    didReachBudget = true
                    break
                }
                guard let tileImage = Self.crop(image: cgImage, to: frame) else { continue }
                let tileResult = try coreMLDetections(
                    image: tileImage,
                    modelURL: modelURL,
                    manifest: manifest,
                    maxItems: discoveryLimit,
                    includeMasks: includesSegmentedCrops
                )
                combined.append(
                    contentsOf: tileResult.detections.compactMap {
                        Self.remapTileDetection($0, from: frame)
                    }
                )
                executedFrames.append(frame)
                loadTime += tileResult.modelLoadMilliseconds
                preparationTime += tileResult.inputPreparationMilliseconds
                inferenceTime += tileResult.inferenceMilliseconds
                decodingTime += tileResult.outputDecodingMilliseconds
            }

            detections = Self.mergedDetections(combined, maxItems: discoveryLimit)
            modelInputResolution = manifest.inputResolution
            modelLoadMilliseconds = loadTime
            inputPreparationMilliseconds = preparationTime
            inferenceMilliseconds = inferenceTime
            outputDecodingMilliseconds = decodingTime
            inferencePassCount = executedFrames.count
            effectiveDetectionResolution = Self.effectiveDetectionResolution(
                sourceWidth: cgImage.width,
                sourceHeight: cgImage.height,
                modelResolution: manifest.inputResolution,
                frames: executedFrames
            )
            inferenceStrategy = executedFrames.count == 1
                ? "Single full-frame pass"
                : "Full frame + \(executedFrames.count - 1) detail tiles"
            budgetLimited = didReachBudget
            thermalState = plan.thermalState
            lowPowerMode = plan.lowPowerMode
        } else {
            method = .foregroundInstance
            let inferenceStarted = Self.now
            detections = try await foregroundDetections(
                image: cgImage,
                maxItems: discoveryLimit
            )
            modelInputResolution = 0
            modelLoadMilliseconds = 0
            inputPreparationMilliseconds = 0
            inferenceMilliseconds = Self.milliseconds(since: inferenceStarted)
            outputDecodingMilliseconds = 0
            inferencePassCount = 1
            effectiveDetectionResolution = 0
            inferenceStrategy = "Apple foreground instance mask"
            budgetLimited = false
            thermalState = Self.thermalStateLabel(ProcessInfo.processInfo.thermalState)
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        let verifiedDetections = try await verifiedDetections(
            detections,
            in: cgImage,
            maxItems: discoveryLimit,
            allowForegroundRecovery: true,
            verifyAllCandidateFamilies: verifyAllCandidateFamilies
        )
        let cropStarted = Self.now
        let candidates = verifiedDetections.prefix(itemLimit).map { detection in
            autoreleasepool {
                GarmentCandidate(
                    id: UUID().uuidString,
                    localLabel: detection.label,
                    confidence: detection.confidence,
                    box: detection.box,
                    boxCropData: includeCrops
                        ? Self.boundingBoxCrop(image: cgImage, detection: detection)
                        : nil,
                    cropData: includesSegmentedCrops
                        ? Self.segmentedCrop(image: cgImage, detection: detection)
                        : nil
                )
            }
        }
        let cropEncodingMilliseconds = Self.milliseconds(since: cropStarted)
        let metrics = GarmentPipelineMetrics(
            sourceWidth: cgImage.width,
            sourceHeight: cgImage.height,
            modelInputResolution: modelInputResolution,
            modelLoadMilliseconds: modelLoadMilliseconds,
            decodeMilliseconds: decodeMilliseconds,
            inputPreparationMilliseconds: inputPreparationMilliseconds,
            inferenceMilliseconds: inferenceMilliseconds,
            outputDecodingMilliseconds: outputDecodingMilliseconds,
            cropEncodingMilliseconds: cropEncodingMilliseconds,
            totalMilliseconds: Self.milliseconds(since: totalStarted),
            inferencePassCount: inferencePassCount,
            effectiveDetectionResolution: effectiveDetectionResolution,
            inferenceStrategy: inferenceStrategy,
            processingBudgetMilliseconds: Self.acceptedCaptureBudgetMilliseconds,
            budgetLimited: budgetLimited,
            thermalState: thermalState,
            lowPowerMode: lowPowerMode
        )
        return GarmentDetectionBatch(
            method: method,
            candidates: candidates,
            metrics: metrics
        )
    }

    func preview(
        imageData: Data,
        modelURL: URL,
        manifest: ModelPackManifestDTO,
        maxItems: Int,
        focusFrame: BoundingBoxDTO? = nil
    ) async throws -> LiveGarmentPreview {
        guard let sourceImage = Self.normalizedImage(
            from: imageData,
            maximumPixelSize: 1_600
        ) else {
            throw GarmentVisionError.invalidImage
        }
        let acceptedFocus: BoundingBoxDTO?
        let inferenceImage: CGImage
        if let focusFrame,
           let focusedImage = Self.crop(image: sourceImage, to: focusFrame)
        {
            acceptedFocus = focusFrame
            inferenceImage = focusedImage
        } else {
            acceptedFocus = nil
            inferenceImage = sourceImage
        }
        let rawDetections = try coreMLDetections(
            image: inferenceImage,
            modelURL: modelURL,
            manifest: manifest,
            maxItems: min(12, max(1, maxItems)),
            includeMasks: false,
            minimumConfidence: 0.42
        ).detections
        let mappedDetections: [RawDetection]
        if let acceptedFocus {
            mappedDetections = rawDetections.compactMap {
                Self.remapTileDetection($0, from: acceptedFocus)
            }
        } else {
            mappedDetections = rawDetections
        }
        let detections = try await verifiedDetections(
            mappedDetections,
            in: sourceImage,
            maxItems: min(12, max(1, maxItems)),
            allowForegroundRecovery: acceptedFocus == nil,
            verifyAllCandidateFamilies: false
        )
        let detection = GarmentDetectionBatch(
            method: .coreML,
            candidates: detections.map {
                GarmentCandidate(
                    id: UUID().uuidString,
                    localLabel: $0.label,
                    confidence: $0.confidence,
                    box: $0.box,
                    boxCropData: nil,
                    cropData: nil
                )
            },
            metrics: nil
        )
        let metrics = Self.frameMetrics(inferenceImage)
        let qualityBoxes = detections.map { detection -> BoundingBoxDTO in
            guard let acceptedFocus else { return detection.box }
            return BoundingBoxDTO(
                x: (detection.box.x - acceptedFocus.x) / acceptedFocus.width,
                y: (detection.box.y - acceptedFocus.y) / acceptedFocus.height,
                width: detection.box.width / acceptedFocus.width,
                height: detection.box.height / acceptedFocus.height
            )
        }
        let largestArea = qualityBoxes
            .map { $0.width * $0.height }
            .max() ?? 0
        let clipped = qualityBoxes.contains { box in
            box.x < 0.018
                || box.y < 0.018
                || box.x + box.width > 0.982
                || box.y + box.height > 0.982
        }
        let meanConfidence = detection.candidates.isEmpty
            ? 0
            : detection.candidates.map(\.confidence).reduce(0, +)
                / Double(detection.candidates.count)
        var quality = 0.45 * metrics.sharpness
            + 0.35 * min(1, largestArea / 0.22)
            + 0.20 * meanConfidence
        if clipped { quality *= 0.72 }
        if metrics.luminance < 0.14 || metrics.luminance > 0.94 { quality *= 0.66 }

        let guidance: LiveCaptureGuidance
        if detection.candidates.isEmpty {
            guidance = .aimAtFashion
        } else if largestArea < 0.04 {
            guidance = .moveCloser
        } else if clipped {
            guidance = .centerItem
        } else if metrics.luminance < 0.14 {
            guidance = .moreLight
        } else if metrics.sharpness < 0.28 {
            guidance = .holdStill
        } else {
            guidance = .ready
        }
        return LiveGarmentPreview(
            candidates: detection.candidates,
            qualityScore: min(1, max(0, quality)),
            guidance: guidance
        )
    }

    /// A screen-specific preview that keeps the accepted-still detector's overlapping detail
    /// tiles but skips crop and mask encoding. Tall phone screenshots can reduce a product near
    /// the top or bottom of a page to too few pixels in a single 384-point full-frame tensor.
    /// This path is still bounded by the same Low Power Mode, thermal, and nine-second safeguards
    /// as final analysis, while remaining much cheaper because it returns boxes only.
    func adaptiveScreenPreview(
        imageData: Data,
        modelURL: URL,
        manifest: ModelPackManifestDTO,
        maxItems: Int
    ) async throws -> LiveGarmentPreview {
        let detection = try await analyze(
            imageData: imageData,
            modelURL: modelURL,
            manifest: manifest,
            maxItems: maxItems,
            includeCrops: false,
            includeDiagnosticMasks: false,
            enableAdaptiveDetail: true,
            verifyAllCandidateFamilies: false
        )
        let candidates = detection.candidates
        let largestArea = candidates
            .map { max(0, $0.box.width * $0.box.height) }
            .max() ?? 0
        let meanConfidence = candidates.isEmpty
            ? 0
            : candidates.map(\.confidence).reduce(0, +) / Double(candidates.count)
        // Stability across two independently sampled frames is the primary false-positive guard. Keep this quality
        // score permissive enough for watches, ties, and other physically small accessories.
        let areaScore = min(1, largestArea / 0.10)
        let quality = min(1, max(0, 0.68 * meanConfidence + 0.32 * areaScore))
        let guidance: LiveCaptureGuidance
        if candidates.isEmpty {
            guidance = .aimAtFashion
        } else if largestArea < 0.004 {
            guidance = .moveCloser
        } else {
            guidance = .ready
        }
        return LiveGarmentPreview(
            candidates: candidates,
            qualityScore: quality,
            guidance: guidance
        )
    }

    private nonisolated static var unitBox: BoundingBoxDTO {
        BoundingBoxDTO(x: 0, y: 0, width: 1, height: 1)
    }

    /// Adds detail passes only for accepted still photos. The plan is reduced or
    /// disabled when Low Power Mode or elevated thermal pressure is present.
    private nonisolated static func adaptiveInferencePlan(
        image: CGImage,
        enabled: Bool
    ) -> AdaptiveInferencePlan {
        let processInfo = ProcessInfo.processInfo
        let thermal = processInfo.thermalState
        let lowPower = processInfo.isLowPowerModeEnabled
        let longestSide = max(image.width, image.height)
        guard enabled, longestSide >= 1_800, !lowPower else {
            return AdaptiveInferencePlan(
                tileFrames: [],
                thermalState: thermalStateLabel(thermal),
                lowPowerMode: lowPower
            )
        }

        let divisions: Int
        switch thermal {
        case .nominal:
            divisions = longestSide >= 3_840 ? 3 : 2
        case .fair:
            divisions = longestSide >= 2_560 ? 2 : 0
        case .serious, .critical:
            divisions = 0
        @unknown default:
            divisions = 0
        }
        return AdaptiveInferencePlan(
            tileFrames: divisions == 0
                ? []
                : Array(
                    detailTileFrames(
                        width: image.width,
                        height: image.height,
                        divisions: divisions
                    ).prefix(8)
                ),
            thermalState: thermalStateLabel(thermal),
            lowPowerMode: lowPower
        )
    }

    /// Produces overlapping square source-space tiles. Square tiles avoid the
    /// extra aspect-ratio distortion of normalized rectangular quadrants.
    private nonisolated static func detailTileFrames(
        width: Int,
        height: Int,
        divisions: Int
    ) -> [BoundingBoxDTO] {
        let sourceWidth = Double(width)
        let sourceHeight = Double(height)
        let longest = max(sourceWidth, sourceHeight)
        let shortest = min(sourceWidth, sourceHeight)
        let tileSide = min(shortest, longest / Double(divisions) * 1.12)

        func positions(total: Double) -> [Double] {
            let count = max(1, Int(ceil(total / tileSide)))
            guard count > 1 else { return [0] }
            let travel = max(0, total - tileSide)
            return (0..<count).map { travel * Double($0) / Double(count - 1) }
        }

        return positions(total: sourceHeight).flatMap { y in
            positions(total: sourceWidth).map { x in
                BoundingBoxDTO(
                    x: x / sourceWidth,
                    y: y / sourceHeight,
                    width: tileSide / sourceWidth,
                    height: tileSide / sourceHeight
                )
            }
        }
    }

    private nonisolated static func crop(
        image: CGImage,
        to frame: BoundingBoxDTO
    ) -> CGImage? {
        let rect = CGRect(
            x: frame.x * Double(image.width),
            y: frame.y * Double(image.height),
            width: frame.width * Double(image.width),
            height: frame.height * Double(image.height)
        ).integral.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        return image.cropping(to: rect)
    }

    private nonisolated static func remapTileDetection(
        _ detection: RawDetection,
        from frame: BoundingBoxDTO
    ) -> RawDetection? {
        let edgeMargin = 0.02
        let local = detection.box
        if frame.x > 0.001, local.x < edgeMargin { return nil }
        if frame.y > 0.001, local.y < edgeMargin { return nil }
        if frame.x + frame.width < 0.999,
           local.x + local.width > 1 - edgeMargin
        { return nil }
        if frame.y + frame.height < 0.999,
           local.y + local.height > 1 - edgeMargin
        { return nil }

        return RawDetection(
            queryIndex: detection.queryIndex,
            classID: detection.classID,
            label: detection.label,
            confidence: detection.confidence,
            box: BoundingBoxDTO(
                x: frame.x + local.x * frame.width,
                y: frame.y + local.y * frame.height,
                width: local.width * frame.width,
                height: local.height * frame.height
            ),
            maskWidth: detection.maskWidth,
            maskHeight: detection.maskHeight,
            mask: detection.mask,
            maskFrame: frame
        )
    }

    private nonisolated static func mergedDetections(
        _ detections: [RawDetection],
        maxItems: Int
    ) -> [RawDetection] {
        var selected: [RawDetection] = []
        for candidate in detections.sorted(by: { $0.confidence > $1.confidence }) {
            let duplicate = selected.contains { existing in
                let overlap = iou(existing.box, candidate.box)
                return (existing.classID == candidate.classID && overlap > 0.60)
                    || overlap > 0.88
            }
            guard !duplicate else { continue }
            selected.append(candidate)
            if selected.count == maxItems { break }
        }
        return selected
    }

    /// RF-DETR is trained on Fashionpedia, so a bedding texture can look strongly like a bag or
    /// puffer jacket even when the object is not wearable. Apple's broad on-device classifier is
    /// used as a cheap second opinion on only the proposed boxes. Strong bedding/furniture
    /// evidence rejects those out-of-domain regions, while clothing/luggage evidence can correct
    /// common label swaps such as jeans → skirt. If RF-DETR misses an obvious foreground bag or
    /// garment entirely, the same evidence can recover one foreground instance without a cloud
    /// request or another downloaded model.
    private func verifiedDetections(
        _ detections: [RawDetection],
        in image: CGImage,
        maxItems: Int,
        allowForegroundRecovery: Bool,
        verifyAllCandidateFamilies: Bool
    ) async throws -> [RawDetection] {
        guard ProcessInfo.processInfo.thermalState != .critical else { return detections }

        var verified: [RawDetection] = []
        for detection in detections {
            guard verifyAllCandidateFamilies
                    || Self.requiresClassificationVerification(detection)
            else {
                verified.append(detection)
                if verified.count == maxItems { break }
                continue
            }
            guard let crop = Self.crop(image: image, to: detection.box),
                  let evidence = classificationEvidenceForVerification(for: crop)
            else {
                verified.append(detection)
                if verified.count == maxItems { break }
                continue
            }
            guard !Self.shouldReject(detection, using: evidence) else { continue }
            verified.append(Self.refined(detection, using: evidence))
            if verified.count == maxItems { break }
        }
        if !verified.isEmpty || !allowForegroundRecovery { return verified }

        guard let frameEvidence = classificationEvidenceForVerification(for: image),
              let fallback = Self.foregroundFashionLabel(from: frameEvidence)
        else { return [] }
        let foreground = try await foregroundDetections(image: image, maxItems: 1)
        return foreground.prefix(1).map { detection in
            RawDetection(
                queryIndex: detection.queryIndex,
                classID: nil,
                label: fallback.label,
                confidence: min(
                    0.96,
                    Foundation.sqrt(max(0, detection.confidence * fallback.confidence))
                ),
                box: detection.box,
                maskWidth: detection.maskWidth,
                maskHeight: detection.maskHeight,
                mask: detection.mask,
                maskFrame: detection.maskFrame
            )
        }
    }

    /// The Fashionpedia model is already reliable for most small accessories.
    /// Broad second-opinion classification is reserved for the label families
    /// that produced the observed household-object and lower-body mistakes, so
    /// live preview does not run another Vision model for every candidate.
    private nonisolated static func requiresClassificationVerification(
        _ detection: RawDetection
    ) -> Bool {
        let label = detection.label.lowercased()
        return [
            "bag", "wallet", "purse", "backpack", "jacket", "coat", "cape",
            "skirt", "pants", "trouser", "jeans", "shorts", "dress",
        ].contains { label.contains($0) }
    }

    private nonisolated static func classificationEvidence(
        for image: CGImage
    ) -> ClassificationEvidence? {
        guard min(image.width, image.height) >= 48 else { return nil }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let results = request.results, !results.isEmpty else { return nil }
        var scores: [String: Double] = [:]
        for result in results.prefix(45) {
            let identifier = result.identifier.lowercased()
            let confidence = Double(result.confidence)
            let aliases = Set(
                [identifier]
                    + identifier
                        .split(whereSeparator: { $0 == "," || $0 == ";" })
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    + identifier
                        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                        .map(String.init)
            )
            for alias in aliases where !alias.isEmpty {
                scores[alias] = max(scores[alias] ?? 0, confidence)
            }
        }
        return ClassificationEvidence(scores: scores)
    }

    private func classificationEvidenceForVerification(
        for image: CGImage
    ) -> ClassificationEvidence? {
        let now = ContinuousClock.now
        classificationCache.removeAll {
            $0.createdAt.duration(to: now) > .seconds(3)
        }
        if let signature = Self.classificationSignature(for: image),
           let cached = classificationCache.first(where: {
               ($0.signature ^ signature).nonzeroBitCount <= 3
           })
        {
            return cached.evidence
        }
        guard let evidence = Self.classificationEvidence(for: image) else { return nil }
        if let signature = Self.classificationSignature(for: image) {
            classificationCache.append(
                CachedClassificationEvidence(
                    signature: signature,
                    createdAt: now,
                    evidence: evidence
                )
            )
            if classificationCache.count > 12 {
                classificationCache.removeFirst(classificationCache.count - 12)
            }
        }
        return evidence
    }

    private nonisolated static func classificationSignature(for image: CGImage) -> UInt64? {
        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let average = pixels.reduce(0, { $0 + Int($1) }) / pixels.count
        var signature: UInt64 = 0
        for (index, pixel) in pixels.enumerated() where Int(pixel) >= average {
            signature |= UInt64(1) << UInt64(index)
        }
        return signature
    }

    private nonisolated static let clothingClassifiers: Set<String> = [
        "clothing", "apparel", "jean", "jeans", "denim", "pants", "trouser", "trousers", "shorts", "skirt",
        "dress", "shirt", "blouse", "t-shirt", "tee shirt", "top", "sweatshirt", "hoodie",
        "sweater", "cardigan", "jacket", "coat", "vest", "suit", "jersey", "sock",
        "stocking", "scarf", "necktie",
    ]
    private nonisolated static let topClassifiers: Set<String> = [
        "shirt", "blouse", "t-shirt", "tee shirt", "tee", "top", "jersey", "sweatshirt",
        "hoodie", "sweater", "cardigan", "vest",
    ]
    private nonisolated static let outerwearClassifiers: Set<String> = [
        "jacket", "coat", "blazer", "parka", "overcoat", "windbreaker", "cape",
    ]
    private nonisolated static let bagClassifiers: Set<String> = [
        "bag", "handbag", "purse", "wallet", "backpack", "back pack", "rucksack",
        "haversack", "luggage", "suitcase", "duffel", "holdall", "kitbag",
    ]
    private nonisolated static let shoeClassifiers: Set<String> = [
        "shoe", "footwear", "sneaker", "boot", "sandal", "loafer",
    ]
    private nonisolated static let accessoryClassifiers: Set<String> = [
        "hat", "headwear", "cap", "beanie", "glove", "watch", "wristwatch",
        "eyeglasses", "sunglasses", "jewelry", "necklace", "bracelet", "ring",
    ]
    private nonisolated static let nonFashionClassifiers: Set<String> = [
        "bedding", "pillow", "bed", "blanket", "comforter", "duvet", "quilt",
        "cushion", "throw pillow", "bolster", "mattress", "bedspread", "bedclothes",
        "bedsheet", "bed sheet", "linen", "linens", "sleeping bag", "furniture", "sofa",
        "couch", "curtain", "shower curtain", "towel", "bath towel", "upholstery",
        "rug", "carpet", "doormat", "tablecloth", "placemat",
    ]

    private nonisolated static func shouldReject(
        _ detection: RawDetection,
        using evidence: ClassificationEvidence
    ) -> Bool {
        let negative = evidence.score(for: nonFashionClassifiers)
        guard negative >= 0.16 else { return false }
        let lowerLabel = detection.label.lowercased()
        let relevantPositive: Double
        if lowerLabel.contains("bag") || lowerLabel.contains("wallet") {
            relevantPositive = evidence.score(for: bagClassifiers)
        } else if lowerLabel.contains("shoe") {
            relevantPositive = evidence.score(for: shoeClassifiers)
        } else if lowerLabel.contains("hat") || lowerLabel.contains("watch")
            || lowerLabel.contains("glove") || lowerLabel.contains("glasses")
        {
            relevantPositive = evidence.score(for: accessoryClassifiers)
        } else {
            relevantPositive = evidence.score(for: clothingClassifiers)
        }
        return negative >= 0.18 && negative > max(0.07, relevantPositive * 1.25)
    }

    private nonisolated static func refined(
        _ detection: RawDetection,
        using evidence: ClassificationEvidence
    ) -> RawDetection {
        let jeans = evidence.score(for: ["jean", "jeans", "denim", "pants", "trouser", "trousers"])
        let skirt = evidence.score(for: ["skirt"])
        let bag = evidence.score(for: bagClassifiers)
        let shoe = evidence.score(for: shoeClassifiers)
        let clothing = evidence.score(for: clothingClassifiers)
        let top = evidence.score(for: topClassifiers)
        let outerwear = evidence.score(for: outerwearClassifiers)
        let detectedLabel = detection.label.lowercased()
        let label: String
        var confidence: Double
        if bag >= 0.10, bag > max(0.06, clothing * 1.15) {
            label = "bag, wallet"
            let geometricSupport = Foundation.sqrt(max(0, detection.confidence * bag))
            let nonFashion = evidence.score(for: nonFashionClassifiers)
            if nonFashion < max(0.12, bag * 1.15) {
                // Calibrated on the physical false-positive corpus: a true bag
                // can receive a modest broad-classifier score while RF-DETR is
                // strong. When both signals agree and bedding evidence does not
                // dominate, lift the fused score above the human-review gate.
                // Raw RF-DETR confidence alone can never take this path.
                confidence = max(
                    geometricSupport,
                    min(0.92, 0.45 + 0.70 * detection.confidence + 0.80 * bag)
                )
            } else {
                confidence = geometricSupport
            }
        } else if jeans >= 0.16, jeans > skirt * 1.25 {
            label = "pants"
            confidence = max(
                Foundation.sqrt(max(0, detection.confidence * jeans)),
                min(0.92, jeans * 0.98)
            )
        } else if skirt >= 0.16, skirt > jeans * 1.25 {
            label = "skirt"
            confidence = Foundation.sqrt(max(0, detection.confidence * skirt))
        } else if shoe >= 0.18, detection.label.lowercased().contains("shoe") {
            label = "shoe"
            confidence = Foundation.sqrt(max(0, detection.confidence * shoe))
        } else if ["jacket", "coat", "cape"].contains(where: detectedLabel.contains),
                  top >= 0.14,
                  top > max(0.06, outerwear * 1.30)
        {
            // White tees and close-fitting tops are the most damaging outerwear swap in the
            // physical corpus. Relabel only when Apple's independent classifier clearly favors
            // a top; otherwise retain the detector label and require confirmation below 88%.
            label = "top, t-shirt, sweatshirt"
            confidence = min(
                0.94,
                max(
                    Foundation.sqrt(max(0, detection.confidence * top)),
                    0.58 + top * 0.42
                )
            )
        } else {
            label = detection.label
            confidence = detection.confidence
        }
        let relevant = max(clothing, max(bag, max(shoe, evidence.score(for: accessoryClassifiers))))
        let nonFashion = evidence.score(for: nonFashionClassifiers)
        if nonFashion >= 0.12, nonFashion > relevant {
            confidence = min(confidence, 0.55)
        } else if relevant < 0.05 {
            // A high Fashionpedia sigmoid without any broad fashion support is not a calibrated
            // probability. Keep the candidate visible for correction, but force human review.
            confidence = min(confidence, 0.70)
        }
        guard label != detection.label || abs(confidence - detection.confidence) > 0.01 else {
            return detection
        }
        return RawDetection(
            queryIndex: detection.queryIndex,
            classID: detection.classID,
            label: label,
            confidence: min(0.96, max(0.05, confidence)),
            box: detection.box,
            maskWidth: detection.maskWidth,
            maskHeight: detection.maskHeight,
            mask: detection.mask,
            maskFrame: detection.maskFrame
        )
    }

    private nonisolated static func foregroundFashionLabel(
        from evidence: ClassificationEvidence
    ) -> (label: String, confidence: Double)? {
        let candidates: [(String, Double)] = [
            ("bag, wallet", evidence.score(for: bagClassifiers)),
            ("shoe", evidence.score(for: shoeClassifiers)),
            ("fashion accessory", evidence.score(for: accessoryClassifiers)),
            ("clothing", evidence.score(for: clothingClassifiers)),
        ]
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 >= 0.18 else {
            return nil
        }
        let negative = evidence.score(for: nonFashionClassifiers)
        guard negative < 0.22 || best.1 >= negative * 0.82 else { return nil }
        return best
    }

    private nonisolated static func effectiveDetectionResolution(
        sourceWidth: Int,
        sourceHeight: Int,
        modelResolution: Int,
        frames: [BoundingBoxDTO]
    ) -> Int {
        let useWidth = sourceWidth >= sourceHeight
        let bestFraction = frames.map { useWidth ? $0.width : $0.height }.min() ?? 1
        let projected = Int((Double(modelResolution) / max(0.001, bestFraction)).rounded())
        return min(max(sourceWidth, sourceHeight), projected)
    }

    private nonisolated static func thermalStateLabel(
        _ state: ProcessInfo.ThermalState
    ) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private func coreMLDetections(
        image: CGImage,
        modelURL: URL,
        manifest: ModelPackManifestDTO,
        maxItems: Int,
        includeMasks: Bool,
        minimumConfidence: Double = 0.35
    ) throws -> CoreMLDetectionResult {
        let modelStarted = Self.now
        let model = try model(at: modelURL)
        let modelLoadMilliseconds = Self.milliseconds(since: modelStarted)
        let preparationStarted = Self.now
        let input = try Self.modelInput(
            image: image,
            resolution: manifest.inputResolution
        )
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [manifest.inputName: MLFeatureValue(multiArray: input)]
        )
        let inputPreparationMilliseconds = Self.milliseconds(since: preparationStarted)
        let inferenceStarted = Self.now
        let result = try model.prediction(from: provider)
        let inferenceMilliseconds = Self.milliseconds(since: inferenceStarted)
        let outputStarted = Self.now
        guard let boxes = result.featureValue(for: manifest.boxOutputName)?.multiArrayValue,
              let logits = result.featureValue(for: manifest.logitOutputName)?.multiArrayValue,
              let masks = result.featureValue(for: manifest.maskOutputName)?.multiArrayValue,
              boxes.shape.count == 3,
              logits.shape.count == 3,
              masks.shape.count == 4
        else {
            throw GarmentVisionError.invalidModelOutput
        }
        let queryCount = boxes.shape[1].intValue
        let classCount = logits.shape[2].intValue
        let maskHeight = masks.shape[2].intValue
        let maskWidth = masks.shape[3].intValue
        let searchableCount = min(27, min(classCount, manifest.classNames.count))

        var scored: [(query: Int, classID: Int, confidence: Double, box: BoundingBoxDTO)] = []
        for query in 0..<queryCount {
            var bestClass = 0
            var bestConfidence = 0.0
            for classID in 0..<searchableCount {
                let logit = Self.value(logits, [0, query, classID])
                let confidence = 1 / (1 + Foundation.exp(-logit))
                if confidence > bestConfidence {
                    bestClass = classID
                    bestConfidence = confidence
                }
            }
            guard bestConfidence >= minimumConfidence else { continue }
            let centerX = Self.value(boxes, [0, query, 0])
            let centerY = Self.value(boxes, [0, query, 1])
            let width = Self.value(boxes, [0, query, 2])
            let height = Self.value(boxes, [0, query, 3])
            let left = max(0, centerX - width / 2)
            let top = max(0, centerY - height / 2)
            let right = min(1, centerX + width / 2)
            let bottom = min(1, centerY + height / 2)
            guard right - left >= 0.025, bottom - top >= 0.025 else { continue }
            scored.append(
                (
                    query,
                    bestClass,
                    bestConfidence,
                    BoundingBoxDTO(
                        x: left,
                        y: top,
                        width: right - left,
                        height: bottom - top
                    )
                )
            )
        }
        scored.sort { $0.confidence > $1.confidence }

        var selected: [(query: Int, classID: Int, confidence: Double, box: BoundingBoxDTO)] = []
        for candidate in scored {
            let isDuplicate = selected.contains {
                $0.classID == candidate.classID && Self.iou($0.box, candidate.box) > 0.74
            }
            if !isDuplicate {
                selected.append(candidate)
            }
            if selected.count == maxItems { break }
        }

        let decoded = selected.map { candidate in
            guard includeMasks else {
                return RawDetection(
                    queryIndex: candidate.query,
                    classID: candidate.classID,
                    label: manifest.classNames[candidate.classID],
                    confidence: candidate.confidence,
                    box: candidate.box,
                    maskWidth: 0,
                    maskHeight: 0,
                    mask: [],
                    maskFrame: Self.unitBox
                )
            }
            var mask = [UInt8](repeating: 0, count: maskWidth * maskHeight)
            for y in 0..<maskHeight {
                for x in 0..<maskWidth {
                    mask[y * maskWidth + x] = Self.softMaskAlpha(
                        logit: Self.value(masks, [0, candidate.query, y, x])
                    )
                }
            }
            return RawDetection(
                queryIndex: candidate.query,
                classID: candidate.classID,
                label: manifest.classNames[candidate.classID],
                confidence: candidate.confidence,
                box: candidate.box,
                maskWidth: maskWidth,
                maskHeight: maskHeight,
                mask: mask,
                maskFrame: Self.unitBox
            )
        }
        return CoreMLDetectionResult(
            detections: decoded,
            modelLoadMilliseconds: modelLoadMilliseconds,
            inputPreparationMilliseconds: inputPreparationMilliseconds,
            inferenceMilliseconds: inferenceMilliseconds,
            outputDecodingMilliseconds: Self.milliseconds(since: outputStarted)
        )
    }

    private func foregroundDetections(
        image: CGImage,
        maxItems: Int
    ) async throws -> [RawDetection] {
        let request = GenerateForegroundInstanceMaskRequest()
        guard let observation = try await request.perform(on: image) else { return [] }
        var candidates: [(area: Double, detection: RawDetection)] = []
        for instance in observation.allInstances {
            let pixelBuffer = try observation.generateMask(for: IndexSet(integer: instance))
            guard let maskResult = Self.maskAndBox(from: pixelBuffer) else { continue }
            let area = maskResult.box.width * maskResult.box.height
            guard area >= 0.002 else { continue }
            candidates.append(
                (
                    area,
                    RawDetection(
                        queryIndex: instance,
                        classID: nil,
                        label: "fashion item",
                        confidence: Double(observation.confidence),
                        box: maskResult.box,
                        maskWidth: maskResult.width,
                        maskHeight: maskResult.height,
                        mask: maskResult.mask,
                        maskFrame: Self.unitBox
                    )
                )
            )
        }
        candidates.sort { $0.area > $1.area }
        return candidates.prefix(maxItems).map(\.detection)
    }

    private func model(at url: URL) throws -> MLModel {
        if loadedModelURL == url, let loadedModel {
            return loadedModel
        }
        let configuration = MLModelConfiguration()
        // The current segmentation package returns all-zero class logits through
        // the GPU/Neural Engine path on iOS 26/27. CPU execution is deterministic
        // and matches the validated Fashionpedia benchmark output.
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: url, configuration: configuration)
        loadedModelURL = url
        loadedModel = model
        return model
    }

    private nonisolated static var now: Double {
        ProcessInfo.processInfo.systemUptime
    }

    private nonisolated static func milliseconds(since started: Double) -> Double {
        (now - started) * 1_000
    }

    private nonisolated static func normalizedImage(
        from data: Data,
        maximumPixelSize: Int
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        )
    }

    private nonisolated static func modelInput(
        image: CGImage,
        resolution: Int
    ) throws -> MLMultiArray {
        let bytesPerRow = resolution * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * resolution)
        guard let context = CGContext(
            data: &pixels,
            width: resolution,
            height: resolution,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw GarmentVisionError.invalidImage
        }
        context.interpolationQuality = .medium
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: resolution, height: resolution)
        )

        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: resolution), NSNumber(value: resolution)],
            dataType: .float32
        )
        let pointer = array.dataPointer.bindMemory(
            to: Float32.self,
            capacity: 3 * resolution * resolution
        )
        let planeSize = resolution * resolution
        let redScale: Float32 = 1 / (255 * 0.229)
        let greenScale: Float32 = 1 / (255 * 0.224)
        let blueScale: Float32 = 1 / (255 * 0.225)
        let redBias: Float32 = -0.485 / 0.229
        let greenBias: Float32 = -0.456 / 0.224
        let blueBias: Float32 = -0.406 / 0.225
        for destination in 0..<planeSize {
            let source = destination * 4
            pointer[destination] = Float32(pixels[source]) * redScale + redBias
            pointer[planeSize + destination] =
                Float32(pixels[source + 1]) * greenScale + greenBias
            pointer[2 * planeSize + destination] =
                Float32(pixels[source + 2]) * blueScale + blueBias
        }
        return array
    }

    private nonisolated static func frameMetrics(_ image: CGImage) -> FrameMetrics {
        let width = 96
        let height = 96
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return FrameMetrics(sharpness: 0, luminance: 0.5)
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var edgeTotal = 0.0
        var edgeCount = 0
        var luminanceTotal = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let value = Double(pixels[y * width + x])
                luminanceTotal += value
                if x + 1 < width {
                    edgeTotal += abs(value - Double(pixels[y * width + x + 1]))
                    edgeCount += 1
                }
                if y + 1 < height {
                    edgeTotal += abs(value - Double(pixels[(y + 1) * width + x]))
                    edgeCount += 1
                }
            }
        }
        let meanEdge = edgeCount == 0 ? 0 : edgeTotal / Double(edgeCount)
        return FrameMetrics(
            sharpness: min(1, meanEdge / 17),
            luminance: luminanceTotal / Double(width * height) / 255
        )
    }

    private nonisolated static func value(
        _ array: MLMultiArray,
        _ indexes: [Int]
    ) -> Double {
        array[indexes.map(NSNumber.init(value:))].doubleValue
    }

    private nonisolated static func iou(
        _ left: BoundingBoxDTO,
        _ right: BoundingBoxDTO
    ) -> Double {
        let x1 = max(left.x, right.x)
        let y1 = max(left.y, right.y)
        let x2 = min(left.x + left.width, right.x + right.width)
        let y2 = min(left.y + left.height, right.y + right.height)
        let intersection = max(0, x2 - x1) * max(0, y2 - y1)
        guard intersection > 0 else { return 0 }
        return intersection / (left.width * left.height + right.width * right.height - intersection)
    }

    private nonisolated static func maskAndBox(
        from pixelBuffer: CVPixelBuffer
    ) -> (mask: [UInt8], width: Int, height: Int, box: BoundingBoxDTO)? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var mask = [UInt8](repeating: 0, count: width * height)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let active: Bool
                if format == kCVPixelFormatType_OneComponent32Float {
                    let row = baseAddress.advanced(by: y * bytesPerRow)
                        .assumingMemoryBound(to: Float32.self)
                    active = row[x] > 0.5
                } else {
                    let row = baseAddress.advanced(by: y * bytesPerRow)
                        .assumingMemoryBound(to: UInt8.self)
                    active = row[x] > 0
                }
                guard active else { continue }
                mask[y * width + x] = 255
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (
            mask,
            width,
            height,
            BoundingBoxDTO(
                x: Double(minX) / Double(width),
                y: Double(minY) / Double(height),
                width: Double(maxX - minX + 1) / Double(width),
                height: Double(maxY - minY + 1) / Double(height)
            )
        )
    }

    private nonisolated static func segmentedCrop(
        image: CGImage,
        detection: RawDetection
    ) -> Data? {
        guard detection.maskWidth > 0,
              detection.maskHeight > 0,
              !detection.mask.isEmpty,
              detection.maskFrame.width > 0,
              detection.maskFrame.height > 0
        else { return nil }
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let padding = max(detection.box.width, detection.box.height) * 0.025
        let left = max(0, detection.box.x - padding)
        let top = max(0, detection.box.y - padding)
        let right = min(1, detection.box.x + detection.box.width + padding)
        let bottom = min(1, detection.box.y + detection.box.height + padding)
        let cropRect = CGRect(
            x: left * imageWidth,
            y: top * imageHeight,
            width: (right - left) * imageWidth,
            height: (bottom - top) * imageHeight
        ).integral
        guard cropRect.width >= 2,
              cropRect.height >= 2,
              let cropped = image.cropping(to: cropRect)
        else { return nil }

        let scale = min(1, 1_024 / max(cropRect.width, cropRect.height))
        let targetWidth = max(1, Int((cropRect.width * scale).rounded()))
        let targetHeight = max(1, Int((cropRect.height * scale).rounded()))
        var alpha = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        let xSamples = (0..<targetWidth).map { x -> (Int, Int, Double) in
            let sourceX = cropRect.minX + (CGFloat(x) + 0.5) / scale
            let fullCoordinate = Double(sourceX / imageWidth)
            let tileCoordinate = (fullCoordinate - detection.maskFrame.x)
                / detection.maskFrame.width
            let coordinate = tileCoordinate * Double(detection.maskWidth) - 0.5
            let low = max(0, min(detection.maskWidth - 1, Int(floor(coordinate))))
            let high = max(0, min(detection.maskWidth - 1, low + 1))
            return (low, high, min(1, max(0, coordinate - floor(coordinate))))
        }
        for y in 0..<targetHeight {
            let sourceY = cropRect.minY + (CGFloat(y) + 0.5) / scale
            let fullCoordinateY = Double(sourceY / imageHeight)
            let tileCoordinateY = (fullCoordinateY - detection.maskFrame.y)
                / detection.maskFrame.height
            let coordinateY = tileCoordinateY * Double(detection.maskHeight) - 0.5
            let yFloor = floor(coordinateY)
            let lowY = max(0, min(detection.maskHeight - 1, Int(yFloor)))
            let highY = max(0, min(detection.maskHeight - 1, lowY + 1))
            let fractionY = min(1, max(0, coordinateY - yFloor))
            for (x, sample) in xSamples.enumerated() {
                let topLeft = Double(detection.mask[lowY * detection.maskWidth + sample.0])
                let topRight = Double(detection.mask[lowY * detection.maskWidth + sample.1])
                let bottomLeft = Double(detection.mask[highY * detection.maskWidth + sample.0])
                let bottomRight = Double(detection.mask[highY * detection.maskWidth + sample.1])
                let top = topLeft + (topRight - topLeft) * sample.2
                let bottom = bottomLeft + (bottomRight - bottomLeft) * sample.2
                alpha[y * targetWidth + x] = UInt8(
                    min(255, max(0, (top + (bottom - top) * fractionY).rounded()))
                )
            }
        }
        // A full opaque rectangle is not a useful segmented crop. Keep its reliable JPEG box
        // crop instead; otherwise save a transparent PNG so Library, Search, and Try On do not
        // inherit surrounding bedding, browser chrome, or unrelated clothing.
        let totalPixels = max(1, alpha.count)
        var foregroundPixels = 0
        var transparentPixels = 0
        for value in alpha {
            if value >= 176 { foregroundPixels += 1 }
            if value <= 32 { transparentPixels += 1 }
        }
        let foregroundCoverage = Double(foregroundPixels) / Double(totalPixels)
        guard foregroundPixels >= max(24, totalPixels / 30),
              transparentPixels >= max(24, totalPixels / 120),
              foregroundCoverage < 0.975
        else { return nil }

        return foregroundPNG(
            image: cropped,
            alpha: alpha,
            width: targetWidth,
            height: targetHeight
        )
    }

    /// Applies a conventional grayscale alpha plane to an image. `CGImage(maskWidth:...)`
    /// creates a Quartz *image mask*, whose samples are inverted (white masks content out).
    /// The detector produces normal alpha where white means garment, so using that initializer
    /// made some saved PNGs preserve the background and erase the clothes. A regular grayscale
    /// image keeps the detector's alpha semantics intact when used as a clipping mask.
    nonisolated static func foregroundPNG(
        image: CGImage,
        alpha: [UInt8],
        width: Int,
        height: Int
    ) -> Data? {
        guard width > 0,
              height > 0,
              alpha.count == width * height,
              let provider = CGDataProvider(data: Data(alpha) as CFData),
              let alphaImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { return nil }

        let size = CGSize(width: width, height: height)
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.saveGState()
            context.cgContext.clip(to: bounds, mask: alphaImage)
            UIImage(cgImage: image).draw(in: bounds)
            context.cgContext.restoreGState()
        }
        return rendered.pngData()
    }

    private nonisolated static func boundingBoxCrop(
        image: CGImage,
        detection: RawDetection
    ) -> Data? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let rect = CGRect(
            x: detection.box.x * imageWidth,
            y: detection.box.y * imageHeight,
            width: detection.box.width * imageWidth,
            height: detection.box.height * imageHeight
        ).integral.intersection(
            CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        )
        guard rect.width >= 2,
              rect.height >= 2,
              let cropped = image.cropping(to: rect)
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            cropped,
            [
                kCGImageDestinationLossyCompressionQuality: 0.94,
                kCGImagePropertyOrientation: 1,
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Keeps the model's 0-logit decision boundary while preserving a narrow
    /// confidence band for antialiased crop edges.
    private nonisolated static func softMaskAlpha(logit: Double) -> UInt8 {
        let probability = 1 / (1 + Foundation.exp(-logit))
        let normalized = min(1, max(0, (probability - 0.35) / 0.30))
        let smooth = normalized * normalized * (3 - 2 * normalized)
        return UInt8((smooth * 255).rounded())
    }
}
