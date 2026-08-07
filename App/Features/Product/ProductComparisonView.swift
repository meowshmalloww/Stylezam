import SwiftUI

struct ProductComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let products: [ProductResultDTO]

    private let labelWidth: CGFloat = 88
    private let productWidth: CGFloat = 164

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        EditorialKicker(text: "Purchase workspace")
                        Text("Compare the evidence.")
                            .font(.system(size: 31, weight: .semibold))
                            .tracking(-0.8)
                        Text("Observed prices and product details can change. Open the store to confirm shipping, size, and returns.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ScrollView(.horizontal) {
                        Grid(horizontalSpacing: 12, verticalSpacing: 0) {
                            productHeader
                            comparisonRow(title: "PRICE") { product in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.price?.formatted ?? "Unavailable")
                                        .font(.subheadline.weight(.semibold))
                                    if isLowestComparablePrice(product) {
                                        Text("LOWEST OBSERVED")
                                            .font(.system(size: 8, weight: .bold))
                                            .tracking(0.7)
                                            .foregroundStyle(StylezamDesign.cobalt)
                                    }
                                }
                            }
                            comparisonRow(title: "MATCH") { product in
                                Text(product.matchSummaryLabel)
                            }
                            comparisonRow(title: "STORE") { product in
                                Text(product.merchant)
                            }
                            comparisonRow(title: "BRAND") { product in
                                Text(product.brand ?? "Not listed")
                            }
                            comparisonRow(title: "COLOR") { product in
                                Text(product.color ?? "Not listed")
                            }
                            comparisonRow(title: "RATING") { product in
                                Text(ratingText(product))
                            }

                            GridRow(alignment: .center) {
                                Color.clear
                                    .frame(width: labelWidth, height: 52)
                                ForEach(products) { product in
                                    Button {
                                        openURL(product.productURL)
                                    } label: {
                                        Label("Open store", systemImage: "arrow.up.right")
                                            .font(.caption.weight(.semibold))
                                            .frame(width: productWidth, height: 44)
                                    }
                                    .stylezamGlassButton(prominent: true)
                                    .tint(StylezamDesign.cobalt)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .padding(1)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(StylezamDesign.pageInset)
                .padding(.bottom, 30)
            }
            .background(StylezamDesign.canvas)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var productHeader: some View {
        GridRow(alignment: .bottom) {
            Text("PRODUCT")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)

            ForEach(products) { product in
                VStack(alignment: .leading, spacing: 8) {
                    ProductImage(url: product.imageURL)
                        .frame(width: productWidth, height: 142)
                        .padding(8)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    Text(product.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                        .frame(width: productWidth, alignment: .topLeading)
                        .frame(minHeight: 58, alignment: .topLeading)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private func comparisonRow<Content: View>(
        title: String,
        @ViewBuilder content: @escaping (ProductResultDTO) -> Content
    ) -> some View {
        GridRow(alignment: .center) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)

            ForEach(products) { product in
                content(product)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(width: productWidth, alignment: .leading)
                    .frame(minHeight: 54, alignment: .leading)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StylezamDesign.hairline)
                .frame(height: 0.75)
        }
    }

    private func ratingText(_ product: ProductResultDTO) -> String {
        guard let rating = product.rating else { return "Not listed" }
        if let reviewCount = product.reviewCount {
            return "\(rating.formatted(.number.precision(.fractionLength(1)))) · \(reviewCount) reviews"
        }
        return rating.formatted(.number.precision(.fractionLength(1)))
    }

    private func isLowestComparablePrice(_ product: ProductResultDTO) -> Bool {
        guard let price = product.price else { return false }
        let comparable = products.compactMap(\.price).filter { $0.currency == price.currency }
        guard comparable.count >= 2, let lowest = comparable.map(\.amount).min() else { return false }
        return price.amount == lowest
    }
}
