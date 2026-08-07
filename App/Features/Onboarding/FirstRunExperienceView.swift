import SwiftUI

struct FirstRunExperienceView: View {
    let completion: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: FirstRunPage = .welcome

    var body: some View {
        GeometryReader { proxy in
            TabView(selection: $page) {
                ForEach(FirstRunPage.allCases) { item in
                    FirstRunPageView(
                        page: item,
                        availableHeight: proxy.size.height
                    )
                    .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(StylezamDesign.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .background(StylezamDesign.canvas)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMarkView(size: 34)
            StylezamWordmark()
            Spacer()
            Text("\(page.rawValue + 1, format: .number.precision(.integerLength(2))) / \(FirstRunPage.allCases.count, format: .number.precision(.integerLength(2)))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, StylezamDesign.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if page != .welcome {
                Button {
                    move(to: page.previous)
                } label: {
                    Text("Back")
                        .font(.headline)
                        .frame(width: 72, height: 54)
                }
                .stylezamGlassButton()
            }

            Button {
                if let next = page.next {
                    move(to: next)
                } else {
                    completion()
                }
            } label: {
                HStack(spacing: 9) {
                    Text(page == .ready ? "Start Stylezam" : "Continue")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .stylezamGlassButton(prominent: true)
            .tint(StylezamDesign.cobalt)
        }
        .padding(.horizontal, StylezamDesign.pageInset)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func move(to destination: FirstRunPage?) {
        guard let destination else { return }
        if reduceMotion {
            page = destination
        } else {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
                page = destination
            }
        }
    }
}

private enum FirstRunPage: Int, CaseIterable, Identifiable {
    case welcome
    case separate
    case remember
    case discover
    case everywhere
    case ready

    var id: Int { rawValue }

    var previous: FirstRunPage? {
        FirstRunPage(rawValue: rawValue - 1)
    }

    var next: FirstRunPage? {
        FirstRunPage(rawValue: rawValue + 1)
    }
}

private struct FirstRunPageView: View {
    let page: FirstRunPage
    let availableHeight: CGFloat

    var body: some View {
        ScrollView {
            Group {
                switch page {
                case .welcome:
                    welcome
                case .separate:
                    separation
                case .remember:
                    memory
                case .discover:
                    discovery
                case .everywhere:
                    captureEverywhere
                case .ready:
                    ready
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding page \(page.rawValue + 1) of \(FirstRunPage.allCases.count)")
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingEditorialHero(
                height: min(360, max(280, availableHeight * 0.43))
            )
            .motionReveal(distance: 12)

            VStack(alignment: .leading, spacing: 8) {
                EditorialKicker(text: "A VISUAL FASHION COMPANION")
                Text("Find what caught\nyour eye.")
                    .onboardingTitle()
                Text("Begin with a look from the camera, Photos, or another app. Stylezam separates the pieces and keeps every next step under your control.")
                    .onboardingBody()
            }
            .motionReveal(delay: 0.08, distance: 12)

            HStack(spacing: 16) {
                OnboardingFact(number: "01", text: "Capture the whole look")
                EditorialRule().frame(maxWidth: 34)
                OnboardingFact(number: "02", text: "Keep only what matters")
            }
            .motionReveal(delay: 0.15, distance: 10)
        }
    }

    private var separation: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                EditorialKicker(text: "ONE LOOK · MANY PIECES")
                Text("Keep the outfit.\nSee the pieces.")
                    .onboardingTitle()
                Text("On device vision finds garments and accessories, then saves readable crops beside the original photo.")
                    .onboardingBody()
            }
            .motionReveal()

            LookBreakdownArtwork(
                height: min(340, max(270, availableHeight * 0.4))
            )
            .motionReveal(delay: 0.08, distance: 12)

            Label("Detection, boxes, and crop creation stay on this iPhone.", systemImage: "iphone.gen3")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .motionReveal(delay: 0.14, distance: 8)
        }
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                EditorialKicker(text: "YOUR NEXT MOVE")
                Text("See it. Search it.\nMake it yours.")
                    .onboardingTitle()
                Text("Every action begins with the piece you selected. Nothing searches or uploads in the background.")
                    .onboardingBody()
            }
            .motionReveal()

            VStack(spacing: 10) {
                OnboardingRouteCard(
                    number: "01",
                    icon: "viewfinder",
                    title: "Search from the image",
                    detail: "Find matching pages and visually similar products online."
                )
                OnboardingRouteCard(
                    number: "02",
                    icon: "text.bubble",
                    title: "Ask Stylezam",
                    detail: "Refine the look in words, then search similar or cheaper options."
                )
                OnboardingRouteCard(
                    number: "03",
                    icon: "figure.stand.dress",
                    title: "Try it on",
                    detail: "Pair a supported product with a photo you explicitly choose."
                )
            }
            .motionReveal(delay: 0.08, distance: 12)
        }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                EditorialKicker(text: "SCAN ONCE · REMEMBERED LOCALLY")
                Text("Recognize it later.\nSkip the duplicate.")
                    .onboardingTitle()
                Text("Live camera and Live Screen share one private visual memory. Once a crop is in your Library, Stylezam recognizes the same piece instead of saving it again.")
                    .onboardingBody()
            }
            .motionReveal()

            ScanMemoryArtwork(
                height: min(330, max(260, availableHeight * 0.38))
            )
            .motionReveal(delay: 0.08, distance: 12)

            Label("The visual signature stays on this iPhone and is forgotten when you delete the capture.", systemImage: "lock.iphone")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .motionReveal(delay: 0.14, distance: 8)
        }
    }

    private var captureEverywhere: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                EditorialKicker(text: "READY WHEN STYLE APPEARS")
                Text("Bring Stylezam\nto the moment.")
                    .onboardingTitle()
                Text("Open the camera inside Stylezam, scan another app with Live Screen, or launch a capture from Control Center and Shortcuts.")
                    .onboardingBody()
            }
            .motionReveal()

            VStack(spacing: 10) {
                OnboardingRouteCard(
                    number: "01",
                    icon: "camera.viewfinder",
                    title: "Camera",
                    detail: "Use Photo for one careful capture or Live for continuous local detection."
                )
                OnboardingRouteCard(
                    number: "02",
                    icon: "rectangle.on.rectangle",
                    title: "Live Screen",
                    detail: "Add the Stylezam control in Control Center, then choose Live Screen to inspect what is visible."
                )
                OnboardingRouteCard(
                    number: "03",
                    icon: "command",
                    title: "Shortcuts",
                    detail: "Add a Stylezam action to a Shortcut for a capture flow you can launch from anywhere."
                )
            }
            .motionReveal(delay: 0.08, distance: 12)

            Label("iOS always shows its screen sharing indicator while Live Screen is active.", systemImage: "checkmark.shield")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .motionReveal(delay: 0.14, distance: 8)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                EditorialKicker(text: "DESIGNED AROUND YOUR CHOICE")
                Text("Private by default.\nConnected on demand.")
                    .onboardingTitle()
                Text("Stylezam separates local fashion tools from the services that need a network connection, so you always know when a photo may leave your device.")
                    .onboardingBody()
            }
            .motionReveal()

            PrivacyBoundaryArtwork()
                .motionReveal(delay: 0.08, distance: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("YOU'RE READY")
                    .font(.caption2.weight(.bold))
                    .tracking(1.25)
                    .foregroundStyle(StylezamDesign.cobalt)
                Text("Begin with one look. The rest stays under your control.")
                    .font(.title3.weight(.semibold))
                    .tracking(-0.25)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .motionReveal(delay: 0.14, distance: 8)
        }
    }
}

private struct ScanMemoryArtwork: View {
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, StylezamDesign.cobalt.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        sourceTile(icon: "camera", title: "Live camera")
                        sourceTile(icon: "rectangle.on.rectangle", title: "Live Screen")
                    }

                    HStack(spacing: 10) {
                        Rectangle().fill(StylezamDesign.hairline).frame(height: 1)
                        Image(systemName: "arrow.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StylezamDesign.cobalt)
                        Rectangle().fill(StylezamDesign.hairline).frame(height: 1)
                    }

                    HStack(spacing: 16) {
                        ZStack {
                            LinearGradient(
                                colors: [StylezamDesign.cobalt.opacity(0.1), .white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "handbag.fill")
                                .font(.system(size: 43, weight: .medium))
                                .foregroundStyle(StylezamDesign.cobalt)
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(StylezamDesign.cobalt, lineWidth: 2)
                                .padding(13)
                        }
                        .frame(width: 96, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        VStack(alignment: .leading, spacing: 7) {
                            Label("Piece saved", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(StylezamDesign.cobalt)
                            Text("Future matches are recognized without another Library copy.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(22)
            }
            .frame(width: proxy.size.width, height: height)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live camera and Live Screen share one private garment memory")
    }

    private func sourceTile(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2.weight(.medium))
                .foregroundStyle(StylezamDesign.cobalt)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
    }
}

private struct OnboardingEditorialHero: View {
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [StylezamDesign.cobaltDeep, StylezamDesign.cobalt],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: geometry.size.width * 0.82)
                    .blur(radius: 1)
                    .offset(x: geometry.size.width * 0.28, y: -height * 0.25)

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
                    .padding(18)

                VStack {
                    HStack {
                        Text("CAPTURE · SEPARATE · DISCOVER")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.35)
                            .foregroundStyle(.white.opacity(0.76))
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                            .accessibilityLabel("Private by default")
                    }
                    Spacer()
                }
                .padding(20)

                HStack(spacing: 12) {
                    heroGlyph("tshirt.fill", offset: -14)
                    heroGlyph("handbag.fill", offset: 8)
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 86, height: 86)
                            .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(StylezamDesign.cobalt)
                    }
                    .accessibilityHidden(true)
                    heroGlyph("watch.analog", offset: 8)
                    heroGlyph("shoe.2.fill", offset: -14)
                }
                .padding(.horizontal, 22)

                VStack(alignment: .leading, spacing: 5) {
                    Spacer()
                    Text("STYLEZAM / VISUAL SEARCH")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.62))
                    Text("Start with what you see.")
                        .font(.system(size: 25, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        }
        .shadow(color: StylezamDesign.cobalt.opacity(0.12), radius: 22, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stylezam camera surrounded by fashion categories")
    }

    private func heroGlyph(_ systemName: String, offset: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 0.75)
            }
            .offset(y: offset)
            .accessibilityHidden(true)
    }
}

private struct LookBreakdownArtwork: View {
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [.white, StylezamDesign.cobalt.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        breakdownTile(index: "01", icon: "tshirt.fill", title: "Clothes")
                        breakdownTile(index: "02", icon: "handbag.fill", title: "Bags")
                    }
                    HStack(spacing: 12) {
                        breakdownTile(index: "03", icon: "shoe.2.fill", title: "Shoes")
                        breakdownTile(index: "04", icon: "watch.analog", title: "Accessories")
                    }
                }
                .padding(22)
            }
            .frame(width: geometry.size.width, height: height)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("One view separated into clothes, bags, shoes, and accessories")
    }

    private func breakdownTile(index: String, icon: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(index)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(StylezamDesign.cobalt)
            }
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(StylezamDesign.cobalt)
            Text(title)
                .font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
    }
}

private struct OnboardingRouteCard: View {
    let number: String
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(StylezamDesign.cobalt)
                .frame(width: 42, height: 42)
                .background(StylezamDesign.cobalt.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(number)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StylezamDesign.secondaryPaper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
    }
}

private struct PrivacyBoundaryArtwork: View {
    var body: some View {
        VStack(spacing: 0) {
            boundarySection(
                kicker: "ON THIS IPHONE",
                title: "Always local",
                icon: "iphone.gen3",
                rows: ["Garment detection and crops", "Your Library and conversations"]
            )

            HStack(spacing: 10) {
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.48))
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
            }
            .padding(.horizontal, 20)

            boundarySection(
                kicker: "ONLY AFTER YOU TAP",
                title: "Connected actions",
                icon: "network",
                rows: ["Product and price searches", "AI questions and virtual try-on"]
            )
        }
        .background(
            LinearGradient(
                colors: [StylezamDesign.cobaltDeep, StylezamDesign.cobalt],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 0.75)
        }
        .shadow(color: StylezamDesign.cobalt.opacity(0.16), radius: 24, y: 14)
        .accessibilityElement(children: .combine)
    }

    private func boundarySection(
        kicker: String,
        title: String,
        icon: String,
        rows: [String]
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(kicker)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.6))
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                ForEach(rows, id: \.self) { row in
                    Label(row, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

private struct OnboardingFact: View {
    let number: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(number)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(StylezamDesign.cobalt)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func onboardingTitle() -> some View {
        font(.system(size: 40, weight: .semibold))
            .tracking(-1.35)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    func onboardingBody() -> some View {
        font(.system(size: 16.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
