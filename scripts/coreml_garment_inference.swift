import CoreGraphics
import CoreML
import Foundation
import ImageIO

private struct Manifest: Decodable {
    let modelID: String
    let version: String
    let inputName: String
    let inputResolution: Int
    let boxOutputName: String
    let logitOutputName: String
    let maskOutputName: String
    let classNames: [String]
}

private struct Box: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct Detection: Codable {
    let query: Int
    let categoryID: Int
    let label: String
    let confidence: Double
    let box: Box
    let maskWidth: Int
    let maskHeight: Int
    let maskBase64: String
}

private struct ImageResult: Codable {
    let path: String
    let width: Int
    let height: Int
    let preprocessingMilliseconds: Double
    let inferenceMilliseconds: [Double]
    let detections: [Detection]
}

private struct Report: Codable {
    let modelID: String
    let modelVersion: String
    let inputResolution: Int
    let threshold: Double
    let maxItems: Int
    let images: [ImageResult]
}

private struct ScoredDetection {
    let query: Int
    let categoryID: Int
    let confidence: Double
    let box: Box
}

private enum RunnerError: LocalizedError {
    case missingArgument(String)
    case invalidArgument(String)
    case unreadableImage(String)
    case invalidModelOutput(String)

    var errorDescription: String? {
        switch self {
        case let .missingArgument(value): "Missing required argument: \(value)"
        case let .invalidArgument(value): "Invalid argument: \(value)"
        case let .unreadableImage(value): "Could not decode image: \(value)"
        case let .invalidModelOutput(value): "Invalid Core ML output: \(value)"
        }
    }
}

@main
private enum CoreMLGarmentInference {
    static func main() throws {
        let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
        let manifestData = try Data(contentsOf: options.manifest)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.classNames.count == 46 else {
            throw RunnerError.invalidArgument("manifest must contain 46 Fashionpedia classes")
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: options.model, configuration: configuration)
        var imageResults: [ImageResult] = []

        for imageURL in options.images {
            let preprocessingStarted = CFAbsoluteTimeGetCurrent()
            let image = try loadImage(at: imageURL)
            let input = try modelInput(image: image, resolution: manifest.inputResolution)
            let provider = try MLDictionaryFeatureProvider(
                dictionary: [manifest.inputName: MLFeatureValue(multiArray: input)]
            )
            let preprocessingMilliseconds =
                (CFAbsoluteTimeGetCurrent() - preprocessingStarted) * 1_000

            var prediction: MLFeatureProvider?
            var timings: [Double] = []
            for _ in 0..<options.runs {
                let started = CFAbsoluteTimeGetCurrent()
                prediction = try model.prediction(from: provider)
                timings.append((CFAbsoluteTimeGetCurrent() - started) * 1_000)
            }
            guard let prediction else {
                throw RunnerError.invalidModelOutput("prediction was not produced")
            }
            let detections = try decode(
                prediction: prediction,
                manifest: manifest,
                threshold: options.threshold,
                maxItems: options.maxItems
            )
            imageResults.append(
                ImageResult(
                    path: imageURL.path,
                    width: image.width,
                    height: image.height,
                    preprocessingMilliseconds: preprocessingMilliseconds,
                    inferenceMilliseconds: timings,
                    detections: detections
                )
            )
        }

        let report = Report(
            modelID: manifest.modelID,
            modelVersion: manifest.version,
            inputResolution: manifest.inputResolution,
            threshold: options.threshold,
            maxItems: options.maxItems,
            images: imageResults
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: options.output, options: .atomic)
    }

    private struct Options {
        let model: URL
        let manifest: URL
        let output: URL
        let threshold: Double
        let maxItems: Int
        let runs: Int
        let images: [URL]
    }

    private static func parseArguments(_ arguments: [String]) throws -> Options {
        var values: [String: String] = [:]
        var images: [URL] = []
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard index + 1 < arguments.count else {
                throw RunnerError.missingArgument(key)
            }
            let value = arguments[index + 1]
            if key == "--image" {
                images.append(URL(fileURLWithPath: value))
            } else {
                values[key] = value
            }
            index += 2
        }
        guard let model = values["--model"] else {
            throw RunnerError.missingArgument("--model")
        }
        guard let manifest = values["--manifest"] else {
            throw RunnerError.missingArgument("--manifest")
        }
        guard let output = values["--output"] else {
            throw RunnerError.missingArgument("--output")
        }
        guard !images.isEmpty else {
            throw RunnerError.missingArgument("at least one --image")
        }
        let threshold = Double(values["--threshold"] ?? "0.35") ?? -1
        let maxItems = Int(values["--max-items"] ?? "5") ?? 0
        let runs = Int(values["--runs"] ?? "2") ?? 0
        guard (0...1).contains(threshold), (1...12).contains(maxItems), (1...20).contains(runs) else {
            throw RunnerError.invalidArgument("threshold, max-items, or runs")
        }
        return Options(
            model: URL(fileURLWithPath: model),
            manifest: URL(fileURLWithPath: manifest),
            output: URL(fileURLWithPath: output),
            threshold: threshold,
            maxItems: maxItems,
            runs: runs,
            images: images
        )
    }

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1_600,
                  ] as CFDictionary
              )
        else {
            throw RunnerError.unreadableImage(url.path)
        }
        return image
    }

    private static func modelInput(image: CGImage, resolution: Int) throws -> MLMultiArray {
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
            throw RunnerError.unreadableImage("could not allocate RGB context")
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: resolution, height: resolution))

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

    private static func decode(
        prediction: MLFeatureProvider,
        manifest: Manifest,
        threshold: Double,
        maxItems: Int
    ) throws -> [Detection] {
        guard let boxes = prediction.featureValue(for: manifest.boxOutputName)?.multiArrayValue,
              let logits = prediction.featureValue(for: manifest.logitOutputName)?.multiArrayValue,
              let masks = prediction.featureValue(for: manifest.maskOutputName)?.multiArrayValue,
              boxes.shape.count == 3,
              logits.shape.count == 3,
              masks.shape.count == 4
        else {
            throw RunnerError.invalidModelOutput("missing boxes, logits, or masks")
        }
        let queryCount = boxes.shape[1].intValue
        let classCount = logits.shape[2].intValue
        let maskHeight = masks.shape[2].intValue
        let maskWidth = masks.shape[3].intValue
        let searchableClassCount = min(27, min(classCount, manifest.classNames.count))
        var scored: [ScoredDetection] = []

        for query in 0..<queryCount {
            var bestClass = 0
            var bestConfidence = 0.0
            for categoryID in 0..<searchableClassCount {
                let logit = value(logits, [0, query, categoryID])
                let confidence = 1 / (1 + Foundation.exp(-logit))
                if confidence > bestConfidence {
                    bestClass = categoryID
                    bestConfidence = confidence
                }
            }
            guard bestConfidence >= threshold else { continue }
            let centerX = value(boxes, [0, query, 0])
            let centerY = value(boxes, [0, query, 1])
            let width = value(boxes, [0, query, 2])
            let height = value(boxes, [0, query, 3])
            let left = max(0, centerX - width / 2)
            let top = max(0, centerY - height / 2)
            let right = min(1, centerX + width / 2)
            let bottom = min(1, centerY + height / 2)
            guard right - left >= 0.025, bottom - top >= 0.025 else { continue }
            scored.append(
                ScoredDetection(
                    query: query,
                    categoryID: bestClass,
                    confidence: bestConfidence,
                    box: Box(x: left, y: top, width: right - left, height: bottom - top)
                )
            )
        }
        scored.sort { $0.confidence > $1.confidence }
        var selected: [ScoredDetection] = []
        for candidate in scored {
            let duplicate = selected.contains {
                $0.categoryID == candidate.categoryID && iou($0.box, candidate.box) > 0.74
            }
            if !duplicate { selected.append(candidate) }
            if selected.count == maxItems { break }
        }

        return selected.map { candidate in
            var mask = [UInt8](repeating: 0, count: maskWidth * maskHeight)
            for y in 0..<maskHeight {
                for x in 0..<maskWidth {
                    mask[y * maskWidth + x] = softMaskAlpha(
                        logit: value(masks, [0, candidate.query, y, x])
                    )
                }
            }
            return Detection(
                query: candidate.query,
                categoryID: candidate.categoryID,
                label: manifest.classNames[candidate.categoryID],
                confidence: candidate.confidence,
                box: candidate.box,
                maskWidth: maskWidth,
                maskHeight: maskHeight,
                maskBase64: Data(mask).base64EncodedString()
            )
        }
    }

    private static func value(_ array: MLMultiArray, _ indexes: [Int]) -> Double {
        array[indexes.map(NSNumber.init(value:))].doubleValue
    }

    private static func softMaskAlpha(logit: Double) -> UInt8 {
        let probability = 1 / (1 + Foundation.exp(-logit))
        let normalized = min(1, max(0, (probability - 0.35) / 0.30))
        let smooth = normalized * normalized * (3 - 2 * normalized)
        return UInt8((smooth * 255).rounded())
    }

    private static func iou(_ left: Box, _ right: Box) -> Double {
        let x1 = max(left.x, right.x)
        let y1 = max(left.y, right.y)
        let x2 = min(left.x + left.width, right.x + right.width)
        let y2 = min(left.y + left.height, right.y + right.height)
        let intersection = max(0, x2 - x1) * max(0, y2 - y1)
        guard intersection > 0 else { return 0 }
        return intersection /
            (left.width * left.height + right.width * right.height - intersection)
    }
}
