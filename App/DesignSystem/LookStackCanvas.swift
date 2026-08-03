import SwiftUI
import UIKit

struct LookStackCanvas: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashPhase: CGFloat = 0

    let imageData: Data?
    let remoteURL: URL?
    let items: [DetectedItemDTO]
    var selectedRegion: BoundingBoxDTO?
    var onSelect: ((DetectedItemDTO) -> Void)?

    private var imageSize: CGSize? {
        imageData.flatMap(UIImage.init(data:))?.size
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let imageData {
                    DataImage(data: imageData, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProductImage(url: remoteURL, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let imageSize {
                    let imageRect = aspectFitRect(imageSize: imageSize, canvas: geometry.size)
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        detectionBox(item, index: index, imageRect: imageRect)
                    }
                }
            }
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(items.isEmpty ? "Captured look" : "Captured look with \(items.count) detected items")
        .onAppear {
            guard !reduceMotion, !items.isEmpty else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                dashPhase = 26
            }
        }
        .sensoryFeedback(.selection, trigger: selectedRegion)
    }

    private func detectionBox(
        _ item: DetectedItemDTO,
        index: Int,
        imageRect: CGRect
    ) -> some View {
        let rect = CGRect(
            x: imageRect.minX + item.box.x * imageRect.width,
            y: imageRect.minY + item.box.y * imageRect.height,
            width: item.box.width * imageRect.width,
            height: item.box.height * imageRect.height
        )
        let isSelected = selectedRegion == item.box

        return Button {
            onSelect?(item)
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? StylezamDesign.cobalt : .white,
                        style: StrokeStyle(
                            lineWidth: isSelected ? 4 : 2,
                            dash: [8, 5],
                            dashPhase: reduceMotion ? 0 : dashPhase
                        )
                    )
                    .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                HStack(spacing: 6) {
                    Text(String(format: "%02d", index + 1))
                        .font(.caption2.monospacedDigit().weight(.black))
                    Text(item.label.uppercased())
                        .font(.caption2.weight(.black))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(7)
            }
            .frame(width: max(rect.width, 56), height: max(rect.height, 56))
            .scaleEffect(isSelected ? 1.025 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
        .motionReveal(delay: Double(index) * 0.055, distance: 8)
        .animation(StylezamMotion.quickSpring, value: isSelected)
        .disabled(onSelect == nil)
        .accessibilityLabel("Search \(item.label)")
        .accessibilityHint("Runs a new search focused on this item")
    }

    private func aspectFitRect(imageSize: CGSize, canvas: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let scale = min(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (canvas.width - fitted.width) / 2,
            y: (canvas.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
