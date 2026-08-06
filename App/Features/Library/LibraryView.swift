import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var section: LibrarySection = .recent
    @State private var selectedTryOn: SavedTryOn?
    @State private var selectedScan: SavedScan?
    @State private var selectedSearch: SavedProductSearch?
    @State private var isSelecting = false
    @State private var selection: Set<LibrarySelection> = []
    @State private var isConfirmingSelectionDelete = false
    @Namespace private var productTransition

    private var galleryColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12),
        ]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your visual wardrobe")
                        .font(.title2.weight(.semibold))
                        .tracking(-0.45)
                    Text("Every scan becomes a reusable piece—not another screenshot to sort through.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                categoryBar

                if let loadError = model.library.loadError {
                    InlineErrorView(message: loadError)
                }

                Group {
                    switch section {
                    case .recent:
                        recentScans
                    case .matches:
                        searchHistory
                    case .saved:
                        savedProducts
                    case .tryOns:
                        tryOnHistory
                    }
                }
                .id(section)
                .transition(.opacity)
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.bottom, 112)
        }
        .background(StylezamDesign.canvas)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation(.snappy(duration: 0.25)) {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                }
                .disabled(count(for: section) == 0)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting {
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationDestination(for: ProductResultDTO.self) { product in
            ProductDetailView(product: product)
                .navigationTransition(.zoom(sourceID: product.id, in: productTransition))
        }
        .sheet(item: $selectedTryOn) { tryOn in
            TryOnArchiveDetail(tryOn: tryOn)
                .environment(model)
        }
        .sheet(item: $selectedScan) { scan in
            ScanDetailView(scanID: scan.id)
                .environment(model)
        }
        .sheet(item: $selectedSearch) { search in
            SearchArchiveDetail(search: search)
                .environment(model)
        }
        .animation(.easeInOut(duration: 0.2), value: section)
        .sensoryFeedback(.selection, trigger: section)
        .sensoryFeedback(.selection, trigger: selection.count)
        .confirmationDialog(
            "Delete \(selection.count) selected item\(selection.count == 1 ? "" : "s")?",
            isPresented: $isConfirmingSelectionDelete,
            titleVisibility: .visible
        ) {
            Button("Delete selected", role: .destructive, action: deleteSelection)
        } message: {
            Text("The selected local captures, crops, searches, saves, or try-ons will be removed from this iPhone.")
        }
        .onChange(of: section) { _, _ in
            selection.removeAll()
        }
        .onChange(of: model.activeScanID, initial: true) { _, scanID in
            guard let scanID,
                  let scan = model.library.scans.first(where: { $0.id == scanID })
            else { return }
            section = .recent
            selectedScan = scan
            model.activeScanID = nil
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.isEmpty ? "Choose items" : "\(selection.count) selected")
                    .font(.headline)
                Text("Tap any card to add or remove it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                isConfirmingSelectionDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, StylezamDesign.pageInset)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func toggle(_ item: LibrarySelection) {
        if !selection.insert(item).inserted {
            selection.remove(item)
        }
    }

    private func deleteSelection() {
        var scanIDs: Set<UUID> = []
        var searchIDs: Set<String> = []
        var wardrobeIDs: Set<UUID> = []
        var productIDs: Set<String> = []
        var tryOnIDs: Set<String> = []
        for item in selection {
            switch item {
            case let .scan(id): scanIDs.insert(id)
            case let .search(id): searchIDs.insert(id)
            case let .wardrobe(id): wardrobeIDs.insert(id)
            case let .product(id): productIDs.insert(id)
            case let .tryOn(id): tryOnIDs.insert(id)
            }
        }
        model.deleteLibraryItems(
            scanIDs: scanIDs,
            searchIDs: searchIDs,
            wardrobeIDs: wardrobeIDs,
            productIDs: productIDs,
            tryOnIDs: tryOnIDs
        )
        selection.removeAll()
        isSelecting = false
    }

    private var categoryBar: some View {
        HStack(spacing: 0) {
            ForEach(LibrarySection.allCases) { item in
                Button {
                    section = item
                } label: {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(.subheadline.weight(item == section ? .semibold : .regular))
                            Text(count(for: item), format: .number)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Rectangle()
                            .fill(item == section ? Color.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .foregroundStyle(item == section ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            EditorialRule()
        }
        .accessibilityElement(children: .contain)
    }

    private func count(for item: LibrarySection) -> Int {
        switch item {
        case .recent: model.library.scans.count
        case .matches: model.library.searches.count
        case .saved: model.library.products.count + model.library.wardrobeItems.count
        case .tryOns: model.library.tryOns.count
        }
    }

    private var recentScans: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(
                title: "Captured looks",
                detail: countLabel(model.library.scans.count, singular: "capture")
            )

            if model.library.scans.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No captures yet",
                    message: "Camera, imported, shared, and live-screen scans will appear here."
                )
            } else {
                LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 24) {
                    ForEach(model.library.scans) { scan in
                        RecentScanCard(
                            scan: scan,
                            imageURL: model.library.displayImageURL(for: scan),
                            onOpen: { selectedScan = scan },
                            onDelete: { model.deleteScan(scan) }
                        )
                        .librarySelectionOverlay(
                            isSelecting: isSelecting,
                            isSelected: selection.contains(.scan(scan.id)),
                            action: { toggle(.scan(scan.id)) }
                        )
                    }
                }
            }
        }
    }

    private var searchHistory: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(
                title: "Product matches",
                detail: countLabel(model.library.searches.count, singular: "search")
            )
            if model.library.searches.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: "No searches yet",
                    message: "Completed product searches will remain here until you delete them."
                )
            } else {
                LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 24) {
                    ForEach(model.library.searches) { search in
                        SearchHistoryCard(
                            search: search,
                            onOpen: { selectedSearch = search },
                            onDelete: { model.library.deleteSearch(search) }
                        )
                        .librarySelectionOverlay(
                            isSelecting: isSelecting,
                            isSelected: selection.contains(.search(search.id)),
                            action: { toggle(.search(search.id)) }
                        )
                    }
                }
            }
        }
    }

    private var savedProducts: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(
                title: "Saved pieces",
                detail: countLabel(model.library.products.count + model.library.wardrobeItems.count, singular: "item")
            )

            if model.library.products.isEmpty && model.library.wardrobeItems.isEmpty {
                emptyState(
                    icon: "bookmark",
                    title: "Nothing saved",
                    message: "Bookmark a product match and it will stay here for later."
                )
            } else {
                LazyVGrid(
                    columns: galleryColumns,
                    alignment: .leading,
                    spacing: 26
                ) {
                    ForEach(model.library.wardrobeItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            LocalFileImage(url: model.library.imageURL(for: item), contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(0.78, contentMode: .fit)
                                .padding(8)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(item.category.title.uppercased())
                                .font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        }
                        .contextMenu {
                            Button("Remove from saved", role: .destructive) { model.library.deleteWardrobeItem(item) }
                        }
                        .librarySelectionOverlay(
                            isSelecting: isSelecting,
                            isSelected: selection.contains(.wardrobe(item.id)),
                            action: { toggle(.wardrobe(item.id)) }
                        )
                    }
                    ForEach(model.library.products) { saved in
                        ZStack(alignment: .topTrailing) {
                            NavigationLink(value: saved.product) {
                                SavedProductCard(saved: saved)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: saved.product.id, in: productTransition)

                            LibraryOverflowMenu(title: "Remove from saved") {
                                model.library.toggleSaved(saved.product)
                            }
                            .padding(8)
                        }
                        .contextMenu {
                            Button("Remove from saved", role: .destructive) {
                                model.library.toggleSaved(saved.product)
                            }
                        }
                        .librarySelectionOverlay(
                            isSelecting: isSelecting,
                            isSelected: selection.contains(.product(saved.id)),
                            action: { toggle(.product(saved.id)) }
                        )
                    }
                }
            }
        }
    }

    private var tryOnHistory: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(
                title: "Appearance previews",
                detail: countLabel(model.library.tryOns.count, singular: "preview")
            )

            if model.library.tryOns.isEmpty {
                emptyState(
                    icon: "tshirt",
                    title: "No try-ons yet",
                    message: "Completed appearance previews are downloaded and kept here automatically."
                )
            } else {
                LazyVGrid(
                    columns: galleryColumns,
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(model.library.tryOns) { tryOn in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                selectedTryOn = tryOn
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    LocalFileImage(url: model.library.imageURL(for: tryOn))
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(0.78, contentMode: .fit)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    Text(tryOn.displayTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Text(tryOn.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            LibraryOverflowMenu(title: "Delete try-on") {
                                model.library.deleteTryOn(tryOn)
                            }
                            .padding(8)
                        }
                        .contextMenu {
                            Button("Delete try-on", role: .destructive) {
                                model.library.deleteTryOn(tryOn)
                            }
                        }
                        .librarySelectionOverlay(
                            isSelecting: isSelecting,
                            isSelected: selection.contains(.tryOn(tryOn.id)),
                            action: { toggle(.tryOn(tryOn.id)) }
                        )
                    }
                }
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text(message)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        if count == 1 {
            return "1 \(singular)"
        }
        return "\(count) \(singular)s"
    }
}

private enum LibrarySection: String, CaseIterable, Identifiable {
    case recent
    case matches
    case saved
    case tryOns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .matches: "Matches"
        case .saved: "Saved"
        case .tryOns: "Try-ons"
        }
    }
}

private enum LibrarySelection: Hashable {
    case scan(UUID)
    case search(String)
    case wardrobe(UUID)
    case product(String)
    case tryOn(String)
}

private extension View {
    func librarySelectionOverlay(
        isSelecting: Bool,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        overlay {
            if isSelecting {
                Button(action: action) {
                    Color.clear
                        .contentShape(Rectangle())
                        .overlay(alignment: .topLeading) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 38, height: 38)
                                .background(
                                    isSelected ? StylezamDesign.cobalt : Color.white.opacity(0.88),
                                    in: Circle()
                                )
                                .shadow(color: .black.opacity(0.14), radius: 9, y: 3)
                                .padding(10)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    isSelected ? StylezamDesign.cobalt : Color.clear,
                                    lineWidth: 3
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Deselect item" : "Select item")
            }
        }
    }
}

private struct RecentScanCard: View {
    let scan: SavedScan
    let imageURL: URL
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var acceptedCount: Int { scan.items.filter(\.accepted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    Color(uiColor: .secondarySystemBackground)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.82, contentMode: .fit)
                        .overlay {
                            LocalFileImage(url: imageURL, contentMode: .fill)
                        }
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.56)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scan.origin.libraryLabel.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1.1)
                                Text(StylezamRelativeTime.string(since: scan.createdAt))
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                        }
                }
                .buttonStyle(.plain)

                LibraryOverflowMenu(title: "Delete capture", onDelete: onDelete)
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(StylezamDesign.hairline, lineWidth: 0.75)
            }

            Button(action: onOpen) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(acceptedCount == 1 ? "1 piece" : "\(acceptedCount) pieces")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text(scan.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Delete capture", role: .destructive, action: onDelete)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct SearchHistoryCard: View {
    @Environment(AppModel.self) private var model
    let search: SavedProductSearch
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var cropURL: URL? {
        guard let scan = model.library.scans.first(where: { $0.id == search.scanID }),
              let garment = scan.items.first(where: { $0.id == search.garmentID })
        else { return nil }
        return model.library.cropURL(for: garment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    Color(uiColor: .secondarySystemBackground)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.82, contentMode: .fit)
                        .overlay {
                            Group {
                                if let cropURL {
                                    LocalFileImage(url: cropURL, contentMode: .fill)
                                } else {
                                    ProductImage(url: search.results.first?.imageURL, contentMode: .fill)
                                }
                            }
                        }
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.58)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottomLeading) {
                            Text("\(search.results.count) MATCHES")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(.white)
                                .padding(12)
                        }
                }
                .buttonStyle(.plain)

                LibraryOverflowMenu(title: "Delete search", onDelete: onDelete)
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(StylezamDesign.hairline, lineWidth: 0.75)
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(search.generatedQuery ?? "Visual product search")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(search.providerSummary).lineLimit(1)
                        Text("·")
                        Text(StylezamRelativeTime.string(since: search.createdAt))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Delete search", role: .destructive, action: onDelete)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct LibraryOverflowMenu: View {
    let title: String
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button(title, systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.5), lineWidth: 0.75) }
        }
        .accessibilityLabel("More actions")
    }
}

private struct SearchArchiveDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let search: SavedProductSearch
    @Namespace private var transition

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let query = search.generatedQuery {
                        Text(query)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text(search.providerSummary)
                        Spacer()
                        Text(search.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        alignment: .leading,
                        spacing: 24
                    ) {
                        ForEach(search.results) { product in
                            NavigationLink(value: product) {
                                ArchiveProductCard(product: product)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: product.id, in: transition)
                        }
                    }
                }
                .padding(StylezamDesign.pageInset)
                .padding(.bottom, 28)
            }
            .background(StylezamDesign.canvas)
            .navigationTitle("Matches")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProductResultDTO.self) { product in
                ProductDetailView(product: product)
                    .navigationTransition(.zoom(sourceID: product.id, in: transition))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete", role: .destructive) {
                        model.library.deleteSearch(search)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ArchiveProductCard: View {
    let product: ProductResultDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductImage(url: product.imageURL)
                .frame(maxWidth: .infinity)
                .aspectRatio(0.82, contentMode: .fit)
                .padding(8)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(product.merchant.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(product.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(product.price?.formatted ?? "Price unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScanDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scanID: UUID

    private var scan: SavedScan? {
        model.library.scans.first { $0.id == scanID }
    }

    private func metricsSummary(_ metrics: GarmentPipelineMetrics) -> String {
        let passCount = metrics.inferencePassCount ?? 1
        let tileLabel = passCount == 1 ? "model tile" : "model tiles"
        let source = "\(metrics.sourceWidth) × \(metrics.sourceHeight) source"
        let model = "\(passCount) × \(metrics.modelInputResolution) \(tileLabel)"
        let effective = passCount > 1
            ? " · ≈ \(metrics.effectiveDetectionResolution ?? metrics.modelInputResolution) px effective"
            : ""
        let elapsed = metrics.totalMilliseconds.formatted(
            .number.precision(.fractionLength(0))
        )
        return "\(source) · \(model)\(effective) · \(elapsed) ms"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let scan {
                    VStack(alignment: .leading, spacing: 24) {
                        LocalFileImage(
                            url: model.library.displayImageURL(for: scan),
                            contentMode: .fit
                        )
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scan.mode.detailTitle)
                                    .font(.title2.weight(.semibold))
                                Text(scan.createdAt.formatted(date: .long, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let metrics = scan.visionMetrics {
                                    Text(metricsSummary(metrics))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            labelState(scan)
                        }

                        EditorialRule()

                        VStack(alignment: .leading, spacing: 14) {
                            EditorialSectionHeader(
                                title: "Pieces",
                                detail: "\(visibleItems(scan).count)"
                            )

                            Text("Search a detected crop for live products and prices, or send the crop directly to Try On.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if visibleItems(scan).isEmpty {
                                ContentUnavailableView(
                                    "No distinct pieces found",
                                    systemImage: "viewfinder",
                                    description: Text(
                                        model.modelPack.isInstalled
                                            ? "Try a brighter angle with less overlap."
                                            : "Download the garment model for worn outfits; the built-in fallback works best on isolated products."
                                    )
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                            } else {
                                ForEach(visibleItems(scan)) { item in
                                    garmentRow(item, scan: scan)
                                }
                            }
                        }
                    }
                    .padding(StylezamDesign.pageInset)
                    .padding(.bottom, 24)
                } else {
                    ContentUnavailableView("Capture unavailable", systemImage: "photo")
                }
            }
            .background(StylezamDesign.canvas)
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let scan {
                        ShareLink(item: model.library.displayImageURL(for: scan)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share capture")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func visibleItems(_ scan: SavedScan) -> [SavedGarment] {
        scan.items.filter { scan.labelState == .enriched ? $0.accepted : true }
    }

    @ViewBuilder
    private func labelState(_ scan: SavedScan) -> some View {
        switch scan.labelState {
        case .local:
            Label("Detected", systemImage: "checkmark")
                .foregroundStyle(StylezamDesign.cobalt)
        case .enriched:
            Label("Ready", systemImage: "checkmark")
                .foregroundStyle(StylezamDesign.cobalt)
        case .unavailable:
            Label("On-device", systemImage: "iphone")
                .foregroundStyle(.secondary)
        }
    }

    private func garmentRow(_ item: SavedGarment, scan: SavedScan) -> some View {
        let key = "\(scan.id.uuidString):\(item.id)"
        let savedSearch = model.library.search(for: key)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let cropURL = model.library.cropURL(for: item) {
                        LocalFileImage(url: cropURL, contentMode: .fit)
                    } else {
                        Color(uiColor: .secondarySystemBackground)
                            .overlay { Image(systemName: "tshirt") }
                    }
                }
                .frame(width: 92, height: 108)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let brand = item.brand {
                        Text(brand.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }
                    let attributes = item.colors + item.materials + item.patterns + item.details
                    if !attributes.isEmpty {
                        Text(attributes.prefix(4).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("On-device confidence \(item.localConfidence.formatted(.percent.precision(.fractionLength(0))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let savedSearch {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(savedSearch.providerSummary)
                                .lineLimit(1)
                            Text(searchPriceSummary(savedSearch))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                Button {
                    dismiss()
                    model.openProductSearch(
                        scanID: scan.id,
                        garmentID: item.id,
                        startsImmediately: savedSearch == nil
                    )
                } label: {
                    Label(
                        savedSearch.map { "View \($0.results.count) products" } ?? "Find products & prices",
                        systemImage: savedSearch == nil ? "magnifyingglass" : "checkmark"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .stylezamGlassButton(prominent: true)
                .tint(StylezamDesign.cobalt)

                Button {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        model.addGarmentToTryOn(scanID: scan.id, garmentID: item.id)
                    }
                } label: {
                    Label("Try on crop", systemImage: "wand.and.sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .stylezamGlassButton()
            }
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
    }

    private func searchPriceSummary(_ search: SavedProductSearch) -> String {
        guard !search.results.isEmpty else { return "No priced products returned" }
        let prices = search.results.compactMap(\.price)
        guard let first = prices.first else {
            return "\(search.results.count) products · prices unavailable"
        }
        let comparable = prices.filter { $0.currency == first.currency }
        guard let lowest = comparable.min(by: { $0.amount < $1.amount }) else {
            return "\(search.results.count) products"
        }
        return "\(search.results.count) products · from \(lowest.formatted)"
    }
}

private extension CaptureMode {
    var detailTitle: String {
        switch self {
        case .photo: "Camera capture"
        case .live: "Live capture"
        case .screen: "Screen capture"
        case .imported: "Imported image"
        }
    }
}

private struct SavedProductCard: View {
    let saved: SavedProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductImage(url: saved.product.imageURL)
                .frame(maxWidth: .infinity)
                .aspectRatio(0.78, contentMode: .fit)
                .padding(8)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text((saved.product.brand ?? saved.product.merchant).uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(saved.product.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(saved.product.price?.formatted ?? "Price unavailable")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TryOnArchiveDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tryOn: SavedTryOn

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LocalFileImage(url: model.library.imageURL(for: tryOn))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.72, contentMode: .fit)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(tryOn.displayTitle)
                        .font(.title2.weight(.semibold))
                    Text("Appearance preview · \(tryOn.createdAt.formatted(date: .long, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ShareLink(item: model.library.imageURL(for: tryOn)) {
                        Label("Share preview", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .stylezamGlassButton(prominent: true)
                    .tint(StylezamDesign.cobalt)
                }
                .padding(StylezamDesign.pageInset)
            }
            .background(StylezamDesign.paper)
            .navigationTitle("Try-on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension CaptureOrigin {
    var libraryLabel: String {
        switch self {
        case .camera: "Camera"
        case .photoLibrary: "Photo"
        case .text: "Text"
        case .clipboard: "Clipboard"
        case .shareExtension: "Shared"
        case .screenCapture: "Live screen"
        }
    }
}
