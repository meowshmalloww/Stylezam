import PhotosUI
import SwiftUI
import UIKit

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var referenceImageData: Data?
    @State private var referenceItem: PhotosPickerItem?
    @State private var sourceOrigin: CaptureOrigin = .photoLibrary
    @State private var scanID: UUID?
    @State private var selectedGarmentID: String?
    @State private var currentSearch: SavedProductSearch?
    @State private var isCameraPresented = false
    @State private var isSearching = false
    @State private var searchProgress: ProductSearchProgress = .preparing
    @State private var showSearchProgress = false
    @State private var searchProgressTask: Task<Void, Never>?
    @State private var message: String?
    @State private var chatContext: StylezamChatContext?
    @State private var correctionTarget: GarmentCorrectionTarget?
    @State private var comparisonSelection: [ProductResultDTO] = []
    @State private var isComparisonPresented = false
    @Namespace private var productTransition

    private var scan: SavedScan? {
        guard let scanID else { return nil }
        return model.library.scans.first { $0.id == scanID }
    }

    private var selectedGarment: SavedGarment? {
        let available = scan?.items.filter(\.accepted) ?? []
        guard let selectedGarmentID else { return available.first }
        return available.first { $0.id == selectedGarmentID }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                searchHeader

                if let scan {
                    detectedPieces(scan)
                    searchAction(scan)
                    if let currentSearch {
                        resultsSection(currentSearch)
                    }
                    assistantSection(currentSearch)
                } else {
                    referenceStage
                    sourceControls
                    detectAction
                }

            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 116)
        }
        .background(StylezamDesign.canvas)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ProductResultDTO.self) { product in
            ProductDetailView(product: product)
                .navigationTransition(.zoom(sourceID: product.id, in: productTransition))
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { data in
                referenceImageData = data
                sourceOrigin = .camera
                resetDetection()
            }
            .ignoresSafeArea()
        }
        .sheet(item: $chatContext) { context in
            StylezamChatView(
                scanID: context.scanID,
                garmentID: context.garmentID,
                currentSearch: $currentSearch
            )
        }
        .sheet(item: $correctionTarget) { target in
            DetectionCorrectionView(target: target) {
                currentSearch = nil
                if selectedGarment == nil {
                    selectedGarmentID = scan?.items.first(where: \.accepted)?.id
                }
            }
            .environment(model)
        }
        .sheet(isPresented: $isComparisonPresented) {
            ProductComparisonView(products: comparisonSelection)
        }
        .onChange(of: referenceItem) { _, item in
            guard let item else { return }
            Task { await loadReference(item) }
        }
        .task(id: model.pendingGarmentSearch?.id) {
            await consumePendingGarmentSearch()
        }
        .onDisappear {
            searchProgressTask?.cancel()
        }
        .onChange(of: currentSearch?.id) { _, _ in
            comparisonSelection.removeAll()
        }
    }

    private var searchHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                EditorialKicker(text: "Product discovery")
                Text("Find the piece.")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-1)
                Text("Choose an image, separate its garments, then search one piece at a time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if scan != nil {
                Button(action: startOver) {
                    Label("New", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 13)
                        .frame(height: 40)
                }
                .stylezamGlassButton()
                .accessibilityLabel("Search another image")
            }
        }
    }

    private var referenceStage: some View {
        Group {
            if let referenceImageData {
                DataImage(data: referenceImageData, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 210, maxHeight: 360)
                    .background(Color(uiColor: .secondarySystemBackground))
            } else {
                PhotosPicker(selection: $referenceItem, matching: .images) {
                    VStack(spacing: 15) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 33, weight: .regular))
                        VStack(spacing: 4) {
                            Text("Add a fashion photo")
                                .font(.headline)
                            Text("A full look or one product both work")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 232)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 1)
        }
    }

    private var sourceControls: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $referenceItem, matching: .images) {
                SearchSourceLabel(title: "Photos", icon: "photo.on.rectangle")
            }
            .stylezamGlassButton()

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isCameraPresented = true
                } else {
                    message = "Camera is not available on this device."
                }
            } label: {
                SearchSourceLabel(title: "Camera", icon: "camera")
            }
            .stylezamGlassButton()

            Button(action: pasteReferenceImage) {
                SearchSourceLabel(title: "Paste", icon: "doc.on.clipboard")
            }
            .stylezamGlassButton()
        }
    }

    private var detectAction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                guard let referenceImageData else { return }
                Task { await detectPieces(referenceImageData) }
            } label: {
                HStack(spacing: 10) {
                    Text(model.isAnalyzingCapture ? "Separating pieces" : "Detect pieces")
                    Spacer()
                    if model.isAnalyzingCapture {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "viewfinder")
                    }
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .stylezamGlassButton(prominent: true)
            .tint(StylezamDesign.cobalt)
            .disabled(referenceImageData == nil || model.isAnalyzingCapture)

            statusMessage
        }
    }

    private func detectedPieces(_ scan: SavedScan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Choose a piece")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(scan.items.filter(\.accepted).count) detected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if scan.items.allSatisfy({ !$0.accepted }) {
                ContentUnavailableView(
                    "No pieces found",
                    systemImage: "viewfinder",
                    description: Text("Try a brighter image with a clearer view of the garment.")
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(scan.items.filter(\.accepted)) { item in
                            garmentChip(item, scan: scan)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func garmentChip(_ item: SavedGarment, scan: SavedScan) -> some View {
        let selected = item.id == selectedGarment?.id
        let garmentKey = "\(scan.id.uuidString):\(item.id)"
        let attempts = model.searchUsage.attempts(for: garmentKey)
        let failedAttempts = model.searchUsage.failedAttempts(for: garmentKey)
        return Button {
            selectedGarmentID = item.id
            currentSearch = model.library.search(for: garmentKey)
            message = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let url = model.library.cropURL(for: item) {
                        LocalFileImage(url: url, contentMode: .fit)
                    } else {
                        Color(uiColor: .secondarySystemBackground)
                            .overlay { Image(systemName: "tshirt") }
                    }
                }
                .frame(width: 112, height: 126)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if item.needsUserReview {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(
                        item.needsUserReview
                            ? "Confirm type"
                            : attempts > 0
                                ? "\(attempts) search\(attempts == 1 ? "" : "es") used"
                                : failedAttempts > 0 ? "Retry available" : "Ready"
                    )
                }
                .font(.caption2)
                .foregroundStyle(item.needsUserReview ? Color.orange : Color.secondary)
            }
            .padding(8)
            .background(
                selected ? StylezamDesign.cobalt.opacity(0.09) : Color.clear,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(selected ? StylezamDesign.cobalt : StylezamDesign.hairline, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func searchAction(_ scan: SavedScan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let garment = selectedGarment, garment.needsUserReview {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Confirm this detection", systemImage: "questionmark.diamond")
                        .font(.headline)
                    Text(GarmentDetectionQualityPolicy.reviewReason(for: garment))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Review detection") {
                        correctionTarget = GarmentCorrectionTarget(
                            scanID: scan.id,
                            garmentID: garment.id
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StylezamDesign.cobalt)
                }
                .padding(15)
                .background(
                    Color.orange.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                }
            }

            if let garment = selectedGarment, !garment.needsUserReview {
                Button {
                    correctionTarget = GarmentCorrectionTarget(
                        scanID: scan.id,
                        garmentID: garment.id
                    )
                } label: {
                    Label("Correct detection", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button {
                guard let garment = selectedGarment else { return }
                Task { await search(scan: scan, garment: garment) }
            } label: {
                HStack(spacing: 10) {
                    Text(
                        selectedGarment?.needsUserReview == true
                            ? "Confirm before searching"
                            : isSearching
                                ? "Searching online"
                                : currentSearch == nil
                                    ? "Search visual matches"
                                    : "Show saved results"
                    )
                    Spacer()
                    if isSearching {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: currentSearch == nil ? "magnifyingglass" : "checkmark")
                    }
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .stylezamGlassButton(prominent: true)
            .tint(StylezamDesign.cobalt)
            .disabled(
                selectedGarment == nil
                    || selectedGarment?.isPipelineEligible != true
                    || isSearching
            )

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                Text(
                    currentSearch.map { "\($0.results.count) live results saved" }
                        ?? "One private search when you tap · up to \(model.settings.productResultLimit) results"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isSearching, showSearchProgress {
                longOperationProgress(title: searchProgress.title)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            statusMessage
        }
        .animation(.easeOut(duration: 0.2), value: showSearchProgress)
    }

    private func resultsSection(_ search: SavedProductSearch) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(searchTitle(search))
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text("\(search.results.count) products")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                    Text("One live shopping search")
                    Text("·")
                    Text(duration(search.durationMilliseconds))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let query = search.generatedQuery {
                Text(query)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(search.results) { product in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink(value: product) {
                            SearchProductCard(product: product)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: product.id, in: productTransition)

                        Button {
                            toggleComparison(product)
                        } label: {
                            Image(systemName: isCompared(product) ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.title3.weight(.semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    isCompared(product) ? .white : StylezamDesign.cobalt,
                                    isCompared(product) ? StylezamDesign.cobalt : .white
                                )
                                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                .frame(width: 42, height: 42)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isCompared(product) ? "Remove from comparison" : "Add to comparison"
                        )
                    }
                }
            }

            if !comparisonSelection.isEmpty {
                comparisonTray
            }

            Label(searchDisclosure(search), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comparisonTray: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare products")
                        .font(.headline)
                    Text(
                        comparisonSelection.count < 2
                            ? "Choose one more product"
                            : "\(comparisonSelection.count) selected · maximum 3"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") { comparisonSelection.removeAll() }
                    .font(.caption.weight(.semibold))
            }

            HStack(spacing: 8) {
                ForEach(comparisonSelection) { product in
                    ProductImage(url: product.imageURL)
                        .frame(width: 48, height: 54)
                        .padding(3)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Spacer(minLength: 6)
                Button {
                    isComparisonPresented = true
                } label: {
                    Label("Compare", systemImage: "rectangle.split.3x1")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                }
                .stylezamGlassButton(prominent: true)
                .tint(StylezamDesign.cobalt)
                .disabled(comparisonSelection.count < 2)
            }
        }
        .padding(15)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
    }

    private func isCompared(_ product: ProductResultDTO) -> Bool {
        comparisonSelection.contains(where: { $0.id == product.id })
    }

    private func toggleComparison(_ product: ProductResultDTO) {
        if let index = comparisonSelection.firstIndex(where: { $0.id == product.id }) {
            comparisonSelection.remove(at: index)
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        guard comparisonSelection.count < 3 else {
            message = "Compare up to three products at a time."
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        comparisonSelection.append(product)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func searchDisclosure(_ search: SavedProductSearch) -> String {
        switch search.aiSearchIntent {
        case .similar:
            "AI prepared visible shopping terms and one live request returned these alternatives."
        case .cheaper:
            "Prices are current observations, not tracked history. Comparable priced results are ordered lower first; verify the merchant’s final price and shipping."
        case nil:
            "One live image search returned these products. Similar means visually related—not proof of an exact SKU."
        }
    }

    private func searchTitle(_ search: SavedProductSearch) -> String {
        switch search.aiSearchIntent {
        case .similar: "Similar pieces"
        case .cheaper: "Lower-priced options"
        case nil: "Visual matches"
        }
    }

    private func assistantSection(_ search: SavedProductSearch?) -> some View {
        let conversationCount: Int = {
            guard let scan, let garment = selectedGarment else { return 0 }
            return model.library.chatMessages(
                for: "\(scan.id.uuidString):\(garment.id)"
            ).count
        }()
        return VStack(alignment: .leading, spacing: 14) {
            EditorialRule()
            EditorialSectionHeader(title: "Stylezam AI", detail: "Image aware")

            Text("Have a real conversation about the selected piece, then search similar products or lower-priced alternatives with live shopping results.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard let scan, let garment = selectedGarment else { return }
                chatContext = StylezamChatContext(scanID: scan.id, garmentID: garment.id)
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(StylezamDesign.cobalt)
                        .frame(width: 42, height: 42)
                        .background(StylezamDesign.cobalt.opacity(0.09), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conversationCount == 0 ? "Start a conversation" : "Continue conversation")
                            .font(.headline)
                        Text(
                            conversationCount == 0
                                ? "Image-aware answers and live shopping actions"
                                : "\(conversationCount) saved message\(conversationCount == 1 ? "" : "s")"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
            }
            .buttonStyle(.plain)
            .background(
                LinearGradient(
                    colors: [Color(uiColor: .secondarySystemBackground), StylezamDesign.cobalt.opacity(0.055)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(StylezamDesign.hairline, lineWidth: 1)
            }

            if let search, !search.generatedSuggestions.isEmpty {
                Text("Search directions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(search.generatedSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                guard let scan, let garment = selectedGarment else { return }
                                Task { await refineSearch(suggestion, scan: scan, garment: garment) }
                            }
                            .stylezamGlassButton()
                            .disabled(isSearching)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func longOperationProgress(title: String) -> some View {
        HStack(spacing: 12) {
            SearchThinkingDots()
            VStack(alignment: .leading, spacing: 3) {
                Text("Working on this piece")
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message = message ?? model.lastError {
            Text(message)
                .font(.caption)
                .foregroundStyle(message == model.lastError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detectPieces(_ data: Data) async {
        message = nil
        model.lastError = nil
        let saved = await model.processCapture(
            imageData: data,
            origin: sourceOrigin,
            mode: .imported,
            navigateToLibrary: false
        )
        guard let saved else { return }
        scanID = saved.id
        selectedGarmentID = saved.items.first(where: \.accepted)?.id
        currentSearch = nil
        model.activeScanID = nil
        if saved.items.isEmpty { message = "No distinct fashion pieces were detected." }
    }

    private func search(scan: SavedScan, garment: SavedGarment) async {
        let key = "\(scan.id.uuidString):\(garment.id)"
        if let existing = model.library.search(for: key) {
            currentSearch = existing
            message = nil
            return
        }
        await performSearch(scan: scan, garment: garment, refinement: nil)
    }

    @MainActor
    private func consumePendingGarmentSearch() async {
        guard let request = model.pendingGarmentSearch else { return }
        guard let requestedScan = model.library.scans.first(where: { $0.id == request.scanID }),
              let requestedGarment = requestedScan.items.first(where: { $0.id == request.garmentID })
        else {
            message = "That detected piece is no longer available in Library."
            if model.pendingGarmentSearch?.id == request.id {
                model.pendingGarmentSearch = nil
            }
            return
        }

        scanID = requestedScan.id
        selectedGarmentID = requestedGarment.id
        referenceImageData = nil
        message = nil
        let key = "\(requestedScan.id.uuidString):\(requestedGarment.id)"
        currentSearch = model.library.search(for: key)

        if request.startsImmediately, currentSearch == nil {
            await search(scan: requestedScan, garment: requestedGarment)
        }

        if model.pendingGarmentSearch?.id == request.id {
            model.pendingGarmentSearch = nil
        }
    }

    private func refineSearch(_ refinement: String, scan: SavedScan, garment: SavedGarment) async {
        await performSearch(scan: scan, garment: garment, refinement: refinement)
    }

    private func performSearch(scan: SavedScan, garment: SavedGarment, refinement: String?) async {
        isSearching = true
        searchProgress = .preparing
        showSearchProgress = false
        message = nil
        model.lastError = nil
        searchProgressTask?.cancel()
        searchProgressTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, isSearching else { return }
            showSearchProgress = true
        }
        defer {
            searchProgressTask?.cancel()
            searchProgressTask = nil
            showSearchProgress = false
            isSearching = false
        }
        do {
            currentSearch = try await model.productSearch(
                scanID: scan.id,
                garmentID: garment.id,
                refinement: refinement,
                progress: { searchProgress = $0 }
            )
        } catch {
            message = error.localizedDescription
        }
    }

    private func loadReference(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let normalized = await ImageEncoding.normalizedJPEGAsync(from: data)
        {
            referenceImageData = normalized
            sourceOrigin = .photoLibrary
            resetDetection()
        } else {
            message = "That image could not be read. Choose another photo."
        }
    }

    private func pasteReferenceImage() {
        guard let image = UIPasteboard.general.image,
              let data = ImageEncoding.normalizedJPEG(from: image)
        else {
            message = "Clipboard does not contain an image."
            return
        }
        referenceImageData = data
        sourceOrigin = .clipboard
        resetDetection()
    }

    private func resetDetection() {
        scanID = nil
        selectedGarmentID = nil
        currentSearch = nil
        message = nil
    }

    private func startOver() {
        referenceImageData = nil
        referenceItem = nil
        resetDetection()
    }

    private func duration(_ milliseconds: Double) -> String {
        if milliseconds < 1_000 { return "\(Int(milliseconds.rounded())) ms" }
        return (milliseconds / 1_000).formatted(.number.precision(.fractionLength(1))) + " s"
    }
}

private struct StylezamChatContext: Identifiable {
    let scanID: UUID
    let garmentID: String

    var id: String { "\(scanID.uuidString):\(garmentID)" }
}

private struct SearchThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(StylezamDesign.cobalt)
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == index ? 1.32 : 0.72)
                    .opacity(phase == index ? 1 : 0.28)
            }
        }
        .frame(width: 36, height: 28)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: phase)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(330))
                guard !Task.isCancelled else { return }
                phase = (phase + 1) % 3
            }
        }
        .accessibilityLabel("Search is working")
    }
}

private struct SearchSourceLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
    }
}

private struct SearchProductCard: View {
    let product: ProductResultDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ProductImage(url: product.imageURL)
                .frame(maxWidth: .infinity)
                .aspectRatio(0.86, contentMode: .fit)
                .padding(10)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            HStack(spacing: 6) {
                Text(product.matchSummaryLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(StylezamDesign.cobalt)
                Spacer(minLength: 0)
                Text(product.merchant)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(product.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(product.price?.formatted ?? "Price unavailable")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
    }
}
