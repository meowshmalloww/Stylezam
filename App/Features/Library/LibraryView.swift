import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var section: LibrarySection = .recent
    @State private var selectedTryOn: SavedTryOn?
    @Namespace private var productTransition

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("Search history, products, and appearance previews saved on this iPhone.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                categoryBar

                if let loadError = model.library.loadError {
                    InlineErrorView(message: loadError)
                }

                Group {
                    switch section {
                    case .recent:
                        recentSearches
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
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: ProductResultDTO.self) { product in
            ProductDetailView(product: product)
                .navigationTransition(.zoom(sourceID: product.id, in: productTransition))
        }
        .sheet(item: $selectedTryOn) { tryOn in
            TryOnArchiveDetail(tryOn: tryOn)
                .environment(model)
        }
        .animation(.easeInOut(duration: 0.2), value: section)
        .sensoryFeedback(.selection, trigger: section)
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
        case .recent: model.library.captures.count
        case .saved: model.library.products.count
        case .tryOns: model.library.tryOns.count
        }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(
                title: "Search history",
                detail: countLabel(model.library.captures.count, singular: "search")
            )

            if model.library.captures.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No searches yet",
                    message: "Camera, photo, text, shared, and screen searches will appear here."
                )
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(model.library.captures) { capture in
                        Button {
                            resume(capture)
                        } label: {
                            RecentSearchTile(
                                capture: capture,
                                imageURL: model.library.imageURL(for: capture)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete search", role: .destructive) {
                                model.deleteCapture(capture)
                            }
                        }
                    }
                }
            }
        }
    }

    private var savedProducts: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(
                title: "Saved pieces",
                detail: countLabel(model.library.products.count, singular: "product")
            )

            if model.library.products.isEmpty {
                emptyState(
                    icon: "bookmark",
                    title: "Nothing saved",
                    message: "Bookmark a product match and it will stay here for later."
                )
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    alignment: .leading,
                    spacing: 26
                ) {
                    ForEach(model.library.products) { saved in
                        NavigationLink(value: saved.product) {
                            SavedProductCard(saved: saved)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: saved.product.id, in: productTransition)
                        .contextMenu {
                            Button("Remove from saved", role: .destructive) {
                                model.library.toggleSaved(saved.product)
                            }
                        }
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
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(model.library.tryOns) { tryOn in
                        Button {
                            selectedTryOn = tryOn
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                LocalFileImage(url: model.library.imageURL(for: tryOn))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(0.78, contentMode: .fit)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(tryOn.product.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                Text(tryOn.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete try-on", role: .destructive) {
                                model.library.deleteTryOn(tryOn)
                            }
                        }
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
        return singular == "search" ? "\(count) searches" : "\(count) \(singular)s"
    }

    private func resume(_ capture: SavedCapture) {
        model.resumeSearch(
            id: capture.searchID,
            imageData: model.library.imageURL(for: capture).flatMap {
                try? Data(contentsOf: $0, options: .mappedIfSafe)
            }
        )
    }
}

private enum LibrarySection: String, CaseIterable, Identifiable {
    case recent
    case saved
    case tryOns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .saved: "Saved"
        case .tryOns: "Try-ons"
        }
    }
}

private struct RecentSearchTile: View {
    let capture: SavedCapture
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let imageURL {
                    LocalFileImage(url: imageURL)
                } else {
                    Color(uiColor: .secondarySystemBackground)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.system(size: 34, weight: .light))
                                Text("TEXT SEARCH")
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(1.1)
                            }
                            .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.95, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(capture.query ?? capture.origin.libraryLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 5) {
                Text(capture.origin.libraryLabel)
                Text("·")
                Text(StylezamRelativeTime.string(since: capture.createdAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
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
                    Text(tryOn.product.title)
                        .font(.title2.weight(.semibold))
                    Text("Appearance preview · \(tryOn.createdAt.formatted(date: .long, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ShareLink(item: model.library.imageURL(for: tryOn)) {
                        Label("Share preview", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
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
