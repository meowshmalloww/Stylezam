import SwiftUI

enum StylezamDesign {
    static let cobalt = Color("BrandCobalt")
    static let cobaltDeep = Color(red: 0.035, green: 0.16, blue: 0.62)
    static let ink = Color.black
    static let paper = Color(uiColor: .systemBackground)
    static let canvas = Color(uiColor: .systemBackground)
    static let secondaryPaper = Color(uiColor: .secondarySystemBackground)
    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 20
    static let compactRadius: CGFloat = 14
    static let hairline = Color.primary.opacity(0.14)
}

enum StylezamRelativeTime {
    static func string(since date: Date, relativeTo now: Date = .now) -> String {
        let elapsedMinutes = max(1, Int(now.timeIntervalSince(date) / 60))
        if elapsedMinutes < 1_440 {
            return "\(elapsedMinutes) min"
        }

        let days = elapsedMinutes / 1_440
        if days < 7 {
            return days == 1 ? "1 day" : "\(days) days"
        }

        let weeks = days / 7
        if weeks < 5 {
            return weeks == 1 ? "1 week" : "\(weeks) weeks"
        }

        let months = max(1, days / 30)
        return months == 1 ? "1 month" : "\(months) months"
    }
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
                .font(.system(.headline, design: .default, weight: .semibold))
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
                .font(.system(size: 42, weight: .semibold, design: .default))
                .tracking(-1.25)
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
            .font(.system(size: size, weight: .semibold, design: .default))
            .tracking(-1.25)
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
