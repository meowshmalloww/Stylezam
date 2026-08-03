import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var productTransition

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                PageTitle(
                    title: "Saved",
                    subtitle: "Products you bookmarked and the real searches you created on this device."
                )
                .padding(.top, 18)
                .motionReveal()

                if let loadError = model.library.loadError {
                    InlineErrorView(message: loadError)
                }

                savedProducts
                    .motionReveal(delay: 0.06)
                captureHistory
                    .motionReveal(delay: 0.12)
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.bottom, 110)
        }
        .background(StylezamDesign.canvas)
        .navigationDestination(for: ProductResultDTO.self) { product in
            ProductDetailView(product: product)
                .navigationTransition(.zoom(sourceID: product.id, in: productTransition))
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var savedProducts: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialSectionHeader(
                title: "Saved products",
                detail: model.library.products.isEmpty ? "Empty" : "\(model.library.products.count) saved"
            )

            if model.library.products.isEmpty {
                archiveEmptyState(
                    number: "01",
                    title: "No products saved",
                    message: "Bookmark a source-backed match and it will remain here on this device."
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
                    ForEach(Array(model.library.products.enumerated()), id: \.element.id) { index, saved in
                        NavigationLink(value: saved.product) {
                            SavedProductCard(saved: saved)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: saved.product.id, in: productTransition)
                        .motionReveal(delay: min(Double(index) * 0.045, 0.24))
                        .motionScrollDepth()
                        .contextMenu {
                            Button("Remove bookmark", role: .destructive) {
                                model.library.toggleSaved(saved.product)
                            }
                        }
                    }
                }
            }
        }
    }

    private var captureHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialSectionHeader(
                title: "Search history",
                detail: model.library.captures.isEmpty ? "Empty" : "\(model.library.captures.count) captures"
            )

            if model.library.captures.isEmpty {
                archiveEmptyState(
                    number: "02",
                    title: "No searches yet",
                    message: "Camera, Photos, Screenshot Shortcut, words, and Share sheet searches appear here."
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(model.library.captures) { capture in
                            Button {
                                model.resumeSearch(
                                    id: capture.searchID,
                                    imageData: model.library.imageURL(for: capture).flatMap {
                                        try? Data(contentsOf: $0)
                                    }
                                )
                            } label: {
                                CaptureHistoryCard(
                                    capture: capture,
                                    imageURL: model.library.imageURL(for: capture)
                                )
                            }
                            .buttonStyle(.plain)
                            .motionScrollDepth()
                            .contextMenu {
                                Button("Delete search", role: .destructive) {
                                    model.deleteCapture(capture)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func archiveEmptyState(number: String, title: String, message: String) -> some View {
        SurfaceCard {
            HStack(spacing: 15) {
                OrbitingBrandMark(size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    EditorialKicker(text: "Collection \(number)", color: StylezamDesign.cobalt)
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
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
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let brand = saved.product.brand {
                EditorialKicker(text: brand)
            }
            Text(saved.product.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            HStack {
                Text(saved.product.price?.formatted ?? "Price unavailable")
                Spacer()
                Text(saved.product.matchTier.label.uppercased())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }
}

private struct CaptureHistoryCard: View {
    let capture: SavedCapture
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let imageURL {
                    LocalFileImage(url: imageURL)
                } else {
                    ZStack {
                        Color.black
                        Text("Aa")
                            .font(.system(size: 52, weight: .black))
                            .fontWidth(.condensed)
                            .foregroundStyle(StylezamDesign.cobalt)
                    }
                }
            }
            .frame(width: 158, height: 190)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            EditorialKicker(text: capture.origin.archiveLabel)
            Text(capture.query ?? "Image search")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 158, alignment: .leading)
            Text(capture.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private extension CaptureOrigin {
    var archiveLabel: String {
        switch self {
        case .camera: "Camera"
        case .photoLibrary: "Photos"
        case .text: "Words"
        case .clipboard: "Clipboard"
        case .shareExtension: "Shared"
        case .screenCapture: "Screen"
        }
    }
}
