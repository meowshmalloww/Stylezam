import SwiftUI

struct FirstRunExperienceView: View {
    let completion: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        ZStack {
            StylezamDesign.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brandHeader
                    FirstRunHero(isPresented: isPresented, reduceMotion: reduceMotion)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 14) {
                        EditorialKicker(text: "VISUAL PRODUCT SEARCH")
                        Text("Find the pieces\nin any look.")
                            .font(.system(size: 42, weight: .semibold, design: .default))
                            .tracking(-1.65)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text("Choose a photo. Stylezam separates the outfit into individual pieces, then searches only the ones you select.")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 22)

                    FirstRunFlow()
                        .padding(.top, 18)
                        .padding(.bottom, 126)
                }
                .padding(.horizontal, StylezamDesign.pageInset)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 9) {
                Button(action: completion) {
                    HStack(spacing: 10) {
                        Text("Enter Stylezam")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 19)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .stylezamGlassButton(prominent: true)
                .tint(StylezamDesign.cobalt)

                Text("On-device detection · No account required")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            guard !isPresented else { return }
            if reduceMotion {
                isPresented = true
            } else {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.84)) {
                    isPresented = true
                }
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            BrandMarkView(size: 40)
            StylezamWordmark()
            Spacer()
            Text("PRIVATE BETA")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }
}

private struct FirstRunHero: View {
    let isPresented: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("OnboardingFashionHero")
                .resizable()
                .scaledToFill()
                .scaleEffect(isPresented || reduceMotion ? 1 : 1.035)

            LinearGradient(
                colors: [.clear, .black.opacity(0.05), .black.opacity(0.68)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("ONE LOOK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.68))
                Text("Every piece.")
                    .font(.system(size: 29, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
            }
            .padding(24)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 0.75)
        }
        .shadow(color: StylezamDesign.cobalt.opacity(0.16), radius: 24, y: 14)
        .opacity(isPresented ? 1 : 0)
        .offset(y: isPresented ? 0 : 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.85), value: isPresented)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Editorial outfit with a cobalt jacket, cream trousers, bag, and sneakers")
    }
}

private struct FirstRunFlow: View {
    private let steps: [(String, String)] = [
        ("photo", "CHOOSE"),
        ("square.3.layers.3d", "SEPARATE"),
        ("bag", "FIND")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 8) {
                    Image(systemName: step.0)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(index == steps.count - 1 ? StylezamDesign.cobalt : .primary)
                    Text(step.1)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.05)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(StylezamDesign.hairline)
                        .frame(width: 34, height: 1)
                }
            }
        }
        .padding(.vertical, 17)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Choose a photo, separate its pieces, and find matching products")
    }
}
