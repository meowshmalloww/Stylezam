import SwiftUI
import UIKit

struct LiveScreenDebugView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "Stream",
                    value: model.liveScreen.isCapturing ? "Active" : "Stopped"
                )
                LabeledContent(
                    "Frames sampled",
                    value: model.liveScreen.receivedFrameCount.formatted()
                )
                LabeledContent(
                    "Model analyses",
                    value: model.liveScreen.analyzedFrameCount.formatted()
                )
                if let lastAnalysisAt = model.liveScreen.lastAnalysisAt {
                    LabeledContent(
                        "Last analysis",
                        value: lastAnalysisAt.formatted(date: .omitted, time: .standard)
                    )
                }
                if let lastDetectionAt = model.liveScreen.lastDetectionAt {
                    LabeledContent(
                        "Last recognition",
                        value: lastDetectionAt.formatted(date: .omitted, time: .standard)
                    )
                }
                Text(model.liveScreen.statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Live pipeline")
            } footer: {
                Text("While Live Screen is active, Stylezam always keeps only the latest authorized frame in memory for inspection. The overlay below shows the exact boxes returned by the local model.")
            }

            if let snapshot = model.liveScreen.latestDebugSnapshot,
                      let image = UIImage(data: snapshot.frameData)
            {
                Section {
                    LiveScreenBoxOverlay(image: image, candidates: snapshot.candidates)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.black)

                    LabeledContent("Stage", value: snapshot.stage)
                    LabeledContent(
                        "Authorized source",
                        value: "\(snapshot.pixelWidth) × \(snapshot.pixelHeight)"
                    )
                    LabeledContent(
                        "Captured",
                        value: snapshot.capturedAt.formatted(date: .omitted, time: .standard)
                    )
                    LabeledContent(
                        "Boxes",
                        value: snapshot.candidates.count.formatted()
                    )
                } header: {
                    Text("Latest analyzed frame")
                }

                if snapshot.candidates.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No garment in this pass",
                            systemImage: "viewfinder",
                            description: Text("The frame reached Core ML, but no Fashionpedia item passed the confidence threshold.")
                        )
                    }
                } else {
                    Section("Recognized crops") {
                        ForEach(Array(snapshot.candidates.enumerated()), id: \.element.id) { index, candidate in
                            let savedCrop = snapshot.savedCropData.indices.contains(index)
                                ? snapshot.savedCropData[index]
                                : nil
                            let crop = savedCrop.flatMap(UIImage.init(data:))
                                ?? liveScreenBoxCrop(from: image, box: candidate.box)
                            LiveScreenDetectedPieceRow(
                                index: index + 1,
                                candidate: candidate,
                                crop: crop,
                                isSavedCrop: savedCrop != nil
                            )
                        }
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        model.liveScreen.isCapturing
                            ? "Waiting for an analyzed frame"
                            : "Start Live Screen",
                        systemImage: "rectangle.on.rectangle",
                        description: Text(
                            model.liveScreen.isCapturing
                                ? "Pause on a fashion item. The first quick analysis should appear here within about one second."
                                : "Choose Share Entire Screen, return to a Reel or product page, and pause briefly."
                        )
                    )
                }
            }
        }
        .navigationTitle("Live Screen Inspector")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LiveScreenBoxOverlay: View {
    let image: UIImage
    let candidates: [GarmentCandidate]

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()

            GeometryReader { proxy in
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    let rect = CGRect(
                        x: candidate.box.x * proxy.size.width,
                        y: candidate.box.y * proxy.size.height,
                        width: candidate.box.width * proxy.size.width,
                        height: candidate.box.height * proxy.size.height
                    )
                    ZStack {
                        Rectangle()
                            .stroke(.white, lineWidth: 2)
                            .background(StylezamDesign.cobalt.opacity(0.12))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        Text("\(index + 1) · \(candidate.localLabel)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(StylezamDesign.cobalt)
                            .position(
                                x: min(proxy.size.width - 60, max(60, rect.minX + 60)),
                                y: max(14, rect.minY + 12)
                            )
                    }
                }
            }
        }
        .aspectRatio(max(0.1, image.size.width / max(1, image.size.height)), contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Authorized screen with \(candidates.count) real model boxes")
    }
}

private struct LiveScreenDetectedPieceRow: View {
    let index: Int
    let candidate: GarmentCandidate
    let crop: UIImage?
    let isSavedCrop: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index). \(candidate.localLabel)")
                    .font(.headline)
                Spacer()
                Text(candidate.confidence, format: .percent.precision(.fractionLength(1)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let crop {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    Image(uiImage: crop)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text(isSavedCrop ? "Saved full-resolution crop" : "Preview from the detected box")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                "x \(coordinate(candidate.box.x)) · y \(coordinate(candidate.box.y)) · "
                    + "w \(coordinate(candidate.box.width)) · h \(coordinate(candidate.box.height))"
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .padding(.vertical, 6)
    }

    private func coordinate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4)))
    }
}

private func liveScreenBoxCrop(from image: UIImage, box: BoundingBoxDTO) -> UIImage? {
    guard let source = image.cgImage else { return nil }
    let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
    let rect = CGRect(
        x: box.x * Double(source.width),
        y: box.y * Double(source.height),
        width: box.width * Double(source.width),
        height: box.height * Double(source.height)
    ).integral.intersection(bounds)
    guard rect.width >= 2,
          rect.height >= 2,
          let cropped = source.cropping(to: rect)
    else { return nil }
    return UIImage(cgImage: cropped, scale: 1, orientation: .up)
}
