import PhotosUI
import SwiftUI
import UIKit

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var textQuery = ""
    @State private var referenceImageData: Data?
    @State private var referenceItem: PhotosPickerItem?
    @State private var isReferencePickerPresented = false
    @State private var isReferenceCameraPresented = false
    @State private var referenceMessage: String?
    @State private var filter: ResultFilter = .closest
    @FocusState private var isTextSearchFocused: Bool
    @Namespace private var productTransition

    var body: some View {
        Group {
            if let job = model.activeSearch {
                if job.status == .completed {
                    resultsView(job)
                } else {
                    progressView(job)
                }
            } else {
                searchLanding
            }
        }
        .background(StylezamDesign.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.activeSearch != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New", systemImage: "square.and.pencil") {
                        Task { await model.cancelActiveSearchAndReset() }
                    }
                    .accessibilityLabel("New search")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.activeSearch != nil {
                textSearchBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
        .onChange(of: model.activeSearch?.id, initial: true) { _, _ in
            textQuery = model.activeSearch?.query ?? ""
            filter = .closest
        }
        .photosPicker(
            isPresented: $isReferencePickerPresented,
            selection: $referenceItem,
            matching: .images
        )
        .fullScreenCover(isPresented: $isReferenceCameraPresented) {
            CameraPicker { data in
                referenceImageData = data
                referenceMessage = nil
            }
            .ignoresSafeArea()
        }
        .onChange(of: referenceItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let normalized = await ImageEncoding.normalizedJPEGAsync(from: data)
                {
                    referenceImageData = normalized
                    referenceMessage = nil
                } else {
                    referenceMessage = "That reference image could not be read."
                }
            }
        }
    }

    private var searchLanding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageTitle(
                    title: "Search",
                    subtitle: "Search clothing across the web with words, a reference image, or both."
                )
                .padding(.top, 18)

                searchComposer

                if let message = model.lastError {
                    InlineErrorView(message: message)
                }

                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(StylezamDesign.cobalt)
                    Text("Results come from configured product sources. Stylezam does not invent listings or prices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, StylezamDesign.pageInset)
        }
    }

    private var searchComposer: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField(
                    "Brand, color, style, or product",
                    text: $textQuery,
                    axis: .vertical
                )
                .focused($isTextSearchFocused)
                .submitLabel(.search)
                .lineLimit(2...4)
                .font(.system(size: 23, weight: .medium))
                .onSubmit { submitUniversalSearch() }

                if !textQuery.isEmpty {
                    Button {
                        textQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear text")
                }
            }

            Rectangle()
                .fill(isTextSearchFocused ? Color.primary : StylezamDesign.hairline)
                .frame(height: isTextSearchFocused ? 1.5 : 1)

            if let referenceImageData {
                HStack(spacing: 12) {
                    DataImage(data: referenceImageData)
                        .frame(width: 72, height: 86)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reference image")
                            .font(.subheadline.weight(.semibold))
                        Text("Stylezam will combine visual details with your search text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        self.referenceImageData = nil
                        referenceItem = nil
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove reference image")
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                Menu {
                    Button {
                        isReferencePickerPresented = true
                    } label: {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            isReferenceCameraPresented = true
                        } else {
                            referenceMessage = "Camera is not available on this device."
                        }
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    Button {
                        pasteReferenceImage()
                    } label: {
                        Label("Paste image", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Label(
                        referenceImageData == nil ? "Reference" : "Replace",
                        systemImage: "photo.badge.plus"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(height: 48)
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.glass)

                Spacer()

                Button {
                    submitUniversalSearch()
                } label: {
                    HStack(spacing: 8) {
                        Text("Search")
                        Image(systemName: "arrow.right")
                    }
                    .fontWeight(.semibold)
                    .frame(height: 48)
                    .padding(.horizontal, 18)
                }
                .buttonStyle(.glassProminent)
                .tint(StylezamDesign.cobalt)
                .disabled(!canSubmitLandingSearch)
            }

            if let referenceMessage {
                Text(referenceMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(StylezamMotion.quickSpring, value: isTextSearchFocused)
    }

    private var canSubmitLandingSearch: Bool {
        referenceImageData != nil
            || !textQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func progressView(_ job: SearchJobDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SEARCH IN PROGRESS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    EditorialTitle(text: progressTitle(job), size: 42)
                }
                .padding(.top, 18)
                .motionReveal()

                if model.activeSearchImageData != nil || job.inputImageURL != nil {
                    LookStackCanvas(
                        imageData: model.activeSearchImageData,
                        remoteURL: job.inputImageURL,
                        items: job.selectedRegion == nil ? (job.analysis?.detectedItems ?? []) : [],
                        selectedRegion: job.selectedRegion
                    )
                    .motionReveal(delay: 0.05, distance: 22)
                } else if let query = job.query {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(query)
                            .font(.title2.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(20)
                    .background(StylezamDesign.secondaryPaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .motionReveal(delay: 0.05, distance: 22)
                }

                searchProgressPanel(job)
                    .motionReveal(delay: 0.1)

                if let message = model.lastError ?? job.errorMessage {
                    InlineErrorView(message: message) {
                        Task { await model.retryActiveSearch() }
                    }
                }

                if !job.providerWarnings.isEmpty {
                    warnings(job.providerWarnings)
                }
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.bottom, 120)
        }
    }

    private func searchProgressPanel(_ job: SearchJobDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.phase.title)
                    .font(.headline)
                Spacer()
                Text(job.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: job.progress)
                .progressViewStyle(.linear)
                .tint(.primary)
                .animation(.easeInOut(duration: 0.35), value: job.progress)

            EditorialRule()

            phaseRow("Understand the item", complete: job.progress >= 0.43, active: job.phase == .understanding || job.phase == .queued)
            phaseRow("Search product sources", complete: job.progress >= 0.78, active: job.phase == .retrieving)
            phaseRow("Check and rank evidence", complete: job.status == .completed, active: job.phase == .reranking)

            if let query = job.query {
                Text(query)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func phaseRow(_ label: String, complete: Bool, active: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: complete ? "checkmark" : active ? "circle.fill" : "circle")
                .font(complete ? .caption.weight(.bold) : .system(size: 7, weight: .semibold))
                .foregroundStyle(complete || active ? Color.primary : Color.secondary)
                .frame(width: 16)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(active || complete ? .primary : .secondary)
            Spacer()
            if active {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func resultsView(_ job: SearchJobDTO) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    EditorialKicker(text: "Source-backed results")
                    EditorialTitle(
                        text: showLookStack(job) ? "Look stack" : "Matches",
                        size: 50
                    )
                }
                .padding(.top, 18)
                .motionReveal()

                if showLookStack(job) {
                    lookStack(job)
                } else {
                    sourceSummary(job)
                }

                EditorialSectionHeader(
                    title: "Product matches",
                    detail: job.resultCount == 1 ? "1 result" : "\(job.resultCount) results"
                )
                .motionReveal(delay: 0.05)

                filterBar
                    .motionReveal(delay: 0.08)

                if filteredResults.isEmpty {
                    emptyResults
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        alignment: .leading,
                        spacing: 26
                    ) {
                        ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, product in
                            NavigationLink(value: product) {
                                ProductResultCard(product: product)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: product.id, in: productTransition)
                            .motionReveal(delay: min(Double(index) * 0.045, 0.28), distance: 22)
                            .motionScrollDepth()
                        }
                    }
                    .animation(StylezamMotion.softSpring, value: filter)
                }

                if !job.providerWarnings.isEmpty {
                    warnings(job.providerWarnings)
                }
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.bottom, 120)
        }
        .navigationDestination(for: ProductResultDTO.self) { product in
            ProductDetailView(product: product)
                .navigationTransition(.zoom(sourceID: product.id, in: productTransition))
        }
    }

    private func showLookStack(_ job: SearchJobDTO) -> Bool {
        job.selectedRegion == nil && (job.analysis?.detectedItems.count ?? 0) > 1
    }

    private func lookStack(_ job: SearchJobDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tap the item you mean")
                    .font(.headline)
                Spacer()
                Text("\(job.analysis?.detectedItems.count ?? 0) detected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LookStackCanvas(
                imageData: model.activeSearchImageData,
                remoteURL: job.inputImageURL,
                items: job.analysis?.detectedItems ?? [],
                selectedRegion: job.selectedRegion
            ) { item in
                Task { await model.focusOnDetectedItem(item) }
            }
            Text("Detection locates visible fashion items; it does not prove a product identity. Choose one to run a tighter product search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceSummary(_ job: SearchJobDTO) -> some View {
        HStack(spacing: 14) {
            Group {
                if let data = model.activeSearchImageData {
                    DataImage(data: data)
                } else if let imageURL = job.inputImageURL {
                    ProductImage(url: imageURL, contentMode: .fill)
                } else {
                    StylezamDesign.cobalt
                        .overlay {
                            Image(systemName: "text.magnifyingglass")
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 70, height: 84)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                if job.selectedRegion != nil {
                    EditorialKicker(text: "Focused selection", color: StylezamDesign.cobalt)
                }
                Text(job.query ?? job.analysis?.searchQuery ?? "From your capture")
                    .font(.headline)
                    .lineLimit(2)
                Text(job.resultCount == 1 ? "1 source-backed result" : "\(job.resultCount) source-backed results")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Nothing strong enough yet")
                .font(.title2.weight(.bold))
                .fontWidth(.condensed)
            Text("Try fewer descriptive words, select a tighter item box, or configure another real retrieval source.")
                .foregroundStyle(.secondary)
            Button("Capture another look") { model.presentCapture(.camera) }
                .fontWeight(.semibold)
                .padding(.top, 4)
        }
        .padding(.vertical, 28)
    }

    private var filterBar: some View {
        Picker("Filter results", selection: $filter) {
            ForEach(ResultFilter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var filteredResults: [ProductResultDTO] {
        switch filter {
        case .closest:
            model.searchResults
        case .underTwoHundred:
            model.searchResults.filter { ($0.price?.amount ?? .infinity) < 200 }
        case .exactOrLikely:
            model.searchResults.filter { $0.matchTier == .exact || $0.matchTier == .likely }
        }
    }

    private var textSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
            TextField("Search products", text: $textQuery)
                .focused($isTextSearchFocused)
                .submitLabel(.search)
                .onSubmit { submitTextSearch() }
            if !textQuery.isEmpty {
                Button {
                    textQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
            Button {
                submitTextSearch()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .tint(StylezamDesign.cobalt)
            .disabled(textQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Search")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 58)
        .glassEffect(.regular, in: Capsule())
    }

    private func submitTextSearch() {
        let query = textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task {
            await model.startSearch(
                SearchInput(query: query, imageData: nil, origin: .text)
            )
        }
    }

    private func submitUniversalSearch() {
        let query = textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard referenceImageData != nil || !query.isEmpty else { return }
        let image = referenceImageData
        Task {
            let identifier = await model.startSearch(
                SearchInput(
                    query: query.isEmpty ? nil : query,
                    imageData: image,
                    origin: image == nil ? .text : .photoLibrary
                )
            )
            if identifier != nil {
                referenceImageData = nil
                referenceItem = nil
                referenceMessage = nil
            }
        }
    }

    private func pasteReferenceImage() {
        guard let image = UIPasteboard.general.image,
              let data = ImageEncoding.normalizedJPEG(from: image)
        else {
            referenceMessage = "The clipboard does not contain an image."
            return
        }
        referenceImageData = data
        referenceMessage = nil
    }

    private func progressTitle(_ job: SearchJobDTO) -> String {
        switch job.phase {
        case .queued, .understanding: "Reading the look"
        case .retrieving: "Finding products"
        case .reranking: "Checking evidence"
        case .completed: "Matches ready"
        case .failed: "Search stopped"
        }
    }

    private func warnings(_ values: [String]) -> some View {
        DisclosureGroup("Provider notes") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(values, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .font(.subheadline.weight(.semibold))
    }
}

private enum ResultFilter: String, CaseIterable, Identifiable {
    case closest
    case underTwoHundred
    case exactOrLikely

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closest: "Closest"
        case .underTwoHundred: "Under $200"
        case .exactOrLikely: "Exact + likely"
        }
    }
}

private struct ProductResultCard: View {
    @Environment(AppModel.self) private var model
    let product: ProductResultDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                ProductImage(url: product.imageURL)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.79, contentMode: .fit)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    model.library.toggleSaved(product)
                } label: {
                    Image(
                        systemName: model.library.isSaved(product)
                            ? "bookmark.fill"
                            : "bookmark"
                    )
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .symbolEffect(.bounce, value: model.library.isSaved(product))
                }
                .padding(8)
                .buttonStyle(.glass)
                .accessibilityLabel(
                    model.library.isSaved(product) ? "Remove bookmark" : "Bookmark"
                )
            }

            HStack(alignment: .firstTextBaseline) {
                Text((product.brand ?? product.merchant).uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(product.matchTier.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(product.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(product.price?.formatted ?? "Price unavailable")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}
