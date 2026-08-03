import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var textQuery = ""
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
                    Button {
                        Task { await model.cancelActiveSearchAndReset() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("New search")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            textSearchBar
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .onChange(of: model.activeSearch?.id, initial: true) { _, _ in
            textQuery = model.activeSearch?.query ?? ""
            filter = .closest
        }
    }

    private var searchLanding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageTitle(
                    title: "What are you looking for?",
                    subtitle: "Start with a photo for visual matching, or describe the piece in your own words below."
                )
                .padding(.top, 18)
                .motionReveal()

                searchStage
                    .motionReveal(delay: 0.06, distance: 24)

                sourceStatus
                    .motionReveal(delay: 0.13)

                if let message = model.lastError {
                    InlineErrorView(message: message)
                }

                Label(
                    "Stylezam only shows products returned by configured sources. It never invents listings or prices.",
                    systemImage: "checkmark.shield"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 110)
            }
            .padding(.horizontal, StylezamDesign.pageInset)
        }
    }

    private var searchStage: some View {
        Button {
            model.isCapturePresented = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                LivingCobaltBackdrop()
                OrbitingBrandMark(size: 205, markOpacity: 0.88)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 30, y: -26)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Photo search", systemImage: "photo.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1)
                    Text("Choose a look")
                        .font(.system(size: 31, weight: .semibold, design: .serif))
                    Text("Use a full outfit or crop. You can focus on a detected item after Stylezam reads the photo.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.74))
                        .frame(maxWidth: 285, alignment: .leading)
                    HStack {
                        Text("Add a photo")
                            .font(.headline)
                        MotionArrow(color: .white)
                    }
                    .padding(.top, 8)
                }
                .foregroundStyle(.white)
                .padding(22)
            }
        }
        .buttonStyle(TactileButtonStyle())
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: StylezamDesign.cobalt.opacity(0.22), radius: 28, y: 16)
    }

    private var sourceStatus: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                Image(systemName: model.capabilities?.imageSearch == true ? "checkmark" : "exclamationmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        model.capabilities?.imageSearch == true ? StylezamDesign.cobalt : Color.orange,
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.capabilities?.imageSearch == true ? "Image search is ready" : "Connect a product source")
                        .font(.headline)
                    Text(
                        model.capabilities?.imageSearch == true
                            ? "Your backend can accept photos and retrieve visual product matches."
                            : "Open Settings to configure a backend with eBay image search or SerpApi Lens ingress."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.capabilities?.imageSearch != true {
                    Button {
                        model.selectedTab = .you
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .motionScrollDepth()
    }

    private func progressView(_ job: SearchJobDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    EditorialKicker(text: "Live search", color: StylezamDesign.cobalt)
                    EditorialTitle(text: progressTitle(job), size: 48)
                }
                .padding(.top, 18)
                .motionReveal()

                if model.activeSearchImageData != nil || job.inputImageURL != nil {
                    ZStack {
                        LookStackCanvas(
                            imageData: model.activeSearchImageData,
                            remoteURL: job.inputImageURL,
                            items: job.selectedRegion == nil ? (job.analysis?.detectedItems ?? []) : [],
                            selectedRegion: job.selectedRegion
                        )
                        SearchActivityOverlay(job: job)
                    }
                    .motionReveal(delay: 0.05, distance: 22)
                } else if let query = job.query {
                    ZStack(alignment: .bottomLeading) {
                        LivingCobaltBackdrop(intensity: 0.7)
                        Text("“\(query)”")
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .padding(24)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 230, alignment: .bottomLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .overlay { SearchActivityOverlay(job: job) }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.phase.title)
                    .font(.title3.weight(.bold))
                Spacer()
                Text(job.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            AnimatedProgressCapsule(progress: job.progress)

            HStack(spacing: 0) {
                phaseMarker("READ", complete: job.progress >= 0.12, active: job.phase == .understanding)
                phaseLine(complete: job.progress >= 0.43)
                phaseMarker("SOURCE", complete: job.progress >= 0.43, active: job.phase == .retrieving)
                phaseLine(complete: job.progress >= 0.78)
                phaseMarker("RANK", complete: job.progress >= 0.78, active: job.phase == .reranking)
            }

            if let query = job.query {
                Text(query)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    }

    private func phaseMarker(_ label: String, complete: Bool, active: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if active {
                    Circle()
                        .fill(StylezamDesign.cobalt.opacity(0.16))
                        .frame(width: 24, height: 24)
                        .symbolEffect(.pulse)
                }
                Circle()
                    .fill(complete ? StylezamDesign.cobalt : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
            .frame(height: 12)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(complete ? .primary : .secondary)
        }
    }

    private func phaseLine(complete: Bool) -> some View {
        Rectangle()
            .fill(complete ? StylezamDesign.cobalt : Color.secondary.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .offset(y: -7)
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
            Button("Capture another look") { model.isCapturePresented = true }
                .fontWeight(.semibold)
                .padding(.top, 4)
        }
        .padding(.vertical, 28)
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(ResultFilter.allCases) { item in
                    Button(item.title) { filter = item }
                        .buttonStyle(
                            .glass(
                                item == filter
                                    ? .regular.tint(StylezamDesign.cobalt)
                                    : .regular
                            )
                        )
                        .foregroundStyle(item == filter ? StylezamDesign.cobalt : .primary)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
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
            TextField("Describe or refine an item", text: $textQuery)
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
        .scaleEffect(isTextSearchFocused ? 1.015 : 1)
        .shadow(
            color: StylezamDesign.cobalt.opacity(isTextSearchFocused ? 0.18 : 0.06),
            radius: isTextSearchFocused ? 18 : 8,
            y: 6
        )
        .animation(StylezamMotion.quickSpring, value: isTextSearchFocused)
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
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack {
                    Button {
                        model.library.toggleSaved(product)
                    } label: {
                        Image(
                            systemName: model.library.isSaved(product)
                                ? "bookmark.fill"
                                : "bookmark"
                        )
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .symbolEffect(.bounce, value: model.library.isSaved(product))
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(
                        model.library.isSaved(product) ? "Remove bookmark" : "Bookmark"
                    )
                    Spacer()
                    StatusPill(text: product.matchTier.label)
                }
                .padding(8)
            }

            Text((product.brand ?? product.merchant).uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

private struct SearchActivityOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    let job: SearchJobDTO

    var body: some View {
        VStack {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                    Circle()
                        .stroke(.white.opacity(0.5), lineWidth: 1)
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulse && !reduceMotion ? 2.5 : 1)
                        .opacity(pulse && !reduceMotion ? 0 : 0.8)
                }
                Text(job.phase.title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                Spacer()
                Text(job.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .contentTransition(.numericText(value: job.progress))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .glassEffect(.regular.tint(.black.opacity(0.2)), in: Capsule())

            Spacer()

            AnimatedProgressCapsule(progress: job.progress)
        }
        .padding(14)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
