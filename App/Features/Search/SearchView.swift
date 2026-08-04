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
    @State private var assistantQuestion = ""
    @State private var lastAssistantQuestion: String?
    @State private var assistantReply: String?
    @State private var isAskingAssistant = false
    @State private var showAssistantProgress = false
    @State private var assistantProgressTask: Task<Void, Never>?
    @FocusState private var assistantFocused: Bool
    @Namespace private var productTransition

    private var scan: SavedScan? {
        guard let scanID else { return nil }
        return model.library.scans.first { $0.id == scanID }
    }

    private var selectedGarment: SavedGarment? {
        guard let selectedGarmentID else { return scan?.items.first }
        return scan?.items.first { $0.id == selectedGarmentID }
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
        .onChange(of: referenceItem) { _, item in
            guard let item else { return }
            Task { await loadReference(item) }
        }
        .onDisappear {
            searchProgressTask?.cancel()
            assistantProgressTask?.cancel()
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
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
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
            .buttonStyle(.glass)

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isCameraPresented = true
                } else {
                    message = "Camera is not available on this device."
                }
            } label: {
                SearchSourceLabel(title: "Camera", icon: "camera")
            }
            .buttonStyle(.glass)

            Button(action: pasteReferenceImage) {
                SearchSourceLabel(title: "Paste", icon: "doc.on.clipboard")
            }
            .buttonStyle(.glass)
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
            .buttonStyle(.glassProminent)
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
                Text("\(scan.items.count) detected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if scan.items.isEmpty {
                ContentUnavailableView(
                    "No pieces found",
                    systemImage: "viewfinder",
                    description: Text("Try a brighter image with a clearer view of the garment.")
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(scan.items) { item in
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
            assistantReply = nil
            lastAssistantQuestion = nil
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

                Text(item.localLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(
                    attempts > 0
                        ? "\(attempts) search\(attempts == 1 ? "" : "es") used"
                        : failedAttempts > 0 ? "Retry available" : "Ready"
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            Button {
                guard let garment = selectedGarment else { return }
                Task { await search(scan: scan, garment: garment) }
            } label: {
                HStack(spacing: 10) {
                    Text(isSearching ? "Searching online" : currentSearch == nil ? "Search visual matches" : "Show saved results")
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
            .buttonStyle(.glassProminent)
            .tint(StylezamDesign.cobalt)
            .disabled(selectedGarment == nil || isSearching)

            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text("\(model.settings.productSearchesPerPiece) visual search per piece · up to \(model.settings.productResultLimit) live results")
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
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text("Matches")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(search.results.count) · \(duration(search.durationMilliseconds))")
                    .font(.caption.monospacedDigit())
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
                spacing: 24
            ) {
                ForEach(search.results) { product in
                    NavigationLink(value: product) {
                        SearchProductCard(product: product)
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: product.id, in: productTransition)
                }
            }

            Text("One provider query can return several products. Stylezam limits what it displays; it does not fire one request per result.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func assistantSection(_ search: SavedProductSearch?) -> some View {
        let quickQuestions = [
            "Describe this piece",
            "What details are visible?",
            "What should I search for?",
        ]
        return VStack(alignment: .leading, spacing: 14) {
            EditorialRule()
            EditorialSectionHeader(title: "Stylezam AI", detail: "Fireworks · Qwen 3.7 Plus")

            Text("Ask about the selected crop. AI does not search stores unless you choose Search using this request.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let search, !search.generatedSuggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(search.generatedSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                guard let scan, let garment = selectedGarment else { return }
                                Task { await refineSearch(suggestion, scan: scan, garment: garment) }
                            }
                            .buttonStyle(.glass)
                            .disabled(isSearching)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                Text("A refinement performs another Qwen + Serper search and follows the per-piece limit.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if assistantReply == nil {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(quickQuestions, id: \.self) { question in
                            Button(question) { askAssistant(question) }
                                .buttonStyle(.glass)
                                .disabled(isAskingAssistant)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 9) {
                TextField("Ask about color, material, or styling", text: $assistantQuestion)
                    .focused($assistantFocused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .onSubmit { askAssistant(nil) }
                Button { askAssistant(nil) } label: {
                    if isAskingAssistant {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(StylezamDesign.cobalt)
                .disabled(assistantQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAskingAssistant)
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(minHeight: 52)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())

            if isAskingAssistant, showAssistantProgress {
                longOperationProgress(title: "Stylezam AI is reading the selected piece")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let assistantReply {
                VStack(alignment: .leading, spacing: 13) {
                    Text(assistantReply)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lastAssistantQuestion, let scan, let garment = selectedGarment {
                        Button {
                            Task { await refineSearch(lastAssistantQuestion, scan: scan, garment: garment) }
                        } label: {
                            Label("Search similar using this request", systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(isSearching)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StylezamDesign.cobalt.opacity(0.07), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showAssistantProgress)
    }

    private func longOperationProgress(title: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
            ProgressView()
                .progressViewStyle(.linear)
                .tint(StylezamDesign.cobalt)
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
        selectedGarmentID = saved.items.first?.id
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

    private func askAssistant(_ suggestedQuestion: String?) {
        let question = (suggestedQuestion ?? assistantQuestion)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let scan, let garment = selectedGarment else { return }
        assistantFocused = false
        isAskingAssistant = true
        showAssistantProgress = false
        assistantReply = nil
        message = nil
        assistantProgressTask?.cancel()
        assistantProgressTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, isAskingAssistant else { return }
            showAssistantProgress = true
        }
        Task { @MainActor in
            defer {
                assistantProgressTask?.cancel()
                assistantProgressTask = nil
                showAssistantProgress = false
                isAskingAssistant = false
            }
            do {
                assistantReply = try await model.askStylezamAI(
                    scanID: scan.id,
                    garmentID: garment.id,
                    question: question
                )
                lastAssistantQuestion = question
                if suggestedQuestion == nil { assistantQuestion = "" }
            } catch {
                message = error.localizedDescription
            }
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
        assistantReply = nil
        lastAssistantQuestion = nil
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
        VStack(alignment: .leading, spacing: 8) {
            ProductImage(url: product.imageURL)
                .frame(maxWidth: .infinity)
                .aspectRatio(0.84, contentMode: .fit)
                .padding(8)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            Text(product.merchant.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(product.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(product.price?.formatted ?? "Price unavailable")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
