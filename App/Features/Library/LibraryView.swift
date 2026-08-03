import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var section: LibrarySection = .recent
    @State private var selectedTryOn: SavedTryOn?
    @Namespace private var productTransition

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                sectionPicker
                    .padding(.top, 8)

                if let loadError = model.library.loadError {
                    InlineErrorView(message: loadError)
                }

                switch section {
                case .recent:
                    recentSearches
                case .saved:
                    savedProducts
                case .tryOns:
                    tryOnHistory
                }
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.bottom, 110)
        }
        .background(StylezamDesign.canvas)
        .navigationDestination(for: ProductResultDTO.self) { product in
            ProductDetailView(product: product)
                .navigationTransition(.zoom(sourceID: product.id, in: productTransition))
        }
        .sheet(item: $selectedTryOn) { tryOn in
            TryOnArchiveDetail(tryOn: tryOn)
                .environment(model)
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .animation(StylezamMotion.quickSpring, value: section)
    }

    private var sectionPicker: some View {
        Picker("Library section", selection: $section) {
            ForEach(LibrarySection.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: section)
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialSectionHeader(
                title: "Recent",
                detail: model.library.captures.isEmpty
                    ? "Empty"
                    : model.library.captures.count == 1
                        ? "1 search"
                        : "\(model.library.captures.count) searches"
            )

            if model.library.captures.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No searches yet",
                    message: "Photo, text, shared, and live-screen searches will appear here."
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.library.captures) { capture in
                        Button {
                            model.resumeSearch(
                                id: capture.searchID,
                                imageData: model.library.imageURL(for: capture).flatMap {
                                    try? Data(contentsOf: $0, options: .mappedIfSafe)
                                }
                            )
                        } label: {
                            RecentSearchRow(
                                capture: capture,
                                imageURL: model.library.imageURL(for: capture)
                            )
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            EditorialRule()
                                .padding(.leading, 77)
                        }
                        .contextMenu {
                            Button("Delete search", role: .destructive) {
                                model.deleteCapture(capture)
                            }
                        }
                    }
                }
            }
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var savedProducts: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialSectionHeader(
                title: "Saved",
                detail: model.library.products.isEmpty
                    ? "Empty"
                    : model.library.products.count == 1
                        ? "1 product"
                        : "\(model.library.products.count) products"
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
        .transition(.opacity)
    }

    private var tryOnHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialSectionHeader(
                title: "Try-ons",
                detail: model.library.tryOns.isEmpty
                    ? "Empty"
                    : model.library.tryOns.count == 1
                        ? "1 preview"
                        : "\(model.library.tryOns.count) previews"
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
                    spacing: 22
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
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text(message)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
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

private struct SavedProductCard: View {
    let saved: SavedProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductImage(url: saved.product.imageURL)
                .frame(maxWidth: .infinity)
                .aspectRatio(0.78, contentMode: .fit)
                .padding(8)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text((saved.product.brand ?? saved.product.merchant).uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
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

private struct RecentSearchRow: View {
    let capture: SavedCapture
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 13) {
            Group {
                if let imageURL {
                    LocalFileImage(url: imageURL)
                } else {
                    StylezamDesign.cobalt
                        .overlay {
                            Image(systemName: "magnifyingglass")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 64, height: 76)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(capture.query ?? capture.origin.libraryLabel)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(capture.origin.libraryLabel)
                    Text("·")
                    Text(capture.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 10)
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
