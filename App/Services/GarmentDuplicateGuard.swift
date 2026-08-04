import CoreGraphics
import Foundation
import UIKit

actor GarmentDuplicateGuard {
    private struct Entry: Sendable {
        let label: String
        let fingerprint: UInt64
        let createdAt: Date
    }

    private var entries: [Entry] = []
    private var seededKeys: Set<String> = []
    private let retention: TimeInterval = 20 * 60
    private let maximumEntries = 80
    private let maximumHammingDistance = 6

    func novelCandidates(
        _ candidates: [GarmentCandidate],
        history: [GarmentFingerprintSource]
    ) -> [GarmentCandidate] {
        let cutoff = Date.now.addingTimeInterval(-retention)
        entries.removeAll { $0.createdAt < cutoff }

        for source in history where source.createdAt >= cutoff {
            guard let fingerprint = Self.differenceHash(source.data) else { continue }
            let seedKey = "\(source.createdAt.timeIntervalSince1970)-\(source.label)-\(fingerprint)"
            guard seededKeys.insert(seedKey).inserted else { continue }
            entries.append(
                Entry(
                    label: Self.canonicalLabel(source.label),
                    fingerprint: fingerprint,
                    createdAt: source.createdAt
                )
            )
        }

        var accepted: [(candidate: GarmentCandidate, fingerprint: UInt64)] = []
        for candidate in candidates {
            guard let crop = candidate.cropData,
                  let fingerprint = Self.differenceHash(crop)
            else {
                accepted.append((candidate, 0))
                continue
            }
            let label = Self.canonicalLabel(candidate.localLabel)
            let duplicate = entries.contains { entry in
                entry.label == label
                    && (entry.fingerprint ^ fingerprint).nonzeroBitCount
                        <= maximumHammingDistance
            }
            if !duplicate {
                accepted.append((candidate, fingerprint))
            }
        }

        let now = Date.now
        for value in accepted where value.fingerprint != 0 {
            entries.append(
                Entry(
                    label: Self.canonicalLabel(value.candidate.localLabel),
                    fingerprint: value.fingerprint,
                    createdAt: now
                )
            )
        }
        if entries.count > maximumEntries {
            entries = Array(entries.suffix(maximumEntries))
        }
        return accepted.map(\.candidate)
    }

    private nonisolated static func canonicalLabel(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
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
