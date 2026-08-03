import SwiftUI
import UIKit

struct DataImage: View {
    let data: Data
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Color(uiColor: .secondarySystemBackground)
                .overlay {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

struct LocalFileImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Color(uiColor: .secondarySystemBackground)
        }
    }
}

struct ProductImage: View {
    let url: URL?
    var contentMode: ContentMode = .fit

    var body: some View {
        AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            case .failure:
                Color(uiColor: .secondarySystemBackground)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
            case .empty:
                Color(uiColor: .secondarySystemBackground)
                    .overlay { ProgressView() }
            @unknown default:
                Color(uiColor: .secondarySystemBackground)
            }
        }
    }
}

enum ImageEncoding {
    static func normalizedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return normalizedJPEG(from: image)
    }

    static func normalizedJPEG(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 4096
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
}

