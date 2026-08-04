import CoreGraphics
import CoreML
import Foundation
import UIKit
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
    }

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
        includeCrops: Bool = true
    ) async throws -> GarmentDetectionBatch {
        guard let source = Self.normalizedImage(from: imageData),
              let cgImage = source.cgImage
        else {
            throw GarmentVisionError.invalidImage
        }
        let itemLimit = min(12, max(1, maxItems))
        let method: GarmentDetectionMethod
        let detections: [RawDetection]
        if let modelURL, let manifest {
            method = .coreML
            detections = try coreMLDetections(
                image: cgImage,
                modelURL: modelURL,
                manifest: manifest,
                maxItems: itemLimit,
                includeMasks: includeCrops
            )
        } else {
            method = .foregroundInstance
            detections = try await foregroundDetections(
                image: cgImage,
                maxItems: itemLimit
            )
        }
        let candidates = detections.map { detection in
            GarmentCandidate(
                id: UUID().uuidString,
                localLabel: detection.label,
                confidence: detection.confidence,
                box: detection.box,
                cropData: includeCrops
                    ? Self.segmentedCrop(image: cgImage, detection: detection)
                    : nil
            )
        }
        return GarmentDetectionBatch(method: method, candidates: candidates)
    }

    func preview(
        imageData: Data,
        modelURL: URL,
        manifest: ModelPackManifestDTO,
        maxItems: Int
    ) async throws -> LiveGarmentPreview {
        guard let source = Self.normalizedImage(from: imageData),
              let image = source.cgImage
        else {
            throw GarmentVisionError.invalidImage
        }
        let detections = try coreMLDetections(
            image: image,
            modelURL: modelURL,
            manifest: manifest,
            maxItems: min(12, max(1, maxItems)),
            includeMasks: false
        )
        let detection = GarmentDetectionBatch(
            method: .coreML,
            candidates: detections.map {
                GarmentCandidate(
                    id: UUID().uuidString,
                    localLabel: $0.label,
                    confidence: $0.confidence,
                    box: $0.box,
                    cropData: nil
                )
            }
        )
        let metrics = Self.frameMetrics(image)
        let largestArea = detection.candidates
            .map { $0.box.width * $0.box.height }
            .max() ?? 0
        let clipped = detection.candidates.contains { candidate in
            candidate.box.x < 0.018
                || candidate.box.y < 0.018
                || candidate.box.x + candidate.box.width > 0.982
                || candidate.box.y + candidate.box.height > 0.982
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
        } else if largestArea < 0.075 {
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

    private func coreMLDetections(
        image: CGImage,
        modelURL: URL,
        manifest: ModelPackManifestDTO,
        maxItems: Int,
        includeMasks: Bool
    ) throws -> [RawDetection] {
        let model = try model(at: modelURL)
        let input = try Self.modelInput(
            image: image,
            resolution: manifest.inputResolution
        )
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [manifest.inputName: MLFeatureValue(multiArray: input)]
        )
        let result = try model.prediction(from: provider)
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
            guard bestConfidence >= 0.35 else { continue }
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

        return selected.map { candidate in
            guard includeMasks else {
                return RawDetection(
                    queryIndex: candidate.query,
                    classID: candidate.classID,
                    label: manifest.classNames[candidate.classID],
                    confidence: candidate.confidence,
                    box: candidate.box,
                    maskWidth: 0,
                    maskHeight: 0,
                    mask: []
                )
            }
            var mask = [UInt8](repeating: 0, count: maskWidth * maskHeight)
            for y in 0..<maskHeight {
                for x in 0..<maskWidth {
                    mask[y * maskWidth + x] = Self.value(
                        masks,
                        [0, candidate.query, y, x]
                    ) > 0 ? 255 : 0
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
                mask: mask
            )
        }
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
                        mask: maskResult.mask
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
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)
        loadedModelURL = url
        loadedModel = model
        return model
    }

    private nonisolated static func normalizedImage(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1_600
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
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
        context.translateBy(x: 0, y: CGFloat(resolution))
        context.scaleBy(x: 1, y: -1)
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
        let means: [Float32] = [0.485, 0.456, 0.406]
        let deviations: [Float32] = [0.229, 0.224, 0.225]
        for y in 0..<resolution {
            for x in 0..<resolution {
                let source = y * bytesPerRow + x * 4
                let destination = y * resolution + x
                for channel in 0..<3 {
                    let value = Float32(pixels[source + channel]) / 255
                    pointer[channel * planeSize + destination] =
                        (value - means[channel]) / deviations[channel]
                }
            }
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
        for y in 0..<targetHeight {
            let sourceY = cropRect.minY + CGFloat(y) / scale
            let maskY = min(
                detection.maskHeight - 1,
                max(0, Int(sourceY / imageHeight * CGFloat(detection.maskHeight)))
            )
            for x in 0..<targetWidth {
                let sourceX = cropRect.minX + CGFloat(x) / scale
                let maskX = min(
                    detection.maskWidth - 1,
                    max(0, Int(sourceX / imageWidth * CGFloat(detection.maskWidth)))
                )
                alpha[y * targetWidth + x] =
                    detection.mask[maskY * detection.maskWidth + maskX]
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
}
