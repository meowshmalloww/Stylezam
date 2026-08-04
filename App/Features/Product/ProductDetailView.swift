import SwiftUI

struct ProductDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let product: ProductResultDTO

    @State private var heroVisible = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                productHero

                VStack(alignment: .leading, spacing: 28) {
                    identity
                        .motionReveal()
                    evidence
                        .motionReveal(delay: 0.06)

                    if !product.offers.isEmpty {
                        offers
                            .motionReveal(delay: 0.11)
                    }

                    EditorialRule()

                    Text("Prices and availability are observations from configured sources. Confirm the product, seller, shipping, and returns on the merchant page. Virtual previews visualize appearance and do not predict size or fit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, StylezamDesign.pageInset)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
        }
        .background(StylezamDesign.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: product.productURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    model.library.toggleSaved(product)
                } label: {
                    Image(systemName: model.library.isSaved(product) ? "bookmark.fill" : "bookmark")
                        .symbolEffect(.bounce, value: model.library.isSaved(product))
                }
                .accessibilityLabel(model.library.isSaved(product) ? "Remove bookmark" : "Bookmark")
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sensoryFeedback(.success, trigger: model.library.isSaved(product))
    }

    private var productHero: some View {
        GeometryReader { proxy in
            let pullDown = max(proxy.frame(in: .scrollView).minY, 0)

            ZStack(alignment: .bottomLeading) {
                Color.white
                ProductImage(url: product.imageURL)
                    .padding(24)
                    .scaleEffect(heroVisible ? 1 : 1.08)
                    .opacity(heroVisible ? 1 : 0)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.06)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                EditorialKicker(text: "Observed at \(product.merchant)", color: .black.opacity(0.62))
                    .padding(18)
                    .motionReveal(delay: 0.12, distance: 8)
            }
            .frame(height: 510 + pullDown)
            .offset(y: -pullDown)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 510)
        .clipped()
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.88)) {
                heroVisible = true
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let brand = product.brand {
                EditorialKicker(text: brand)
            }
            Text(product.title)
                .font(.system(size: 33, weight: .semibold))
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline) {
                Text(product.price?.formatted ?? "Price unavailable")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(product.merchant.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(title: "Match evidence", detail: "Not identity proof")

            EditorialRule()

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.matchTier.label)
                        .font(.title2.weight(.semibold))
                    Text("match tier")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.confidencePercent, format: .number)
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Text("evidence score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            EditorialRule()

            Text(matchExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var offers: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSectionHeader(title: "Observed offers", detail: "\(product.offers.count) live links")
                .padding(.bottom, 7)

            ForEach(Array(product.offers.enumerated()), id: \.offset) { index, offer in
                Button {
                    openURL(offer.url)
                } label: {
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", index + 1))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(StylezamDesign.cobalt)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(offer.merchant)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let condition = offer.condition {
                                Text(condition)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(offer.price?.formatted ?? "View")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .motionScrollDepth()

                if index < product.offers.count - 1 {
                    EditorialRule()
                }
            }
        }
    }

    private var actionBar: some View {
        GlassEffectContainer(spacing: 10) {
            Button {
                model.addToTryOn(product)
            } label: {
                Label("Try on", systemImage: "wand.and.sparkles")
                    .fontWeight(.semibold)
                    .frame(height: 54)
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.glass)
            Button {
                openURL(product.productURL)
            } label: {
                merchantButtonLabel
            }
            .buttonStyle(.glassProminent)
            .tint(StylezamDesign.cobalt)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .motionReveal(delay: 0.16, distance: 10)
    }

    private var merchantButtonLabel: some View {
        HStack {
            Text("View at \(product.merchant)")
                .fontWeight(.semibold)
                .lineLimit(1)
            Image(systemName: "arrow.up.right")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
    }

    private var matchExplanation: String {
        switch product.matchTier {
        case .exact:
            "The source reported exact-match evidence and the combined visual and attribute score stayed high. Confirm the SKU and details on the merchant page."
        case .likely:
            "The title, visible attributes, and retrieval evidence align closely, but Stylezam cannot prove that this is the exact SKU."
        case .similar:
            "The silhouette or visible attributes are close, while brand, material, color, or construction may differ."
        case .inspired:
            "This result shares parts of the captured style but is not presented as the same product."
        }
    }
}
