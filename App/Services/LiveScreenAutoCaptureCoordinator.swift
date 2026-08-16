import CoreGraphics
import Foundation
import ImageIO

enum LiveScreenAnalysisStrategy: Equatable, Sendable {
    case global
    case adaptive
    case focused
}

enum LiveScreenAnalysisPlanner {
    static func strategy(
        contentIsStable: Bool,
        stableFrameCount: Int,
        hasFocus: Bool
    ) -> LiveScreenAnalysisStrategy {
        // A focused pass is cheap confirmation for the current item, but a static Reel or
        // product page can show several pieces. Return to full-screen detail discovery every
        // third stable sample so the first anchor never hides the rest of the outfit.
        if contentIsStable, hasFocus, stableFrameCount.isMultiple(of: 3) {
            return .adaptive
        }
        if contentIsStable, hasFocus {
            return .focused
        }
        if contentIsStable, stableFrameCount >= 2 {
            return .adaptive
        }
        return .global
    }
}

/// Temporal and perceptual gating for automatic Live Screen captures.
///
/// ScreenCaptureKit can deliver a large number of visually identical frames while a product
/// page is stationary. Requiring spatial, label, and perceptual agreement across several
/// observations avoids saving transient UI and prevents a static garment from repeatedly running
/// the full-resolution detector.
struct LiveScreenAutoCaptureCoordinator: Sendable {
    struct Candidate: Sendable {
        let label: String
        let confidence: Double
        let box: BoundingBoxDTO
        let fingerprint: UInt64
    }

    private struct Track: Sendable {
        var candidate: Candidate
        var consecutiveHits: Int
    }

    private struct CapturedFingerprint: Sendable {
        let value: UInt64
        let capturedAt: Date
    }

    private var track: Track?
    private var capturedFingerprints: [CapturedFingerprint] = []
    private var lastAttemptAt = Date.distantPast

    // Two independent detections are enough after the model, confidence, area, quality, label,
    // box-IoU, and garment-region perceptual checks all agree. At the active 0.85-second screen
    // cadence this makes a two-second pause useful instead of requiring five or more seconds.
    private let requiredHits = 2
    private let minimumConfidence = 0.44
    private let minimumArea = 0.004
    private let minimumQuality = 0.34
    private let attemptCooldown: TimeInterval = 7
    private let duplicateRetention: TimeInterval = 20 * 60

    mutating func reset(keepCapturedFingerprints: Bool = true) {
        track = nil
        if !keepCapturedFingerprints {
            capturedFingerprints = []
            lastAttemptAt = .distantPast
        }
    }

    /// Returns `true` only after a good garment remains stable for two analyzed frames.
    mutating func shouldCapture(
        _ candidate: Candidate,
        qualityScore: Double,
        now: Date = .now
    ) -> Bool {
        let retention = duplicateRetention
        capturedFingerprints.removeAll {
            now.timeIntervalSince($0.capturedAt) > retention
        }

        let area = candidate.box.width * candidate.box.height
        guard candidate.confidence >= minimumConfidence,
              area >= minimumArea,
              qualityScore >= minimumQuality
        else {
            track = nil
            return false
        }

        if let current = track,
           Self.canonicalLabel(current.candidate.label) == Self.canonicalLabel(candidate.label),
           Self.intersectionOverUnion(current.candidate.box, candidate.box) >= 0.42,
           Self.hammingDistance(current.candidate.fingerprint, candidate.fingerprint) <= 12
        {
            track = Track(
                candidate: Candidate(
                    label: candidate.label,
                    confidence: max(current.candidate.confidence, candidate.confidence),
                    box: Self.smoothedBox(current.candidate.box, candidate.box),
                    fingerprint: candidate.fingerprint
                ),
                consecutiveHits: current.consecutiveHits + 1
            )
        } else {
            track = Track(candidate: candidate, consecutiveHits: 1)
        }

        // A very clear product frame may be captured immediately so a playing video does not
        // have to pause on the exact same frame twice. Ambiguous detections still use the normal
        // two-frame confirmation path, which protects accuracy and false-positive rejection.
        let highConfidenceMovingFrame = candidate.confidence >= 0.90
            && qualityScore >= 0.60
            && area >= 0.03
        guard let track,
              (track.consecutiveHits >= requiredHits || highConfidenceMovingFrame),
              now.timeIntervalSince(lastAttemptAt) >= attemptCooldown,
              !capturedFingerprints.contains(where: {
                  Self.hammingDistance($0.value, track.candidate.fingerprint) <= 7
              })
        else { return false }

        lastAttemptAt = now
        return true
    }

    /// Remembers successful and duplicate-filtered captures, but allows a failed inference to
    /// retry after the normal cooldown.
    mutating func recordCaptureResult(
        fingerprint: UInt64,
        shouldSuppressRepeat: Bool,
        now: Date = .now
    ) {
        if shouldSuppressRepeat {
            capturedFingerprints.append(
                CapturedFingerprint(value: fingerprint, capturedAt: now)
            )
            if capturedFingerprints.count > 40 {
                capturedFingerprints.removeFirst(capturedFingerprints.count - 40)
            }
        }
        track = nil
    }

    private static func canonicalLabel(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func hammingDistance(_ left: UInt64, _ right: UInt64) -> Int {
        (left ^ right).nonzeroBitCount
    }

    private static func smoothedBox(
        _ previous: BoundingBoxDTO,
        _ current: BoundingBoxDTO
    ) -> BoundingBoxDTO {
        let currentWeight = 0.6
        let previousWeight = 1 - currentWeight
        return BoundingBoxDTO(
            x: previous.x * previousWeight + current.x * currentWeight,
            y: previous.y * previousWeight + current.y * currentWeight,
            width: previous.width * previousWeight + current.width * currentWeight,
            height: previous.height * previousWeight + current.height * currentWeight
        )
    }

    private static func intersectionOverUnion(
        _ left: BoundingBoxDTO,
        _ right: BoundingBoxDTO
    ) -> Double {
        let width = max(
            0,
            min(left.x + left.width, right.x + right.width) - max(left.x, right.x)
        )
        let height = max(
            0,
            min(left.y + left.height, right.y + right.height) - max(left.y, right.y)
        )
        let intersection = width * height
        guard intersection > 0 else { return 0 }
        let union = left.width * left.height + right.width * right.height - intersection
        return union > 0 ? intersection / union : 0
    }
}

/// A tiny perceptual hash of the detected source region. The source is decoded as a bounded
/// thumbnail, so this check does not duplicate the full-resolution detector's memory cost.
enum LiveScreenPerceptualHash {
    static func differenceHash(
        imageData: Data,
        region: BoundingBoxDTO
    ) -> UInt64? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 640,
                      kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary
              )
        else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let regionRect = CGRect(
            x: region.x * Double(image.width),
            y: region.y * Double(image.height),
            width: region.width * Double(image.width),
            height: region.height * Double(image.height)
        ).integral.intersection(bounds)
        guard regionRect.width >= 2,
              regionRect.height >= 2,
              let cropped = image.cropping(to: regionRect)
        else { return nil }

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
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

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

/// A low-resolution signature of the whole authorized display. It is intentionally much cheaper
/// than Core ML and lets the app decide when a paused page deserves detail discovery, then stop
/// repeating ML work while the same captured or known-empty page remains visible.
struct LiveScreenContentFingerprint: Sendable, Equatable {
    private let values: [UInt64]

    static func make(imageData: Data) -> LiveScreenContentFingerprint? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 480,
                      kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary
              )
        else { return nil }

        let width = Double(image.width)
        let height = Double(image.height)
        // System status indicators and app/browser toolbars can animate while the actual product
        // view is motionless. Exclude only those outer chrome bands so they cannot keep resetting
        // content comparison; the central 80%+ of the authorized screen remains represented.
        let content: CGRect
        if height >= width {
            content = CGRect(
                x: width * 0.02,
                y: height * 0.065,
                width: width * 0.96,
                height: height * 0.82
            )
        } else {
            content = CGRect(
                x: width * 0.06,
                y: height * 0.04,
                width: width * 0.88,
                height: height * 0.90
            )
        }
        var regions = [content]
        if height >= width {
            regions.append(contentsOf: (0..<3).map { index in
                CGRect(
                    x: content.minX,
                    y: content.minY + content.height * Double(index) / 3,
                    width: content.width,
                    height: content.height / 3
                )
            })
        } else {
            regions.append(contentsOf: (0..<3).map { index in
                CGRect(
                    x: content.minX + content.width * Double(index) / 3,
                    y: content.minY,
                    width: content.width / 3,
                    height: content.height
                )
            })
        }
        let values = regions.compactMap { region -> UInt64? in
            guard let cropped = image.cropping(to: region.integral) else { return nil }
            return differenceHash(image: cropped)
        }
        guard values.count == regions.count else { return nil }
        return LiveScreenContentFingerprint(values: values)
    }

    func isVisuallySimilar(to other: LiveScreenContentFingerprint) -> Bool {
        guard !values.isEmpty, values.count == other.values.count else { return false }
        let fullDistance = (values[0] ^ other.values[0]).nonzeroBitCount
        let distances = zip(values.dropFirst(), other.values.dropFirst()).map {
            ($0 ^ $1).nonzeroBitCount
        }
        return fullDistance <= 7
            && distances.allSatisfy { $0 <= 11 }
            && distances.reduce(0, +) <= 24
    }

    private static func differenceHash(image: CGImage) -> UInt64? {
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
        context.interpolationQuality = .medium
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

/// Backs off repeated Live-camera inference only after the same view has produced two empty
/// results. A visual change or any garment candidate returns to the normal fast cadence.
struct LiveContentInferenceGate: Sendable {
    private var lastFingerprint: LiveScreenContentFingerprint?
    private var consecutiveEmptyResults = 0
    private var lastEmptyAnalysisAt = Date.distantPast
    private let emptyRetryInterval: TimeInterval = 2.4

    mutating func shouldAnalyze(
        fingerprint: LiveScreenContentFingerprint,
        now: Date = .now
    ) -> Bool {
        let contentChanged = lastFingerprint.map {
            !fingerprint.isVisuallySimilar(to: $0)
        } ?? true
        lastFingerprint = fingerprint
        if contentChanged {
            consecutiveEmptyResults = 0
            return true
        }
        return consecutiveEmptyResults < 2
            || now.timeIntervalSince(lastEmptyAnalysisAt) >= emptyRetryInterval
    }

    mutating func recordResult(hasCandidates: Bool, now: Date = .now) {
        if hasCandidates {
            consecutiveEmptyResults = 0
        } else {
            consecutiveEmptyResults += 1
            lastEmptyAnalysisAt = now
        }
    }

    mutating func reset() {
        lastFingerprint = nil
        consecutiveEmptyResults = 0
        lastEmptyAnalysisAt = .distantPast
    }
}
