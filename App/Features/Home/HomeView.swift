import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var feedbackEvent = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                    .padding(.bottom, 32)

                Text("Find the piece.")
                    .font(.system(size: 44, weight: .semibold))
                    .tracking(-1.65)
                    .accessibilityAddTraits(.isHeader)

                Text("Start with what you see. Stylezam identifies the clothing and searches real product sources.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)
                    .padding(.bottom, 28)

                capturePortal

                Button {
                    model.presentCapture(.photos)
                } label: {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.glass)
                .padding(.top, 12)

                latestSearch
                    .padding(.top, 32)
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 86)
        }
        .background(StylezamDesign.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.impact(weight: .medium), trigger: feedbackEvent)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            BrandMarkView(size: 36)
            StylezamWordmark()
            Spacer()
        }
    }

    private var capturePortal: some View {
        Button {
            feedbackEvent += 1
            model.presentCapture(.camera)
        } label: {
            ZStack {
                Color(uiColor: .secondarySystemBackground)

                ViewfinderCorners()
                    .stroke(.primary.opacity(0.72), style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                    .padding(20)

                VStack(spacing: 13) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 39, weight: .regular))
                    Text("Open camera")
                        .font(.title3.weight(.semibold))
                    Text("Photo search")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("VISUAL SEARCH")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.25)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .padding(20)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .aspectRatio(1.32, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(StylezamDesign.hairline, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(QuietPressButtonStyle())
        .accessibilityLabel("Open camera to find clothing")
    }

    @ViewBuilder
    private var latestSearch: some View {
        if let latest = model.library.captures.first {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                EditorialRule()
                Button {
                    model.resumeSearch(
                        id: latest.searchID,
                        imageData: model.library.imageURL(for: latest).flatMap {
                            try? Data(contentsOf: $0, options: .mappedIfSafe)
                        }
                    )
                } label: {
                    HStack(spacing: 13) {
                        Group {
                            if let imageURL = model.library.imageURL(for: latest) {
                                LocalFileImage(url: imageURL)
                            } else {
                                Color(uiColor: .secondarySystemBackground)
                                    .overlay {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .frame(width: 52, height: 62)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(latest.query ?? "Photo search")
                                .font(.headline)
                                .lineLimit(1)
                            Text(latest.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                EditorialRule()
                Text("Searches, saved products, and try-ons appear in Library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.12
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

private struct QuietPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
