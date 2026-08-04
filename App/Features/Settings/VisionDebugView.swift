import PhotosUI
import SwiftUI
import UIKit

struct VisionDebugView: View {
    @Environment(AppModel.self) private var model

    @State private var photoItem: PhotosPickerItem?
    @State private var sourceData: Data?
    @State private var sourceName: String?
    @State private var detection: GarmentDetectionBatch?
    @State private var elapsedMilliseconds: Double?
    @State private var errorMessage: String?
    @State private var isInspecting = false
    @State private var copiedReport = false
    @State private var inspectionID = UUID()

    var body: some View {
        List {
            sourceSection

            if let sourceImage {
                Section("Detected regions") {
                    VisionSourceDebugPreview(
                        image: sourceImage,
                        candidates: detection?.candidates ?? []
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.black)
                }
            }

            if sourceData != nil {
                pipelineSection
            }

            if let errorMessage {
                Section("Local detector error") {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            if let candidates = detection?.candidates, !candidates.isEmpty {
                controlsSection(candidates: candidates)
                piecesSection(candidates: candidates)
                diagnosticsSection(candidates: candidates)
            } else if detection != nil, !isInspecting {
                Section {
                    ContentUnavailableView(
                        "No pieces detected",
                        systemImage: "viewfinder",
                        description: Text("Try a clearer photo with the complete garment visible, then run the detector again.")
                    )
                }
            }
        }
        .navigationTitle("Vision Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .sensoryFeedback(.success, trigger: copiedReport)
    }

    private var sourceSection: some View {
        Section {
            Text("This view runs the production detector and crop generator without saving to Library. It never inserts sample results.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose a test photo", systemImage: "photo.on.rectangle")
            }

            if let latestScan = model.library.scans.first {
                Button {
                    Task { await loadLatestScan(latestScan) }
                } label: {
                    Label("Use latest Library capture", systemImage: "clock.arrow.circlepath")
                }
            }

            if let sourceName {
                LabeledContent("Input", value: sourceName)
                    .font(.subheadline)
            }
        } header: {
            Text("Test image")
        } footer: {
            Text("The photo and generated crops stay inside this local inspection and are not uploaded.")
        }
    }

    private var pipelineSection: some View {
        Section("Pipeline state") {
            debugValue(
                "Detector",
                value: detectorName,
                symbol: detection?.method == .coreML ? "cpu" : "person.crop.rectangle"
            )
            debugValue(
                "Model pack",
                value: model.modelPack.status.shortLabel,
                symbol: model.modelPack.isInstalled ? "checkmark.seal" : "arrow.down.circle"
            )
            if let manifest = model.modelPack.manifest {
                debugValue(
                    "Model",
                    value: "\(manifest.modelID) · \(manifest.version)",
                    symbol: "shippingbox"
                )
            }
            debugValue(
                "Pieces",
                value: "\(detection?.candidates.count ?? 0) / \(model.settings.maxDetectedItems)",
                symbol: "square.stack.3d.up"
            )
            debugValue(
                "Transparent crops",
                value: cropCountDescription,
                symbol: "scissors"
            )
            debugValue(
                "Local time",
                value: elapsedMilliseconds.map { "\($0.formatted(.number.precision(.fractionLength(1)))) ms" }
                    ?? (isInspecting ? "Running" : "Not run"),
                symbol: "timer"
            )

            if isInspecting {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running on-device detection and segmentation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func controlsSection(candidates: [GarmentCandidate]) -> some View {
        Section {
            Button {
                Task { await runInspection() }
            } label: {
                Label("Run local detector again", systemImage: "arrow.clockwise")
            }
            .disabled(isInspecting)
        } header: {
            Text("Local rerun")
        } footer: {
            Text("This reruns the bundled Core ML model and crop generator. It does not save the inspection to Library.")
        }
    }

    private func piecesSection(candidates: [GarmentCandidate]) -> some View {
        Section {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                VisionCandidateDebugRow(
                    index: index + 1,
                    candidate: candidate
                )
            }
        } header: {
            Text("Segmented pieces")
        } footer: {
            Text("Each crop is drawn across white and black so bad mask edges, missing regions, and transparent backgrounds are easy to see.")
        }
    }

    private func diagnosticsSection(candidates: [GarmentCandidate]) -> some View {
        Section("Diagnostics") {
            Button {
                UIPasteboard.general.string = diagnosticReport(candidates: candidates)
                copiedReport.toggle()
            } label: {
                Label(
                    copiedReport ? "Diagnostic report copied" : "Copy diagnostic report",
                    systemImage: copiedReport ? "checkmark" : "doc.on.doc"
                )
            }

            Text("The report contains model state, timings, item IDs, confidences, boxes, and crop byte counts. It does not include image bytes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sourceImage: UIImage? {
        sourceData.flatMap(UIImage.init(data:))
    }

    private var detectorName: String {
        if isInspecting { return "Running" }
        return switch detection?.method {
        case .coreML: "Core ML garment segmentation"
        case .foregroundInstance: "Apple foreground fallback"
        case nil: "Not run"
        }
    }

    private var cropCountDescription: String {
        guard let candidates = detection?.candidates else { return "0" }
        return "\(candidates.filter { $0.cropData != nil }.count) / \(candidates.count)"
    }

    private func debugValue(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(StylezamDesign.cobalt)
                .frame(width: 22)
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  UIImage(data: data) != nil
            else {
                throw VisionDebugError.unreadablePhoto
            }
            sourceData = data
            sourceName = "Selected photo · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
            await runInspection()
        } catch {
            resetResults()
            errorMessage = error.localizedDescription
        }
    }

    private func loadLatestScan(_ scan: SavedScan) async {
        do {
            let data = try Data(contentsOf: model.library.imageURL(for: scan))
            guard UIImage(data: data) != nil else {
                throw VisionDebugError.unreadablePhoto
            }
            sourceData = data
            sourceName = "Library · \(scan.createdAt.formatted(date: .abbreviated, time: .shortened))"
            await runInspection()
        } catch {
            resetResults()
            errorMessage = error.localizedDescription
        }
    }

    private func runInspection() async {
        guard let sourceData else { return }
        let requestID = UUID()
        inspectionID = requestID
        isInspecting = true
        detection = nil
        elapsedMilliseconds = nil
        errorMessage = nil
        copiedReport = false
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let result = try await model.inspectGarments(in: sourceData)
            guard inspectionID == requestID else { return }
            elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            detection = result
        } catch {
            guard inspectionID == requestID else { return }
            errorMessage = error.localizedDescription
        }
        guard inspectionID == requestID else { return }
        isInspecting = false
    }

    private func resetResults() {
        inspectionID = UUID()
        sourceData = nil
        sourceName = nil
        detection = nil
        elapsedMilliseconds = nil
        errorMessage = nil
        isInspecting = false
        copiedReport = false
    }

    private func diagnosticReport(candidates: [GarmentCandidate]) -> String {
        let report = VisionDiagnosticReport(
            createdAt: .now,
            source: sourceName,
            sourceBytes: sourceData?.count,
            detector: detection?.method.rawValue,
            modelID: model.modelPack.manifest?.modelID,
            modelVersion: model.modelPack.manifest?.version,
            modelStatus: model.modelPack.status.shortLabel,
            maxItems: model.settings.maxDetectedItems,
            elapsedMilliseconds: elapsedMilliseconds,
            items: candidates.map {
                VisionDiagnosticItem(
                    id: $0.id,
                    localLabel: $0.localLabel,
                    confidence: $0.confidence,
                    box: $0.box,
                    cropBytes: $0.cropData?.count
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else {
            return "Stylezam Vision Inspector could not encode the diagnostic report."
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct VisionSourceDebugPreview: View {
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
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .stroke(.white, lineWidth: 2)
                            .background(StylezamDesign.cobalt.opacity(0.08))
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
        .accessibilityLabel("Test image with \(candidates.count) detected garment regions")
    }
}

private struct VisionCandidateDebugRow: View {
    let index: Int
    let candidate: GarmentCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index). \(candidate.localLabel)")
                    .font(.headline)
                Spacer()
                Text(candidate.confidence, format: .percent.precision(.fractionLength(1)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let cropData = candidate.cropData,
               let image = UIImage(data: cropData)
            {
                VisionCropDebugPreview(image: image)
                HStack {
                    Text("PNG with alpha")
                    Spacer()
                    Text("\(Int(image.size.width)) × \(Int(image.size.height)) · \(ByteCountFormatter.string(fromByteCount: Int64(cropData.count), countStyle: .file))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Label("No crop data returned", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                debugGridRow("Item ID", candidate.id)
                debugGridRow("Box x/y", coordinate(candidate.box.x, candidate.box.y))
                debugGridRow("Box w/h", coordinate(candidate.box.width, candidate.box.height))
            }
            .font(.caption)

        }
        .padding(.vertical, 8)
    }

    private func debugGridRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        }
    }

    private func coordinate(_ first: Double, _ second: Double) -> String {
        "\(first.formatted(.number.precision(.fractionLength(4)))) / \(second.formatted(.number.precision(.fractionLength(4))))"
    }

}

private struct VisionCropDebugPreview: View {
    let image: UIImage

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Color.white
                    .overlay(alignment: .bottomLeading) {
                        Text("LIGHT")
                            .foregroundStyle(.black.opacity(0.46))
                            .padding(8)
                    }
                Color.black
                    .overlay(alignment: .bottomTrailing) {
                        Text("DARK")
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(8)
                    }
            }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(12)
        }
        .font(.system(size: 9, weight: .bold))
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 1)
        }
        .accessibilityLabel("Transparent segmented crop shown on light and dark backgrounds")
    }
}

private struct VisionDiagnosticReport: Codable {
    let createdAt: Date
    let source: String?
    let sourceBytes: Int?
    let detector: String?
    let modelID: String?
    let modelVersion: String?
    let modelStatus: String
    let maxItems: Int
    let elapsedMilliseconds: Double?
    let items: [VisionDiagnosticItem]
}

private struct VisionDiagnosticItem: Codable {
    let id: String
    let localLabel: String
    let confidence: Double
    let box: BoundingBoxDTO
    let cropBytes: Int?
}

private enum VisionDebugError: LocalizedError {
    case unreadablePhoto

    var errorDescription: String? {
        "The selected image could not be opened. Choose another photo."
    }
}
