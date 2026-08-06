import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                brandHeader
                editorialHero
                quickStart
                recentSection

                if !model.library.products.isEmpty {
                    savedSection
                }
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 104)
        }
        .background(StylezamDesign.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: ProductResultDTO.self) { product in
            ProductDetailView(product: product)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            BrandMarkView(size: 36)
            StylezamWordmark()
            Spacer()
            Text(Date.now.formatted(.dateTime.weekday(.wide)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var editorialHero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.035, green: 0.055, blue: 0.11))

            HomeEditorialDecoration()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("STYLE DISCOVERY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.62))
                Text("Keep the look.\nSeparate the pieces.")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-1.25)
                    .foregroundStyle(.white)
                Text("Camera, live screen, or an image you already have.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .padding(22)
        }
        .frame(height: 218)
        .accessibilityElement(children: .combine)
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: "Start somewhere")
            HStack(spacing: 12) {
                quickAction(
                    title: "Capture",
                    detail: "Front or back camera",
                    icon: "camera"
                ) {
                    model.presentCamera()
                }

                quickAction(
                    title: "Add image",
                    detail: "Photos or clipboard",
                    icon: "photo.badge.plus"
                ) {
                    model.selectedTab = .search
                }
            }
        }
    }

    private func quickAction(
        title: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3.weight(.medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(HomePressButtonStyle())
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HomeSectionHeader(title: "Recent") {
                model.selectedTab = .library
            }

            if model.library.scans.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Your captured looks will collect here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 14)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(model.library.scans.prefix(6)) { scan in
                            Button {
                                model.activeScanID = scan.id
                                model.selectedTab = .library
                            } label: {
                                HomeRecentCard(
                                    scan: scan,
                                    imageURL: model.library.displayImageURL(for: scan)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 0, for: .scrollContent)
            }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HomeSectionHeader(title: "Saved") {
                model.selectedTab = .library
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(model.library.products.prefix(6)) { saved in
                        NavigationLink(value: saved.product) {
                            HomeSavedCard(saved: saved)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

}

private struct HomeSectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.semibold))
            Spacer()
            if let action {
                Button("View all", action: action)
                    .font(.subheadline.weight(.medium))
            }
        }
    }
}

private struct HomeRecentCard: View {
    let scan: SavedScan
    let imageURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalFileImage(url: imageURL)
            .frame(width: 154, height: 116)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            let count = scan.items.filter(\.accepted).count
            Text(count == 1 ? "1 piece" : "\(count) pieces")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(width: 154, alignment: .leading)
            Text(StylezamRelativeTime.string(since: scan.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HomeSavedCard: View {
    let saved: SavedProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ProductImage(url: saved.product.imageURL)
                .frame(width: 154, height: 174)
                .padding(7)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(saved.product.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(width: 154, alignment: .leading)
        }
    }
}

private struct HomeEditorialDecoration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(StylezamDesign.cobalt.opacity(0.95))
                .frame(width: 118, height: 198)
                .rotationEffect(.degrees(24))
                .offset(x: 58, y: -16)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.13))
                .frame(width: 92, height: 158)
                .rotationEffect(.degrees(-17))
                .offset(x: 90, y: 70)
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .frame(width: 74, height: 124)
                .rotationEffect(.degrees(9))
                .offset(x: 32, y: 60)
        }
        .frame(width: 190, height: 218)
    }
}

private struct HomePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
