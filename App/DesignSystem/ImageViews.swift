import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private actor StylezamImagePipeline {
    static let shared = StylezamImagePipeline()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()

    func image(data: Data, key: String, maxPixelSize: Int = 2_200) async -> UIImage? {
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.downsample(data: data, maxPixelSize: maxPixelSize)
        }.value
        if let decoded {
            cache.setObject(decoded, forKey: cacheKey, cost: Self.cost(of: decoded))
        }
        return decoded
    }

    func image(fileURL: URL, maxPixelSize: Int = 2_200) async -> UIImage? {
        let key = "file:\(fileURL.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
                return nil as UIImage?
            }
            return Self.downsample(data: data, maxPixelSize: maxPixelSize)
        }.value
        if let decoded {
            cache.setObject(decoded, forKey: key, cost: Self.cost(of: decoded))
        }
        return decoded
    }

    func image(remoteURL: URL, maxPixelSize: Int = 1_600) async -> UIImage? {
        let key = "remote:\(remoteURL.absoluteString)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            return nil
        }
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.downsample(data: data, maxPixelSize: maxPixelSize)
        }.value
        if let decoded {
            cache.setObject(decoded, forKey: key, cost: Self.cost(of: decoded))
        }
        return decoded
    }

    private nonisolated static func downsample(data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }

    private nonisolated static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

private func dataIdentity(_ data: Data) -> String {
    var hasher = Hasher()
    hasher.combine(data.count)
    hasher.combine(data.prefix(64))
    hasher.combine(data.suffix(64))
    return "data:\(hasher.finalize())"
}

struct DataImage: View {
    let data: Data
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    private var identity: String { dataIdentity(data) }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                imagePlaceholder
            }
        }
        .task(id: identity) {
            image = nil
            image = await StylezamImagePipeline.shared.image(data: data, key: identity)
        }
    }
}

struct LocalFileImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                imagePlaceholder
            }
        }
        .task(id: url) {
            image = nil
            image = await StylezamImagePipeline.shared.image(fileURL: url)
        }
    }
}

struct ProductImage: View {
    let url: URL?
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if didFail {
                imagePlaceholder
            } else {
                Color(uiColor: .secondarySystemBackground)
                    .overlay { ProgressView() }
            }
        }
        .task(id: url) {
            image = nil
            didFail = false
            guard let url else {
                didFail = true
                return
            }
            image = await StylezamImagePipeline.shared.image(remoteURL: url)
            didFail = image == nil
        }
    }
}

private var imagePlaceholder: some View {
    Color(uiColor: .secondarySystemBackground)
        .overlay {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
}

enum ImageEncoding {
    static func normalizedJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any]
        else { return nil }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
           max(width, height) <= 5_120,
           orientation == 1
        {
            // AVCapturePhoto commonly already returns an upright, high-quality JPEG. Avoiding a
            // full decode/render/re-encode saves latency, memory bandwidth, and heat while also
            // preserving the camera's original detail.
            return data
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 5_120,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        ) else { return nil }
        return encodeJPEG(image)
    }

    static func normalizedJPEGAsync(from data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            normalizedJPEG(from: data)
        }.value
    }

    static func normalizedJPEG(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 5_120
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.92)
    }

    private static func encodeJPEG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImageDestinationLossyCompressionQuality: 0.92,
                kCGImagePropertyOrientation: 1,
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
