import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var section: LibrarySection = .recent
    @State private var selectedTryOn: SavedTryOn?
    @State private var selectedWardrobeItem: SavedWardrobeItem?
    @State private var selectedScan: SavedScan?
    @State private var selectedSearch: SavedProductSearch?
    @State private var isSelecting = false
    @State private var selection: Set<LibrarySelection> = []
    @State private var libraryQuery = ""
    @State private var categoryFilter: LibraryCategoryFilter = .all
    @State private var sortOrder: LibrarySortOrder = .newest
    @State private var isConfirmingSelectionDelete = false
    @State private var pendingWardrobeDeletion: SavedWardrobeItem?
    @State private var pendingTryOnDeletion: SavedTryOn?
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
                libraryOrganizer

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
        .searchable(
            text: $libraryQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search pieces, brands, and colors"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation(.snappy(duration: 0.25)) {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                }
                .disabled(visibleCount == 0)
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
        .sheet(item: $selectedWardrobeItem) { item in
            WardrobeItemDetail(item: item)
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
        .confirmationDialog(
            "Remove this item from Library?",
            isPresented: Binding(
                get: { pendingWardrobeDeletion != nil },
                set: { if !$0 { pendingWardrobeDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingWardrobeDeletion
        ) { item in
            Button("Remove item", role: .destructive) {
                model.library.deleteWardrobeItem(item)
                pendingWardrobeDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingWardrobeDeletion = nil
            }
        } message: { item in
            Text("“\(item.title)” will also be removed from the current try-on rail. Saved try-on manifests will not change.")
        }
        .confirmationDialog(
            "Delete this try-on?",
            isPresented: Binding(
                get: { pendingTryOnDeletion != nil },
                set: { if !$0 { pendingTryOnDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingTryOnDeletion
        ) { tryOn in
            Button("Delete try-on", role: .destructive) {
                model.library.deleteTryOn(tryOn)
                pendingTryOnDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingTryOnDeletion = nil
            }
        } message: { tryOn in
            Text("“\(tryOn.displayTitle)” will be removed. Your wardrobe and current try-on rail will stay unchanged.")
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
        .onChange(of: categoryFilter) { _, _ in
            selection.removeAll()
        }
        .onChange(of: libraryQuery) { _, _ in
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

    private var libraryOrganizer: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Label("Organize", systemImage: "line.3.horizontal.decrease")
                    .font(.subheadline.weight(.semibold))

                Text(visibleCount == count(for: section)
                     ? countLabel(visibleCount, singular: "item")
                     : "\(visibleCount) of \(count(for: section))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Menu {
                    Picker("Sort Library", selection: $sortOrder) {
                        ForEach(LibrarySortOrder.allCases) { order in
                            Label(order.title, systemImage: order.symbol)
                                .tag(order)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(sortOrder.shortTitle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                    }
                }
                .accessibilityLabel("Sort Library")
                .accessibilityValue(sortOrder.title)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(LibraryCategoryFilter.allCases) { filter in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                categoryFilter = filter
                            }
                        } label: {
                            Label(filter.title, systemImage: filter.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    categoryFilter == filter ? Color.white : Color.primary
                                )
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(
                                    categoryFilter == filter
                                        ? StylezamDesign.cobalt
                                        : Color(uiColor: .secondarySystemBackground),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            categoryFilter == filter
                                                ? Color.clear
                                                : Color.primary.opacity(0.09),
                                            lineWidth: 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            categoryFilter == filter ? .isSelected : []
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: visibleCount)
    }

    private var recentScans: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(
                title: "Captured looks",
                detail: countLabel(filteredScans.count, singular: "capture")
            )

            if model.library.scans.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No captures yet",
                    message: "Camera, imported, shared, and live-screen scans will appear here."
                )
            } else if filteredScans.isEmpty {
                filteredEmptyState
            } else {
                LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 24) {
                    ForEach(filteredScans) { scan in
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
                detail: countLabel(filteredSearches.count, singular: "search")
            )
            if model.library.searches.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: "No searches yet",
                    message: "Completed product searches will remain here until you delete them."
                )
            } else if filteredSearches.isEmpty {
                filteredEmptyState
            } else {
                LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 24) {
                    ForEach(filteredSearches) { search in
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
                detail: countLabel(filteredWardrobeItems.count + filteredProducts.count, singular: "item")
            )

            if model.library.products.isEmpty && model.library.wardrobeItems.isEmpty {
                emptyState(
                    icon: "bookmark",
                    title: "Nothing saved",
                    message: "Bookmark a product match and it will stay here for later."
                )
            } else if filteredWardrobeItems.isEmpty && filteredProducts.isEmpty {
                filteredEmptyState
            } else {
                LazyVGrid(
                    columns: galleryColumns,
                    alignment: .leading,
                    spacing: 26
                ) {
                    ForEach(filteredWardrobeItems) { item in
                        let railEntry = model.library.tryOnRail.first {
                            $0.wardrobeItemID == item.id
                        }
                        ZStack(alignment: .topTrailing) {
                            Button {
                                selectedWardrobeItem = item
                            } label: {
                                WardrobeItemCard(
                                    item: item,
                                    imageURL: model.library.imageURL(for: item),
                                    isOnRail: railEntry != nil,
                                    isSelected: railEntry?.isSelected == true
                                )
                            }
                            .buttonStyle(.plain)

                            WardrobeOverflowMenu(
                                item: item,
                                isOnRail: railEntry != nil,
                                isSelected: railEntry?.isSelected == true,
                                onPreview: { selectedWardrobeItem = item },
                                onAddToRail: {
                                    model.library.addWardrobeItemToTryOnRail(item, selected: true)
                                },
                                onRemoveFromRail: {
                                    model.library.removeFromTryOnRail(item.id)
                                },
                                onPurchase: item.sourceProduct.map { product in
                                    { openURL(product.productURL) }
                                },
                                onDelete: { pendingWardrobeDeletion = item }
                            )
                            .padding(8)
                        }
                        .contextMenu {
                            Button {
                                selectedWardrobeItem = item
                            } label: {
                                Label("Preview item", systemImage: "eye")
                            }
                            Button {
                                model.library.addWardrobeItemToTryOnRail(item, selected: true)
                            } label: {
                                Label(
                                    railEntry?.isSelected == true
                                        ? "Selected on try-on rail"
                                        : "Select on try-on rail",
                                    systemImage: railEntry?.isSelected == true
                                        ? "checkmark.circle.fill"
                                        : "wand.and.sparkles"
                                )
                            }
                            .disabled(railEntry?.isSelected == true)
                            if let product = item.sourceProduct {
                                Button {
                                    openURL(product.productURL)
                                } label: {
                                    Label("View at \(product.merchant)", systemImage: "arrow.up.right")
                                }
                            }
                            if railEntry != nil {
                                Button {
                                    model.library.removeFromTryOnRail(item.id)
                                } label: {
                                    Label("Remove from try-on rail", systemImage: "minus.circle")
                                }
                            }
                            Button("Remove from saved", systemImage: "trash", role: .destructive) {
                                pendingWardrobeDeletion = item
                            }
                        }
                        .librarySelectionOverlay(
                            isSelecting: isSelecting,
                            isSelected: selection.contains(.wardrobe(item.id)),
                            action: { toggle(.wardrobe(item.id)) }
                        )
                    }
                    ForEach(filteredProducts) { saved in
                        ZStack(alignment: .topTrailing) {
                            NavigationLink(value: saved.product) {
                                SavedProductCard(saved: saved)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: saved.product.id, in: productTransition)

                            LibraryOverflowMenu(
                                title: "Remove from saved",
                                accessibilityTarget: saved.product.title
                            ) {
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
                detail: countLabel(filteredTryOns.count, singular: "preview")
            )

            if model.library.tryOns.isEmpty {
                emptyState(
                    icon: "tshirt",
                    title: "No try-ons yet",
                    message: "Save a completed appearance preview and its outfit details will stay here."
                )
            } else if filteredTryOns.isEmpty {
                filteredEmptyState
            } else {
                LazyVGrid(
                    columns: galleryColumns,
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(filteredTryOns) { tryOn in
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

                            LibraryOverflowMenu(
                                title: "Delete try-on",
                                accessibilityTarget: tryOn.displayTitle
                            ) {
                                pendingTryOnDeletion = tryOn
                            }
                            .padding(8)
                        }
                        .contextMenu {
                            Button("Delete try-on", role: .destructive) {
                                pendingTryOnDeletion = tryOn
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

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No matching items", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Try another category or clear your Library search.")
        } actions: {
            Button("Clear filters") {
                libraryQuery = ""
                categoryFilter = .all
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var visibleCount: Int {
        switch section {
        case .recent: filteredScans.count
        case .matches: filteredSearches.count
        case .saved: filteredWardrobeItems.count + filteredProducts.count
        case .tryOns: filteredTryOns.count
        }
    }

    private var filteredScans: [SavedScan] {
        let matches = model.library.scans.filter { scan in
            guard scanMatchesCategory(scan) else { return false }
            return matchesQuery(scanSearchTerms(scan))
        }
        return ordered(matches, date: \SavedScan.createdAt) { scan in
            scan.items.first(where: \.accepted)?.title ?? scan.items.first?.title ?? "Capture"
        }
    }

    private var filteredSearches: [SavedProductSearch] {
        let matches = model.library.searches.filter { search in
            guard searchMatchesCategory(search) else { return false }
            return matchesQuery(searchSearchTerms(search))
        }
        return ordered(matches, date: \SavedProductSearch.createdAt) { search in
            search.generatedQuery ?? search.results.first?.title ?? "Product search"
        }
    }

    private var filteredWardrobeItems: [SavedWardrobeItem] {
        let matches = model.library.wardrobeItems.filter { item in
            categoryFilter.contains(item.category)
                && matchesQuery(wardrobeSearchTerms(item))
        }
        return ordered(matches, date: \SavedWardrobeItem.savedAt) { $0.title }
    }

    private var filteredProducts: [SavedProduct] {
        let matches = model.library.products.filter { saved in
            categoryFilter.contains(productCategory(saved.product))
                && matchesQuery(productSearchTerms(saved.product))
        }
        return ordered(matches, date: \SavedProduct.savedAt) { $0.product.title }
    }

    private var filteredTryOns: [SavedTryOn] {
        let matches = model.library.tryOns.filter { tryOn in
            guard tryOnMatchesCategory(tryOn) else { return false }
            var terms = [
                tryOn.displayTitle,
                tryOn.photoContext?.title ?? "",
                tryOn.gender?.title ?? "",
            ]
            for item in tryOn.items {
                terms.append(contentsOf: [item.title, item.category.title, item.garmentRegion.title])
                if let product = item.sourceProduct {
                    terms.append(contentsOf: productSearchTerms(product))
                }
            }
            if let product = tryOn.product {
                terms.append(contentsOf: productSearchTerms(product))
            }
            return matchesQuery(terms)
        }
        return ordered(matches, date: \SavedTryOn.createdAt) { $0.displayTitle }
    }

    private func scanMatchesCategory(_ scan: SavedScan) -> Bool {
        guard categoryFilter != .all else { return true }
        return scan.items.contains { item in
            categoryFilter.contains(
                TryOnCategory.infer(
                    category: item.category,
                    title: "\(item.title) \(item.localLabel)"
                )
            )
        }
    }

    private func searchMatchesCategory(_ search: SavedProductSearch) -> Bool {
        guard categoryFilter != .all else { return true }
        if search.results.contains(where: { categoryFilter.contains(productCategory($0)) }) {
            return true
        }
        return categoryFilter.contains(
            TryOnCategory.infer(
                category: search.results.first?.category,
                title: search.generatedQuery ?? search.generatedSuggestions.joined(separator: " ")
            )
        )
    }

    private func tryOnMatchesCategory(_ tryOn: SavedTryOn) -> Bool {
        guard categoryFilter != .all else { return true }
        if tryOn.items.contains(where: { categoryFilter.contains($0.category) }) {
            return true
        }
        guard let product = tryOn.product else { return false }
        return categoryFilter.contains(productCategory(product))
    }

    private func scanSearchTerms(_ scan: SavedScan) -> [String] {
        var terms = [scan.origin.rawValue, scan.mode.rawValue]
        for item in scan.items {
            terms.append(contentsOf: [
                item.title,
                item.localLabel,
                item.category ?? "",
                item.brand ?? "",
            ])
            terms.append(contentsOf: item.colors)
            terms.append(contentsOf: item.materials)
            terms.append(contentsOf: item.patterns)
            terms.append(contentsOf: item.details)
            terms.append(contentsOf: item.visibleText)
        }
        return terms
    }

    private func searchSearchTerms(_ search: SavedProductSearch) -> [String] {
        var terms = [
            search.providerSummary,
            search.generatedQuery ?? "",
            search.aiSearchIntent?.title ?? "",
        ]
        terms.append(contentsOf: search.generatedSuggestions)
        for result in search.results {
            terms.append(contentsOf: productSearchTerms(result))
        }
        return terms
    }

    private func wardrobeSearchTerms(_ item: SavedWardrobeItem) -> [String] {
        var terms = [item.title, item.category.title, item.garmentRegion?.title ?? ""]
        if let product = item.sourceProduct {
            terms.append(contentsOf: productSearchTerms(product))
        }
        return terms
    }

    private func productSearchTerms(_ product: ProductResultDTO) -> [String] {
        [
            product.title,
            product.brand ?? "",
            product.category ?? "",
            product.color ?? "",
            product.merchant,
            product.provider,
        ]
    }

    private func productCategory(_ product: ProductResultDTO) -> TryOnCategory {
        TryOnCategory.infer(category: product.category, title: product.title)
    }

    private func matchesQuery(_ terms: [String]) -> Bool {
        let query = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let tokens = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        let haystack = terms
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return tokens.allSatisfy(haystack.contains)
    }

    private func ordered<Value>(
        _ values: [Value],
        date: KeyPath<Value, Date>,
        title: (Value) -> String
    ) -> [Value] {
        values.sorted { lhs, rhs in
            switch sortOrder {
            case .newest:
                lhs[keyPath: date] > rhs[keyPath: date]
            case .oldest:
                lhs[keyPath: date] < rhs[keyPath: date]
            case .name:
                title(lhs).localizedStandardCompare(title(rhs)) == .orderedAscending
            }
        }
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        if count == 1 {
            return "1 \(singular)"
        }
        return "\(count) \(singular)s"
    }
}

private enum LibraryCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case clothes
    case bags
    case shoes
    case accessories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .clothes: "Clothes"
        case .bags: "Bags"
        case .shoes: "Shoes"
        case .accessories: "Accessories"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .clothes: "tshirt"
        case .bags: "handbag"
        case .shoes: "shoe"
        case .accessories: "sparkles"
        }
    }

    func contains(_ category: TryOnCategory) -> Bool {
        switch self {
        case .all:
            true
        case .clothes:
            category == .clothes
        case .bags:
            category == .bag
        case .shoes:
            category == .shoes
        case .accessories:
            ![TryOnCategory.clothes, .bag, .shoes].contains(category)
        }
    }
}

private enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .name: "Name A–Z"
        }
    }

    var shortTitle: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .name: "A–Z"
        }
    }

    var symbol: String {
        switch self {
        case .newest: "arrow.down"
        case .oldest: "arrow.up"
        case .name: "textformat"
        }
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

                LibraryOverflowMenu(
                    title: "Delete capture",
                    accessibilityTarget: "capture from \(scan.createdAt.formatted(date: .abbreviated, time: .omitted))",
                    onDelete: onDelete
                )
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

                LibraryOverflowMenu(
                    title: "Delete search",
                    accessibilityTarget: search.generatedQuery ?? "visual product search",
                    onDelete: onDelete
                )
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
                        Text("Live shopping search").lineLimit(1)
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
    let accessibilityTarget: String
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
        .accessibilityLabel("More actions for \(accessibilityTarget)")
    }
}

private struct WardrobeOverflowMenu: View {
    let item: SavedWardrobeItem
    let isOnRail: Bool
    let isSelected: Bool
    let onPreview: () -> Void
    let onAddToRail: () -> Void
    let onRemoveFromRail: () -> Void
    let onPurchase: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button("Preview item", systemImage: "eye", action: onPreview)
            Button(
                isSelected ? "Selected on try-on rail" : "Select on try-on rail",
                systemImage: isSelected ? "checkmark.circle.fill" : "wand.and.sparkles",
                action: onAddToRail
            )
            .disabled(isSelected)

            if let onPurchase, let product = item.sourceProduct {
                Button(
                    "View at \(product.merchant)",
                    systemImage: "arrow.up.right",
                    action: onPurchase
                )
            }

            if isOnRail {
                Button(
                    "Remove from try-on rail",
                    systemImage: "minus.circle",
                    action: onRemoveFromRail
                )
            }

            Divider()
            Button("Remove from saved", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.5), lineWidth: 0.75) }
        }
        .accessibilityLabel("More actions for \(item.title)")
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
                        Text("Live shopping results")
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
    @State private var correctionTarget: GarmentCorrectionTarget?

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
        .sheet(item: $correctionTarget) { target in
            DetectionCorrectionView(target: target)
                .environment(model)
        }
    }

    private func visibleItems(_ scan: SavedScan) -> [SavedGarment] {
        scan.items.filter(\.accepted)
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
                    }

                    Label(
                        item.userFacingDetectionStatus,
                        systemImage: item.needsUserReview
                            ? "questionmark.circle.fill"
                            : "checkmark.circle"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.needsUserReview ? Color.orange : Color.secondary)

                    if let savedSearch {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Live shopping results")
                            Text(searchPriceSummary(savedSearch))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if item.needsUserReview {
                VStack(alignment: .leading, spacing: 9) {
                    Text(GarmentDetectionQualityPolicy.reviewReason(for: item))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        correctionTarget = GarmentCorrectionTarget(
                            scanID: scan.id,
                            garmentID: item.id
                        )
                    } label: {
                        Label("Review detection", systemImage: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .stylezamGlassButton(prominent: true)
                    .tint(StylezamDesign.cobalt)
                }
                .padding(14)
                .background(
                    Color.orange.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
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
                .disabled(!item.isPipelineEligible)

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
                .disabled(!item.isPipelineEligible)

                Button {
                    correctionTarget = GarmentCorrectionTarget(
                        scanID: scan.id,
                        garmentID: item.id
                    )
                } label: {
                    Label("Correct detection", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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

private struct WardrobeItemCard: View {
    let item: SavedWardrobeItem
    let imageURL: URL
    let isOnRail: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalFileImage(url: imageURL, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .aspectRatio(0.78, contentMode: .fit)
                .padding(8)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if isOnRail {
                        Label(
                            isSelected ? "Selected" : "On rail",
                            systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .frame(height: 25)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                    }
                }

            Text(item.category.title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let product = item.sourceProduct {
                Text(
                    product.price.map { "\(product.merchant) · \($0.formatted)" }
                        ?? product.merchant
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.title), \(item.category.title)"
                + (isSelected ? ", selected on try-on rail" : isOnRail ? ", on try-on rail" : "")
        )
    }
}

private struct WardrobeItemDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: SavedWardrobeItem
    @State private var confirmsDeletion = false

    private var railEntry: TryOnRailEntry? {
        model.library.tryOnRail.first { $0.wardrobeItemID == item.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LocalFileImage(
                        url: model.library.imageURL(for: item),
                        contentMode: .fit
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.78, contentMode: .fit)
                    .padding(14)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(StylezamDesign.hairline, lineWidth: 0.75)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        EditorialKicker(text: item.category.title)
                        Text(item.title)
                            .font(.system(size: 30, weight: .semibold))
                            .tracking(-0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text((item.garmentRegion ?? .infer(
                                category: item.category,
                                title: item.title
                            )).title)
                            Text("·")
                            Text("Saved \(StylezamRelativeTime.string(since: item.savedAt)) ago")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        if railEntry?.isSelected == true {
                            Label("Selected on the try-on rail", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(StylezamDesign.cobalt)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    StylezamDesign.cobalt.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        } else {
                            CobaltActionButton(
                                title: "Select on try-on rail",
                                systemImage: "wand.and.sparkles"
                            ) {
                                model.library.addWardrobeItemToTryOnRail(item, selected: true)
                            }
                        }

                        if railEntry != nil {
                            Button {
                                model.library.removeFromTryOnRail(item.id)
                            } label: {
                                Label("Remove from try-on rail", systemImage: "minus.circle")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                            .stylezamGlassButton()
                        }
                    }

                    if let product = item.sourceProduct {
                        VStack(alignment: .leading, spacing: 13) {
                            EditorialSectionHeader(title: "Purchase", detail: product.merchant)
                            EditorialRule()
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(product.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                    Text(product.price?.formatted ?? "Price unavailable")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                Link(destination: product.productURL) {
                                    Label("View", systemImage: "arrow.up.right")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    } else {
                        Label(
                            "This detected piece does not have a saved purchase link yet.",
                            systemImage: "link.badge.plus"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Remove item from Library", systemImage: "trash", role: .destructive) {
                        confirmsDeletion = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 8)
                }
                .padding(StylezamDesign.pageInset)
                .padding(.bottom, 28)
            }
            .background(StylezamDesign.paper)
            .navigationTitle("Wardrobe item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove this item from Library?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Remove item", role: .destructive) {
                    model.library.deleteWardrobeItem(item)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will also be removed from the current try-on rail. Saved try-on manifests will not change.")
            }
        }
    }
}

private enum TryOnManifestTab: String, CaseIterable, Identifiable {
    case wearing
    case onRail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wearing: "Wearing"
        case .onRail: "On the rail"
        }
    }
}

private struct TryOnArchiveDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tryOn: SavedTryOn
    @State private var manifestTab: TryOnManifestTab = .wearing
    @State private var confirmsDeletion = false

    private var wearingItems: [SavedTryOnItemSnapshot] {
        tryOn.items.filter(\.wasSelected)
    }

    private var railItems: [SavedTryOnItemSnapshot] {
        tryOn.items.filter { !$0.wasSelected }
    }

    private var visibleManifestItems: [SavedTryOnItemSnapshot] {
        manifestTab == .wearing ? wearingItems : railItems
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LocalFileImage(url: model.library.imageURL(for: tryOn))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.72, contentMode: .fit)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
                        }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(tryOn.displayTitle)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Appearance preview · \(tryOn.createdAt.formatted(date: .long, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let context = tryOn.photoContext {
                            HStack(spacing: 6) {
                                Label(context.title, systemImage: "person.crop.rectangle")
                                if let gender = tryOn.gender {
                                    Text("·")
                                    Text(gender.title)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    ShareLink(item: model.library.imageURL(for: tryOn)) {
                        Label("Share preview", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .stylezamGlassButton(prominent: true)
                    .tint(StylezamDesign.cobalt)

                    manifest
                }
                .padding(StylezamDesign.pageInset)
                .padding(.bottom, 28)
            }
            .background(StylezamDesign.paper)
            .navigationTitle("Try-on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete", role: .destructive) {
                        confirmsDeletion = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this try-on?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete try-on", role: .destructive) {
                    model.library.deleteTryOn(tryOn)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The saved preview will be removed. Your wardrobe and current try-on rail will stay unchanged.")
            }
        }
    }

    @ViewBuilder
    private var manifest: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialRule()
            EditorialSectionHeader(title: "Outfit items", detail: "Saved with this look")

            if tryOn.items.isEmpty {
                legacyManifest
            } else {
                Picker("Saved outfit items", selection: $manifestTab) {
                    Text("Wearing \(wearingItems.count)")
                        .tag(TryOnManifestTab.wearing)
                    Text("On the rail \(railItems.count)")
                        .tag(TryOnManifestTab.onRail)
                }
                .pickerStyle(.segmented)

                Text(
                    manifestTab == .wearing
                        ? "These pieces were actually applied when this preview was created."
                        : "These pieces were available but not applied—they were toggled off or parked for another photo type."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    if visibleManifestItems.isEmpty {
                        Text(
                            manifestTab == .wearing
                                ? "No pieces were recorded as worn."
                                : "Every recorded rail item was applied."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                        .padding(.horizontal, 14)
                    } else {
                        ForEach(Array(visibleManifestItems.enumerated()), id: \.element.id) { index, item in
                            manifestRow(item)
                            if index < visibleManifestItems.count - 1 {
                                EditorialRule()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(StylezamDesign.hairline, lineWidth: 0.75)
                }
            }
        }
    }

    @ViewBuilder
    private var legacyManifest: some View {
        if let product = tryOn.product {
            manifestRow(
                title: product.title,
                category: TryOnCategory.infer(category: product.category, title: product.title),
                region: .infer(
                    category: TryOnCategory.infer(category: product.category, title: product.title),
                    title: product.category ?? product.title
                ),
                product: product
            )
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        } else {
            Label(
                "Item details were not stored for this earlier preview.",
                systemImage: "archivebox"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(.horizontal, 14)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private func manifestRow(_ item: SavedTryOnItemSnapshot) -> some View {
        manifestRow(
            title: item.title,
            category: item.category,
            region: item.garmentRegion,
            product: item.sourceProduct
        )
    }

    private func manifestRow(
        title: String,
        category: TryOnCategory,
        region: TryOnGarmentRegion,
        product: ProductResultDTO?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(StylezamDesign.cobalt)
                .frame(width: 34, height: 34)
                .background(
                    StylezamDesign.cobalt.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(manifestSubtitle(category: category, region: region, product: product))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let product {
                Link(destination: product.productURL) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("Buy", systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                        if let price = product.price {
                            Text(price.formatted)
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(StylezamDesign.cobalt)
                }
                .accessibilityLabel("Buy \(title) at \(product.merchant)")
            }
        }
        .padding(14)
    }

    private func manifestSubtitle(
        category: TryOnCategory,
        region: TryOnGarmentRegion,
        product: ProductResultDTO?
    ) -> String {
        [category.title, region.title, product?.merchant]
            .compactMap { $0 }
            .joined(separator: " · ")
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
