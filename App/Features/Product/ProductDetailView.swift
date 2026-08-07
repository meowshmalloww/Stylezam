import SwiftUI

struct ProductDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let product: ProductResultDTO

    @State private var heroVisible = false
    @State private var addToTryOnTask: Task<Void, Never>?
    @State private var isAddingToTryOn = false
    @State private var tryOnErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                productHero

                VStack(alignment: .leading, spacing: 28) {
                    identity
                        .motionReveal()
                    actionBar
                        .motionReveal(delay: 0.04)
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
                .padding(.bottom, 54)
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
        .sensoryFeedback(.success, trigger: model.library.isSaved(product))
        .alert(
            "Couldn’t add this piece",
            isPresented: Binding(
                get: { tryOnErrorMessage != nil },
                set: { if !$0 { tryOnErrorMessage = nil } }
            )
        ) {
            Button("OK") { tryOnErrorMessage = nil }
        } message: {
            Text(tryOnErrorMessage ?? "Try again in a moment.")
        }
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
            .frame(height: heroHeight + pullDown)
            .offset(y: -pullDown)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .clipped()
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.88)) {
                heroVisible = true
            }
        }
    }

    private var heroHeight: CGFloat {
        verticalSizeClass == .compact ? 270 : 390
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
            EditorialSectionHeader(title: "Why it appeared", detail: product.matchSummaryLabel)

            EditorialRule()

            Text(matchExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Retrieved by \(product.provider)", systemImage: "network")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var offers: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSectionHeader(title: "Compare sellers", detail: "\(comparisonOffers.count) observed")
                .padding(.bottom, 13)

            HStack {
                Text("SELLER")
                Spacer()
                Text("OBSERVED PRICE")
            }
            .font(.caption2.weight(.bold))
            .tracking(0.75)
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)

            ForEach(Array(comparisonOffers.enumerated()), id: \.offset) { index, offer in
                Button {
                    openURL(offer.url)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(offer.merchant)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if index == 0, offer.price != nil {
                                    Text("LOWEST")
                                        .font(.system(size: 8, weight: .bold))
                                        .tracking(0.6)
                                        .foregroundStyle(StylezamDesign.cobalt)
                                        .padding(.horizontal, 6)
                                        .frame(height: 19)
                                        .background(StylezamDesign.cobalt.opacity(0.09), in: Capsule())
                                }
                            }
                            if let condition = offer.condition {
                                Text(condition)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if offer.url == product.productURL {
                                Text("Primary result")
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
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .motionScrollDepth()

                if index < comparisonOffers.count - 1 {
                    EditorialRule()
                }
            }
        }
    }

    private var comparisonOffers: [MerchantOfferDTO] {
        let primary = MerchantOfferDTO(
            merchant: product.merchant,
            url: product.productURL,
            price: product.price,
            shipping: nil,
            condition: nil
        )
        return ([primary] + product.offers).sorted { left, right in
            switch (left.price, right.price) {
            case let (leftPrice?, rightPrice?) where leftPrice.currency == rightPrice.currency:
                if leftPrice.amount != rightPrice.amount { return leftPrice.amount < rightPrice.amount }
                return left.merchant.localizedCaseInsensitiveCompare(right.merchant) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return left.merchant.localizedCaseInsensitiveCompare(right.merchant) == .orderedAscending
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                addProductToTryOn()
            } label: {
                HStack {
                    Text(isAddingToTryOn ? "Adding to try-on…" : "Try on this piece")
                        .fontWeight(.semibold)
                    Spacer()
                    if isAddingToTryOn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "wand.and.sparkles")
                    }
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .stylezamGlassButton(prominent: true)
            .tint(StylezamDesign.cobalt)
            .disabled(isAddingToTryOn)

            Button {
                openURL(product.productURL)
            } label: {
                merchantButtonLabel
            }
            .stylezamGlassButton()
        }
    }

    private func addProductToTryOn() {
        guard addToTryOnTask == nil else { return }
        tryOnErrorMessage = nil
        isAddingToTryOn = true

        let task = model.addToTryOn(product)
        addToTryOnTask = task
        Task { @MainActor in
            await task.value
            addToTryOnTask = nil
            isAddingToTryOn = false
            if !model.isTryOnPresented {
                tryOnErrorMessage = model.lastError
                    ?? "Stylezam couldn’t prepare this product image for try-on. Try again or choose another product photo."
            }
        }
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
            "The visual-search source found similar shape, color, or construction. Brand, material, and the exact model may still differ, so verify the merchant photo and title."
        case .inspired:
            "This result shares part of the captured style, but the visual evidence is weaker. Treat it as an alternative—not the same product."
        }
    }
}
