import SwiftUI

enum StylezamDesign {
    static let cobalt = Color("BrandCobalt")
    static let cobaltDeep = Color(red: 0.035, green: 0.16, blue: 0.62)
    static let ink = Color.black
    static let paper = Color(uiColor: .systemBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let secondaryPaper = Color(uiColor: .secondarySystemBackground)
    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 28
    static let compactRadius: CGFloat = 20
    static let hairline = Color.primary.opacity(0.12)
}

struct BrandMarkView: View {
    var size: CGFloat = 46
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius ?? size * 0.225,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }
}

struct StylezamWordmark: View {
    var light = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Stylezam")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text("FIND THE LOOK")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.25)
                .opacity(0.62)
        }
        .foregroundStyle(light ? Color.white : Color.primary)
    }
}

struct PageTitle: View {
    let title: String
    var subtitle: String? = nil
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 43, weight: .semibold, design: .serif))
                .tracking(-1.1)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(color.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct EditorialTitle: View {
    let text: String
    var size: CGFloat = 46
    var color: Color = .primary

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .serif))
            .tracking(-1.1)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct EditorialKicker: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.25)
            .foregroundStyle(color)
    }
}

struct EditorialSectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.semibold))
                .fontDesign(.serif)
            Spacer()
            if let detail {
                Text(detail.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EditorialRule: View {
    var body: some View {
        Rectangle()
            .fill(StylezamDesign.hairline)
            .frame(height: 1)
    }
}

struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct CobaltActionButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
        }
        .buttonStyle(.glassProminent)
        .tint(StylezamDesign.cobalt)
        .disabled(!isEnabled)
    }
}

struct StatusPill: View {
    let text: String
    var tint: Color = StylezamDesign.cobalt

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .textCase(.uppercase)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(tint)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: StylezamDesign.cardRadius))
    }
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                StylezamDesign.paper,
                in: RoundedRectangle(cornerRadius: StylezamDesign.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StylezamDesign.cardRadius, style: .continuous)
                    .stroke(StylezamDesign.hairline, lineWidth: 0.5)
            }
    }
}

struct ServiceBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    let connected: Bool
    var connectedText = "Connected"
    var disconnectedText = "Setup needed"

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(connected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .overlay {
                    if connected {
                        Circle()
                            .stroke(Color.green.opacity(0.45), lineWidth: 1)
                            .scaleEffect(isPulsing && !reduceMotion ? 2.1 : 1)
                            .opacity(isPulsing && !reduceMotion ? 0 : 0.7)
                    }
                }
            Text(connected ? connectedText : disconnectedText)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .glassEffect(.regular, in: Capsule())
        .onAppear {
            guard connected, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.35).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .onChange(of: connected) { _, value in
            guard value, !reduceMotion else {
                isPulsing = false
                return
            }
            withAnimation(.easeOut(duration: 1.35).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

struct InlineErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Something needs attention", systemImage: "exclamationmark.circle.fill")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let retry {
                Button("Try again", action: retry)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
}
