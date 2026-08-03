import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    private var latestCapture: SavedCapture? {
        model.library.captures.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                    .motionReveal()
                hero
                    .motionReveal(delay: 0.06, distance: 24)
                recentCaptures
                    .motionReveal(delay: 0.13)
                accessSection
                    .motionReveal(delay: 0.18)
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.bottom, 110)
        }
        .background(StylezamDesign.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandMarkView(size: 42)
            StylezamWordmark()
            Spacer()
            ServiceBadge(
                connected: model.capabilities != nil,
                connectedText: "Online",
                disconnectedText: "Offline"
            )
            GlassIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {
                model.selectedTab = .you
            }
        }
        .padding(.top, 8)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            heroArtwork

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.02), location: 0),
                    .init(color: StylezamDesign.cobaltDeep.opacity(0.38), location: 0.34),
                    .init(color: .black.opacity(0.9), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 18) {
                if latestCapture != nil {
                    StatusPill(text: "Continue your latest search", tint: .white)
                }

                PageTitle(
                    title: "Find what they’re wearing.",
                    subtitle: "Start with a photo or a few words. Stylezam checks real product sources and shows how strong each match is.",
                    color: .white
                )

                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        Button {
                            model.isCapturePresented = true
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "photo.badge.plus")
                                Text("Search a photo")
                                    .fontWeight(.semibold)
                                Spacer()
                                MotionArrow()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .padding(.horizontal, 17)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.white)
                        .foregroundStyle(.black)

                        Button {
                            model.selectedTab = .search
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "text.magnifyingglass")
                                Text("Search with words")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .padding(.horizontal, 17)
                        }
                        .buttonStyle(.glass)
                        .foregroundStyle(.white)
                    }
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: StylezamDesign.cobalt.opacity(0.2), radius: 30, y: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var heroArtwork: some View {
        if let latestCapture,
           let imageURL = model.library.imageURL(for: latestCapture)
        {
            LocalFileImage(url: imageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                LivingCobaltBackdrop()
                OrbitingBrandMark(size: 210, markOpacity: 0.84)
                    .offset(x: 96, y: -132)
            }
        }
    }

    private var recentCaptures: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent searches")
                    .font(.title2.weight(.semibold))
                    .fontDesign(.serif)
                Spacer()
                if !model.library.captures.isEmpty {
                    Button("See all") { model.selectedTab = .looks }
                        .font(.subheadline.weight(.semibold))
                }
            }

            if model.library.captures.isEmpty {
                SurfaceCard {
                    HStack(spacing: 15) {
                        BrandMarkView(size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your first find starts here")
                                .font(.headline)
                            Text("Photos and descriptions you search will appear here—never invented examples.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 13) {
                        ForEach(model.library.captures.prefix(8)) { capture in
                            Button {
                                model.resumeSearch(
                                    id: capture.searchID,
                                    imageData: model.library.imageURL(for: capture).flatMap {
                                        try? Data(contentsOf: $0)
                                    }
                                )
                            } label: {
                                captureTile(capture)
                            }
                            .buttonStyle(.plain)
                            .motionScrollDepth()
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func captureTile(_ capture: SavedCapture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = model.library.imageURL(for: capture) {
                    LocalFileImage(url: url)
                } else {
                    LinearGradient(
                        colors: [StylezamDesign.cobalt, StylezamDesign.cobaltDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "text.magnifyingglass")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 150, height: 184)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(capture.query ?? capture.origin.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(capture.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accessSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Find it from anywhere")
                .font(.title2.weight(.semibold))
                .fontDesign(.serif)

            SurfaceCard {
                VStack(spacing: 0) {
                    accessRow(
                        icon: "square.and.arrow.up",
                        title: "Share to Stylezam",
                        detail: "Send an image or description from another app."
                    )
                    EditorialRule()
                    accessRow(
                        icon: "switch.2",
                        title: "Control Center",
                        detail: "Open capture from a control or the Action Button."
                    )
                    EditorialRule()
                    accessRow(
                        icon: "lock.shield",
                        title: "Private by default",
                        detail: "Nothing is uploaded until you start a search."
                    )
                }
            }
            .motionScrollDepth()
        }
    }

    private func accessRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(StylezamDesign.cobalt)
                .frame(width: 38, height: 38)
                .background(StylezamDesign.cobalt.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }
}

private extension CaptureOrigin {
    var displayName: String {
        switch self {
        case .camera: "Camera capture"
        case .photoLibrary: "Photo"
        case .text: "Text search"
        case .clipboard: "Clipboard"
        case .shareExtension: "Shared look"
        case .screenCapture: "Screen capture"
        }
    }
}
