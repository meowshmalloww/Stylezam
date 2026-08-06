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

    private static let acceptedCaptureBudgetMilliseconds = 9_000.0
    private static let cropReserveMilliseconds = 750.0

    private var loadedModelURL: URL?
    private var loadedModel: MLModel?

    func prepare(modelURL: URL) throws {
        _ = try model(at: modelURL)
    }

    func analyze(
        imageData: Data,
        modelURL: URL?,
        manifest: ModelPackManifestDTO?,
        maxItems: Int,
        includeCrops: Bool = true,
        includeDiagnosticMasks: Bool = false,
        enableAdaptiveDetail: Bool = true
    ) async throws -> GarmentDetectionBatch {
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
                maxItems: max(itemLimit, 8),
                includeMasks: includeCrops && includeDiagnosticMasks
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
                    maxItems: max(itemLimit, 8),
                    includeMasks: includeCrops && includeDiagnosticMasks
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

            detections = Self.mergedDetections(combined, maxItems: itemLimit)
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
                maxItems: itemLimit
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
        let cropStarted = Self.now
        let candidates = detections.map { detection in
            autoreleasepool {
                GarmentCandidate(
                    id: UUID().uuidString,
                    localLabel: detection.label,
                    confidence: detection.confidence,
                    box: detection.box,
                    boxCropData: includeCrops
                        ? Self.boundingBoxCrop(image: cgImage, detection: detection)
                        : nil,
                    cropData: includeCrops
                        && includeDiagnosticMasks
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
        let detections: [RawDetection]
        if let acceptedFocus {
            detections = rawDetections.compactMap {
                Self.remapTileDetection($0, from: acceptedFocus)
            }
        } else {
            detections = rawDetections
        }
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
            enableAdaptiveDetail: true
        )
        let candidates = detection.candidates
        let largestArea = candidates
            .map { max(0, $0.box.width * $0.box.height) }
            .max() ?? 0
        let meanConfidence = candidates.isEmpty
            ? 0
            : candidates.map(\.confidence).reduce(0, +) / Double(candidates.count)
        // Stability across three frames is the primary false-positive guard. Keep this quality
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
        guard let provider = CGDataProvider(data: Data(alpha) as CFData),
              let mask = CGImage(
                  maskWidth: targetWidth,
                  height: targetHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  bytesPerRow: targetWidth,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true
              )
        else { return nil }

        let size = CGSize(width: targetWidth, height: targetHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            context.cgContext.saveGState()
            context.cgContext.clip(to: bounds, mask: mask)
            UIImage(cgImage: cropped).draw(in: bounds)
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
