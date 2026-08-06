import CoreGraphics
import Foundation
import ImageIO

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

    private let requiredHits = 3
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

    /// Returns `true` only after a good garment remains stable for three analyzed frames.
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

        guard let track,
              track.consecutiveHits >= requiredHits,
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
