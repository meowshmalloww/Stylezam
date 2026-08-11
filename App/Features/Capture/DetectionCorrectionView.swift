import SwiftUI

struct GarmentCorrectionTarget: Identifiable, Hashable {
    let scanID: UUID
    let garmentID: String

    var id: String { "\(scanID.uuidString):\(garmentID)" }
}

struct DetectionCorrectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let target: GarmentCorrectionTarget
    var onFinished: () -> Void = {}

    @State private var showsMoreCategories = false
    @State private var errorMessage: String?

    private var garment: SavedGarment? {
        model.library.scans
            .first(where: { $0.id == target.scanID })?
            .items.first(where: { $0.id == target.garmentID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preview

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Correct this detection")
                            .font(.title2.weight(.semibold))
                        Text("Your choice stays on this iPhone and controls whether this crop can enter product search or virtual try-on.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(role: .destructive) {
                        apply(.notFashion)
                    } label: {
                        correctionRow(
                            title: "This is not fashion",
                            detail: "Reject this crop and remove its derived search or try-on items",
                            symbol: "xmark.circle"
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CHOOSE THE RIGHT TYPE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.85)
                            .foregroundStyle(.secondary)

                        correctionButton("T-shirt or top", symbol: "tshirt", category: .clothes)
                        correctionButton("Shirt or blouse", symbol: "tshirt", category: .clothes)
                        correctionButton("Jacket or blazer", symbol: "jacket", category: .clothes)
                        correctionButton("Pants or jeans", symbol: "figure.walk", category: .clothes)
                        correctionButton("Bag", symbol: "handbag", category: .bag)
                        correctionButton("Shoes", symbol: "shoe", category: .shoes)

                        DisclosureGroup("Another category", isExpanded: $showsMoreCategories) {
                            VStack(spacing: 10) {
                                correctionButton("Sweater or sweatshirt", symbol: "tshirt.fill", category: .clothes)
                                correctionButton("Cardigan", symbol: "jacket", category: .clothes)
                                correctionButton("Coat", symbol: "jacket.fill", category: .clothes)
                                correctionButton("Vest", symbol: "tshirt", category: .clothes)
                                correctionButton("Shorts", symbol: "figure.run", category: .clothes)
                                correctionButton("Skirt", symbol: "triangle", category: .clothes)
                                correctionButton("Dress or gown", symbol: "figure.dress.line.vertical.figure", category: .clothes)
                                correctionButton("Jumpsuit or romper", symbol: "figure.stand", category: .clothes)
                                correctionButton("Other clothing", symbol: "tshirt", category: .clothes)
                                correctionButton("Scarf", symbol: "wind", category: .scarf)
                                correctionButton("Hat", symbol: "hat.widebrim", category: .hat)
                                correctionButton("Ring", symbol: "circle", category: .ring)
                                correctionButton("Bracelet", symbol: "circle.dashed", category: .bracelet)
                                correctionButton("Earrings", symbol: "ear", category: .earring)
                                correctionButton("Watch", symbol: "applewatch", category: .watch)
                                correctionButton("Necklace", symbol: "scribble.variable", category: .necklace)
                            }
                            .padding(.top, 10)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(
                            Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }
                .padding(StylezamDesign.pageInset)
                .padding(.bottom, 28)
            }
            .background(StylezamDesign.canvas)
            .navigationTitle("Detection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Couldn’t save the correction",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Try again.")
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let garment {
            HStack(spacing: 15) {
                Group {
                    if let url = model.library.cropURL(for: garment) {
                        LocalFileImage(url: url, contentMode: .fit)
                    } else {
                        Color(uiColor: .secondarySystemBackground)
                            .overlay { Image(systemName: "viewfinder") }
                    }
                }
                .frame(width: 104, height: 122)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(garment.localLabel.capitalized)
                        .font(.headline)
                    Label(garment.userFacingDetectionStatus, systemImage: "questionmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func correctionButton(
        _ title: String,
        symbol: String,
        category: TryOnCategory
    ) -> some View {
        Button {
            apply(.fashion(category: category, label: title))
        } label: {
            correctionRow(
                title: title,
                detail: category == .clothes ? "Clothing" : category.title,
                symbol: symbol
            )
        }
        .buttonStyle(.plain)
    }

    private func correctionRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func apply(_ correction: GarmentDetectionCorrection) {
        do {
            try model.correctDetection(
                scanID: target.scanID,
                garmentID: target.garmentID,
                correction: correction
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onFinished()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
