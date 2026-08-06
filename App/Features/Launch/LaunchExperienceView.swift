import SwiftUI

struct LaunchExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var markReveal = 0.0
    @State private var markScale = 0.92
    @State private var markBlur = 10.0
    @State private var wordmarkReveal = 0.0
    @State private var taglineOpacity = 0.0
    @State private var poweredOpacity = 0.0
    @State private var scanPosition = -1.0
    @State private var exitScale = 1.0
    @State private var exitOpacity = 1.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.16, blue: 0.58),
                    StylezamDesign.cobalt,
                    Color(red: 0.13, green: 0.43, blue: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 1)
                    .frame(width: 292, height: 292)
                    .scaleEffect(markScale)
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 380, height: 380)
                    .scaleEffect(markScale)

                VStack(spacing: 24) {
                    BrandMarkView(size: 148, cornerRadius: 32)
                        .mask {
                            IconRevealMask(progress: markReveal)
                        }
                        .overlay {
                            GeometryReader { proxy in
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .white.opacity(0.75), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 42)
                                    .rotationEffect(.degrees(14))
                                    .offset(x: scanPosition * (proxy.size.width + 72))
                                    .blendMode(.plusLighter)
                                    .mask { RoundedRectangle(cornerRadius: 32) }
                            }
                        }
                        .scaleEffect(markScale)
                        .blur(radius: markBlur)
                        .shadow(color: .black.opacity(0.16), radius: 28, y: 18)

                    VStack(spacing: 8) {
                        Text("Stylezam")
                            .font(.system(size: 38, weight: .semibold, design: .default))
                            .tracking(-1.2)
                            .foregroundStyle(.white)
                            .frame(width: 178, height: 46)
                            .mask(alignment: .leading) {
                                GeometryReader { proxy in
                                    Rectangle()
                                        .frame(width: proxy.size.width * wordmarkReveal)
                                        .blur(radius: wordmarkReveal < 1 ? 3 : 0)
                                }
                            }
                            .offset(y: 5 * (1 - wordmarkReveal))

                        Text("FIND THE LOOK")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2.5)
                            .foregroundStyle(.white.opacity(0.68))
                            .opacity(taglineOpacity)
                    }
                    .frame(width: 178)
                }
            }
            .scaleEffect(exitScale)
            .opacity(exitOpacity)

            VStack {
                Spacer()
                Text("Powered by YouCam")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .tracking(0.2)
                    .opacity(poweredOpacity)
                    .padding(.bottom, 28)
            }
            .scaleEffect(exitScale)
            .opacity(exitOpacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stylezam. Find the look.")
        .task { await play() }
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            markScale = 1
            markBlur = 0
            withAnimation(.easeOut(duration: 0.22)) {
                markReveal = 1
                wordmarkReveal = 1
                taglineOpacity = 1
                poweredOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.02)) {
            markReveal = 1
            markScale = 1
            markBlur = 0
        }
        withAnimation(.easeInOut(duration: 0.9)) {
            scanPosition = 1.2
        }

        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.52)) {
            wordmarkReveal = 1
        }

        try? await Task.sleep(for: .milliseconds(360))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            taglineOpacity = 1
            poweredOpacity = 1
        }

        try? await Task.sleep(for: .milliseconds(820))
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.24)) {
            exitScale = 1.025
            exitOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(230))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

private struct IconRevealMask: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                revealCircle(
                    diameter: size * 1.38,
                    phase: phase(from: 0, to: 0.64),
                    x: proxy.size.width * 0.5,
                    y: proxy.size.height * 0.34
                )
                revealCircle(
                    diameter: size * 1.44,
                    phase: phase(from: 0.14, to: 0.82),
                    x: proxy.size.width * 0.30,
                    y: proxy.size.height * 0.70
                )
                revealCircle(
                    diameter: size * 1.44,
                    phase: phase(from: 0.28, to: 0.94),
                    x: proxy.size.width * 0.70,
                    y: proxy.size.height * 0.70
                )

                Rectangle()
                    .fill(.white)
                    .opacity(phase(from: 0.76, to: 1))
            }
            .blur(radius: 5 * (1 - progress))
            .compositingGroup()
        }
    }

    private func revealCircle(
        diameter: CGFloat,
        phase: Double,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        Circle()
            .fill(.white)
            .frame(width: diameter, height: diameter)
            .scaleEffect(max(0.001, phase))
            .position(x: x, y: y)
    }

    private func phase(from start: Double, to end: Double) -> Double {
        let value = min(max((progress - start) / (end - start), 0), 1)
        return value * value * (3 - 2 * value)
    }
}
