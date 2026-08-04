import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var section: LibrarySection = .recent
    @State private var selectedTryOn: SavedTryOn?
    @State private var selectedScan: SavedScan?
    @Namespace private var productTransition

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("Captures, separated pieces, saved products, and appearance previews kept on this iPhone.")
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
                        recentScans
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
        .animation(.easeInOut(duration: 0.2), value: section)
        .sensoryFeedback(.selection, trigger: section)
        .onChange(of: model.activeScanID, initial: true) { _, scanID in
            guard let scanID,
                  let scan = model.library.scans.first(where: { $0.id == scanID })
            else { return }
            section = .recent
            selectedScan = scan
            model.activeScanID = nil
        }
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
        case .saved: model.library.products.count
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
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(model.library.scans) { scan in
                        Button {
                            selectedScan = scan
                        } label: {
                            RecentScanTile(
                                scan: scan,
                                imageURL: model.library.imageURL(for: scan)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete capture", role: .destructive) {
                                model.deleteScan(scan)
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
        return "\(count) \(singular)s"
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

private struct RecentScanTile: View {
    let scan: SavedScan
    let imageURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalFileImage(url: imageURL)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.95, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            let acceptedCount = scan.items.filter(\.accepted).count
            Text(acceptedCount == 1 ? "1 piece" : "\(acceptedCount) pieces")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 5) {
                Text(scan.origin.libraryLabel)
                Text("·")
                Text(StylezamRelativeTime.string(since: scan.createdAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct ScanDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scanID: UUID

    private var scan: SavedScan? {
        model.library.scans.first { $0.id == scanID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let scan {
                    VStack(alignment: .leading, spacing: 24) {
                        LocalFileImage(
                            url: model.library.imageURL(for: scan),
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
                                    garmentRow(item)
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
                        ShareLink(item: model.library.imageURL(for: scan)) {
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
            Label("Labeling", systemImage: "ellipsis")
                .foregroundStyle(.secondary)
        case .enriched:
            Label("Ready", systemImage: "checkmark")
                .foregroundStyle(StylezamDesign.cobalt)
        case .unavailable:
            Label("On-device", systemImage: "iphone")
                .foregroundStyle(.secondary)
        }
    }

    private func garmentRow(_ item: SavedGarment) -> some View {
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
            .background(Color(uiColor: .secondarySystemBackground))
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
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
