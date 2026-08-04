import PhotosUI
import SwiftUI
import UIKit

struct VisionDebugView: View {
    @Environment(AppModel.self) private var model

    @State private var photoItem: PhotosPickerItem?
    @State private var sourceData: Data?
    @State private var sourceImage: UIImage?
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
            if let metrics = detection?.metrics {
                debugValue(
                    "Detection plan",
                    value: "\(metrics.sourceWidth) × \(metrics.sourceHeight) source · "
                        + "\(metrics.inferencePassCount ?? 1) passes",
                    symbol: "arrow.down.right.and.arrow.up.left"
                )
                debugValue(
                    "Model tile",
                    value: "\(metrics.modelInputResolution) × \(metrics.modelInputResolution) each · fixed tensor",
                    symbol: "square.dashed"
                )
                if let effectiveResolution = metrics.effectiveDetectionResolution {
                    debugValue(
                        "Effective detector detail",
                        value: "≈ \(effectiveResolution) px long edge",
                        symbol: "scope"
                    )
                }
                if let strategy = metrics.inferenceStrategy {
                    debugValue(
                        "Detail strategy",
                        value: strategy,
                        symbol: "square.grid.3x3"
                    )
                }
                debugValue(
                    "Source detail",
                    value: metrics.sourceMegapixels.formatted(
                        .number.precision(.fractionLength(2))
                    ) + " MP",
                    symbol: "camera.aperture"
                )
            }
            debugValue(
                "Pieces",
                value: "\(detection?.candidates.count ?? 0) / \(model.settings.maxDetectedItems)",
                symbol: "square.stack.3d.up"
            )
            if let sourceImage {
                debugValue(
                    "Inspector preview",
                    value: "\(Int(sourceImage.size.width)) × \(Int(sourceImage.size.height)) px",
                    symbol: "photo"
                )
            }
            debugValue(
                "Box crops",
                value: boxCropCountDescription,
                symbol: "crop"
            )
            debugValue(
                "Transparent crops",
                value: cropCountDescription,
                symbol: "scissors"
            )
            debugValue(
                "Class labeling",
                value: detection == nil ? "Not run" : "Included in model inference",
                symbol: "tag"
            )
            if let metrics = detection?.metrics {
                debugValue(
                    "Decode source",
                    value: milliseconds(metrics.decodeMilliseconds),
                    symbol: "photo.badge.arrow.down"
                )
                debugValue(
                    "Prepare model input",
                    value: milliseconds(metrics.inputPreparationMilliseconds),
                    symbol: "square.resize.down"
                )
                debugValue(
                    "Core ML inference",
                    value: milliseconds(metrics.inferenceMilliseconds),
                    symbol: "cpu"
                )
                debugValue(
                    "Decode boxes + labels + masks",
                    value: milliseconds(metrics.outputDecodingMilliseconds),
                    symbol: "viewfinder"
                )
                debugValue(
                    "Encode full-detail crops",
                    value: milliseconds(metrics.cropEncodingMilliseconds),
                    symbol: "crop"
                )
                debugValue(
                    "Vision engine total",
                    value: milliseconds(metrics.totalMilliseconds),
                    symbol: "stopwatch"
                )
                if let budget = metrics.processingBudgetMilliseconds {
                    debugValue(
                        "Still-photo budget",
                        value: "\(milliseconds(budget)) · "
                            + ((metrics.budgetLimited ?? false) ? "limited" : "within budget"),
                        symbol: "hourglass"
                    )
                }
                if let thermalState = metrics.thermalState {
                    debugValue(
                        "Device protection",
                        value: thermalState
                            + ((metrics.lowPowerMode ?? false) ? " · Low Power Mode" : ""),
                        symbol: "thermometer.medium"
                    )
                }
            }
            debugValue(
                "Inspector wall time",
                value: elapsedMilliseconds.map(milliseconds)
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
            if let sourceImage {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    VisionCandidateDebugRow(
                        index: index + 1,
                        candidate: candidate,
                        sourceImage: sourceImage,
                        metrics: detection?.metrics
                    )
                }
            }
        } header: {
            Text("Segmented pieces")
        } footer: {
            Text("Box crop shows the complete detected region without a mask. Isolated cutout shows the saved transparent PNG. Alpha mask makes holes and rough edges explicit.")
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

            Text("The report contains model state, timing, source and crop dimensions, normalized and pixel-space boxes, Fashionpedia IDs, confidence, PNG sizes, and alpha-pixel diagnostics. It does not include image bytes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

    private var boxCropCountDescription: String {
        guard let candidates = detection?.candidates else { return "0" }
        return "\(candidates.filter { $0.boxCropData != nil }.count) / \(candidates.count)"
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

    private func milliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " ms"
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                throw VisionDebugError.unreadablePhoto
            }
            sourceData = data
            sourceImage = preparedDebugImage(image)
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
            guard let image = UIImage(data: data) else {
                throw VisionDebugError.unreadablePhoto
            }
            sourceData = data
            sourceImage = preparedDebugImage(image)
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
        sourceImage = nil
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
            sourceWidth: detection?.metrics?.sourceWidth
                ?? sourceImage.map { Int($0.size.width) },
            sourceHeight: detection?.metrics?.sourceHeight
                ?? sourceImage.map { Int($0.size.height) },
            detector: detection?.method.rawValue,
            modelID: model.modelPack.manifest?.modelID,
            modelVersion: model.modelPack.manifest?.version,
            modelStatus: model.modelPack.status.shortLabel,
            maxItems: model.settings.maxDetectedItems,
            elapsedMilliseconds: elapsedMilliseconds,
            pipeline: detection?.metrics,
            items: candidates.map { candidate in
                let boxCrop = candidate.boxCropData.flatMap(UIImage.init(data:))
                    ?? sourceImage.flatMap { boundingBoxCrop(from: $0, box: candidate.box) }
                return VisionDiagnosticItem(
                    id: candidate.id,
                    categoryID: model.modelPack.manifest?.classNames.firstIndex(
                        of: candidate.localLabel
                    ),
                    localLabel: candidate.localLabel,
                    confidence: candidate.confidence,
                    box: candidate.box,
                    boxPixels: detection?.metrics.flatMap {
                        sourcePixelBox(
                            for: candidate.box,
                            width: $0.sourceWidth,
                            height: $0.sourceHeight
                        )
                    } ?? sourceImage.flatMap {
                        sourcePixelBox(for: candidate.box, image: $0)
                    },
                    boxCrop: boxCrop.map {
                        VisionRasterSummary(
                            width: Int($0.size.width),
                            height: Int($0.size.height),
                            bytes: candidate.boxCropData?.count
                        )
                    },
                    segmentedCrop: candidate.cropData.flatMap {
                        cropAlphaArtifacts($0)?.summary
                    }
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
    let sourceImage: UIImage
    let metrics: GarmentPipelineMetrics?
    @State private var isCropExpanded = false

    var body: some View {
        let boxCrop = candidate.boxCropData.flatMap(UIImage.init(data:))
            ?? boundingBoxCrop(from: sourceImage, box: candidate.box)
        let sourceWidth = metrics?.sourceWidth ?? Int(sourceImage.size.width)
        let sourceHeight = metrics?.sourceHeight ?? Int(sourceImage.size.height)
        let pixelBox = sourcePixelBox(
            for: candidate.box,
            width: sourceWidth,
            height: sourceHeight
        )
        let alphaArtifacts = candidate.cropData.flatMap(cropAlphaArtifacts)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index). \(candidate.localLabel)")
                    .font(.headline)
                Spacer()
                Text(candidate.confidence, format: .percent.precision(.fractionLength(1)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            DebugArtifactTitle(
                title: "Bounding-box crop",
                detail: "Saved user crop · tap to expand"
            )
            if let boxCrop {
                Button {
                    isCropExpanded = true
                } label: {
                    VisionBoxCropPreview(image: boxCrop)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(.black.opacity(0.62), in: Circle())
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)
            } else {
                debugArtifactError("Bounding-box crop could not be created")
            }

            if let cropData = candidate.cropData,
               let image = UIImage(data: cropData)
            {
                DebugArtifactTitle(
                    title: "Isolated cutout",
                    detail: "Saved transparent PNG"
                )
                VisionCutoutDebugPreview(image: image)

                if let alphaArtifacts {
                    DebugArtifactTitle(
                        title: "Alpha mask",
                        detail: "White kept · black removed"
                    )
                    VisionMaskDebugPreview(image: alphaArtifacts.maskImage)
                }
            } else {
                debugArtifactError("No transparent cutout was returned")
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                debugGridRow("Item ID", candidate.id)
                if let categoryID = StylezamCategory.index(of: candidate.localLabel) {
                    debugGridRow("Category", "Fashionpedia \(categoryID)")
                }
                debugGridRow(
                    "Confidence",
                    "\(candidate.confidence.formatted(.percent.precision(.fractionLength(2)))) · "
                        + candidate.confidence.formatted(.number.precision(.fractionLength(6)))
                )
                debugGridRow(
                    "Source pixels",
                    "\(sourceWidth) × \(sourceHeight)"
                )
                debugGridRow("Box x/y", coordinate(candidate.box.x, candidate.box.y))
                debugGridRow("Box w/h", coordinate(candidate.box.width, candidate.box.height))
                if let pixelBox {
                    debugGridRow(
                        "Box pixels",
                        "x \(pixelBox.x), y \(pixelBox.y), w \(pixelBox.width), h \(pixelBox.height)"
                    )
                }
                if let boxCrop {
                    debugGridRow(
                        "Box crop",
                        "\(Int(boxCrop.size.width)) × \(Int(boxCrop.size.height)) px · "
                            + ByteCountFormatter.string(
                                fromByteCount: Int64(candidate.boxCropData?.count ?? 0),
                                countStyle: .file
                            )
                    )
                }
                if let cropData = candidate.cropData,
                   let alpha = alphaArtifacts?.summary
                {
                    debugGridRow(
                        "Cutout PNG",
                        "\(alpha.width) × \(alpha.height) · "
                            + ByteCountFormatter.string(
                                fromByteCount: Int64(cropData.count),
                                countStyle: .file
                            )
                    )
                    debugGridRow(
                        "Mask coverage",
                        alpha.foregroundFraction.formatted(
                            .percent.precision(.fractionLength(2))
                        )
                    )
                    debugGridRow("Transparent α0", "\(alpha.transparentPixels)")
                    debugGridRow("Soft edge α1–254", "\(alpha.softEdgePixels)")
                    debugGridRow("Opaque α255", "\(alpha.opaquePixels)")
                }
            }
            .font(.caption)

        }
        .padding(.vertical, 8)
        .fullScreenCover(isPresented: $isCropExpanded) {
            if let boxCrop {
                NavigationStack {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: boxCrop)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    }
                    .navigationTitle(candidate.localLabel)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbarBackground(.black, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isCropExpanded = false }
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
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

    private func debugArtifactError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(.red)
    }
}

private struct DebugArtifactTitle: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VisionBoxCropPreview: View {
    let image: UIImage

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(8)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 1)
        }
        .accessibilityLabel("Original image cropped to the detected bounding box")
    }
}

private struct VisionCutoutDebugPreview: View {
    let image: UIImage

    var body: some View {
        ZStack {
            TransparencyCheckerboard()
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(10)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 1)
        }
        .accessibilityLabel("Transparent segmented garment cutout on a checkerboard")
    }
}

private struct VisionMaskDebugPreview: View {
    let image: UIImage

    var body: some View {
        ZStack {
            Color.black
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(10)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 1)
        }
        .accessibilityLabel("Black and white segmentation alpha mask")
    }
}

private struct TransparencyCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 14
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for column in 0..<columns {
                    let color = (row + column).isMultiple(of: 2)
                        ? Color(uiColor: .systemBackground)
                        : Color(uiColor: .systemGray5)
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * tile,
                                y: CGFloat(row) * tile,
                                width: tile,
                                height: tile
                            )
                        ),
                        with: .color(color)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct VisionDiagnosticReport: Codable {
    let createdAt: Date
    let source: String?
    let sourceBytes: Int?
    let sourceWidth: Int?
    let sourceHeight: Int?
    let detector: String?
    let modelID: String?
    let modelVersion: String?
    let modelStatus: String
    let maxItems: Int
    let elapsedMilliseconds: Double?
    let pipeline: GarmentPipelineMetrics?
    let items: [VisionDiagnosticItem]
}

private struct VisionDiagnosticItem: Codable {
    let id: String
    let categoryID: Int?
    let localLabel: String
    let confidence: Double
    let box: BoundingBoxDTO
    let boxPixels: VisionPixelBox?
    let boxCrop: VisionRasterSummary?
    let segmentedCrop: VisionCropAlphaSummary?
}

private struct VisionPixelBox: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

private struct VisionRasterSummary: Codable {
    let width: Int
    let height: Int
    let bytes: Int?
}

private struct VisionCropAlphaSummary: Codable {
    let width: Int
    let height: Int
    let bytes: Int
    let transparentPixels: Int
    let softEdgePixels: Int
    let opaquePixels: Int

    var foregroundFraction: Double {
        Double(softEdgePixels + opaquePixels) / Double(max(1, width * height))
    }

    var softEdgeFraction: Double {
        Double(softEdgePixels) / Double(max(1, width * height))
    }
}

private enum StylezamCategory {
    private static let names = [
        "shirt, blouse", "top, t-shirt, sweatshirt", "sweater", "cardigan", "jacket",
        "vest", "pants", "shorts", "skirt", "coat", "dress", "jumpsuit", "cape",
        "glasses", "hat", "headband, head covering, hair accessory", "tie", "glove",
        "watch", "belt", "leg warmer", "tights, stockings", "sock", "shoe",
        "bag, wallet", "scarf", "umbrella",
    ]

    static func index(of label: String) -> Int? {
        names.firstIndex(of: label)
    }
}

private struct VisionCropAlphaArtifacts {
    let summary: VisionCropAlphaSummary
    let maskImage: UIImage
}

private func preparedDebugImage(_ image: UIImage) -> UIImage {
    let maximumDimension: CGFloat = 2_000
    let longestSide = max(1, max(image.size.width, image.size.height))
    let scale = min(1, maximumDimension / longestSide)
    let target = CGSize(
        width: max(1, (image.size.width * scale).rounded()),
        height: max(1, (image.size.height * scale).rounded())
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: target, format: format).image { context in
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: target))
        image.draw(in: CGRect(origin: .zero, size: target))
    }
}

private func sourcePixelBox(
    for box: BoundingBoxDTO,
    image: UIImage
) -> VisionPixelBox? {
    sourcePixelBox(
        for: box,
        width: Int(image.size.width),
        height: Int(image.size.height)
    )
}

private func sourcePixelBox(
    for box: BoundingBoxDTO,
    width: Int,
    height: Int
) -> VisionPixelBox? {
    guard width > 1, height > 1 else { return nil }
    let left = max(0, min(width - 1, Int(floor(box.x * Double(width)))))
    let top = max(0, min(height - 1, Int(floor(box.y * Double(height)))))
    let right = max(left + 1, min(width, Int(ceil((box.x + box.width) * Double(width)))))
    let bottom = max(top + 1, min(height, Int(ceil((box.y + box.height) * Double(height)))))
    return VisionPixelBox(
        x: left,
        y: top,
        width: right - left,
        height: bottom - top
    )
}

private func boundingBoxCrop(
    from image: UIImage,
    box: BoundingBoxDTO
) -> UIImage? {
    guard let pixels = sourcePixelBox(for: box, image: image),
          let source = image.cgImage,
          let cropped = source.cropping(
              to: CGRect(
                  x: pixels.x,
                  y: pixels.y,
                  width: pixels.width,
                  height: pixels.height
              )
          )
    else { return nil }
    return UIImage(cgImage: cropped, scale: 1, orientation: .up)
}

private func cropAlphaArtifacts(_ data: Data) -> VisionCropAlphaArtifacts? {
    guard let image = UIImage(data: data)?.cgImage else { return nil }
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var transparent = 0
    var softEdge = 0
    var opaque = 0
    var alphaPixels = [UInt8](repeating: 0, count: width * height)
    for alphaIndex in stride(from: 3, to: pixels.count, by: 4) {
        let alpha = pixels[alphaIndex]
        alphaPixels[alphaIndex / 4] = alpha
        switch alpha {
        case 0: transparent += 1
        case 255: opaque += 1
        default: softEdge += 1
        }
    }
    guard let provider = CGDataProvider(data: Data(alphaPixels) as CFData),
          let mask = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 8,
              bytesPerRow: width,
              space: CGColorSpaceCreateDeviceGray(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: true,
              intent: .defaultIntent
          )
    else { return nil }
    let summary = VisionCropAlphaSummary(
        width: width,
        height: height,
        bytes: data.count,
        transparentPixels: transparent,
        softEdgePixels: softEdge,
        opaquePixels: opaque
    )
    return VisionCropAlphaArtifacts(
        summary: summary,
        maskImage: UIImage(cgImage: mask)
    )
}

private enum VisionDebugError: LocalizedError {
    case unreadablePhoto

    var errorDescription: String? {
        "The selected image could not be opened. Choose another photo."
    }
}
