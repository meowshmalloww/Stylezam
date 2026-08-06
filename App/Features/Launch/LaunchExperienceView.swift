import SwiftUI

struct LaunchExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var backgroundBloom = 0.0
    @State private var assemblyProgress = 0.0
    @State private var resolvedOpacity = 0.0
    @State private var orbitRotation = -80.0
    @State private var focusProgress = 0.0
    @State private var flashProgress = 0.0
    @State private var glintPosition = -1.0
    @State private var wordmarkReveal = 0.0
    @State private var taglineOpacity = 0.0
    @State private var poweredOpacity = 0.0
    @State private var exitScale = 1.0
    @State private var exitOpacity = 1.0

    var body: some View {
        ZStack {
            launchBackground

            VStack(spacing: 25) {
                ZStack {
                    LaunchOrbitView(
                        rotation: orbitRotation,
                        opacity: 1 - resolvedOpacity
                    )
                    .frame(width: 214, height: 214)

                    ShutterAssemblyMark(
                        progress: assemblyProgress,
                        resolvedOpacity: resolvedOpacity,
                        focusProgress: focusProgress,
                        flashProgress: flashProgress,
                        glintPosition: glintPosition
                    )
                    .frame(width: 168, height: 168)
                }
                .frame(width: 226, height: 226)

                VStack(spacing: 8) {
                    Text("Stylezam")
                        .font(.system(size: 39, weight: .semibold, design: .default))
                        .tracking(-1.35)
                        .foregroundStyle(.white)
                        .frame(width: 182, height: 47)
                        .mask(alignment: .leading) {
                            GeometryReader { proxy in
                                Rectangle()
                                    .frame(width: proxy.size.width * wordmarkReveal)
                                    .blur(radius: wordmarkReveal < 1 ? 2.5 : 0)
                            }
                        }
                        .offset(y: 5 * (1 - wordmarkReveal))

                    Text("FIND THE LOOK")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.7)
                        .foregroundStyle(.white.opacity(0.7))
                        .opacity(taglineOpacity)
                }
                .frame(width: 182)
            }
            .offset(y: -12)
            .scaleEffect(exitScale)
            .opacity(exitOpacity)

            VStack {
                Spacer()
                Text("Powered by YouCam")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .tracking(0.2)
                    .opacity(poweredOpacity)
                    .padding(.bottom, 28)
            }
            .scaleEffect(exitScale)
            .opacity(exitOpacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stylezam. Find the look. Powered by YouCam.")
        .task { await play() }
    }

    private var launchBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.12, blue: 0.48),
                    Color(red: 0.03, green: 0.25, blue: 0.82),
                    StylezamDesign.cobalt,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.17, green: 0.48, blue: 1).opacity(0.72),
                    .clear,
                ],
                center: .center,
                startRadius: 12,
                endRadius: 360
            )
            .scaleEffect(0.65 + (0.5 * backgroundBloom))
            .opacity(backgroundBloom)

            LinearGradient(
                colors: [.white.opacity(0.08), .clear, .black.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            backgroundBloom = 1
            assemblyProgress = 1
            resolvedOpacity = 1
            focusProgress = 1
            withAnimation(.easeOut(duration: 0.22)) {
                wordmarkReveal = 1
                taglineOpacity = 1
                poweredOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        try? await Task.sleep(for: .milliseconds(70))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.9)) {
            backgroundBloom = 1
            orbitRotation = 310
        }
        withAnimation(.spring(response: 0.82, dampingFraction: 0.72)) {
            assemblyProgress = 1
            focusProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(610))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            resolvedOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.62)) {
            flashProgress = 1
            glintPosition = 1.25
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)) {
            wordmarkReveal = 1
        }

        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            taglineOpacity = 1
            poweredOpacity = 1
        }

        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.55, 0, 1, 0.45, duration: 0.25)) {
            exitScale = 1.035
            exitOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(240))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

private struct ShutterAssemblyMark: View {
    let progress: Double
    let resolvedOpacity: Double
    let focusProgress: Double
    let flashProgress: Double
    let glintPosition: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                shutterPiece(.top, size: size)
                shutterPiece(.left, size: size)
                shutterPiece(.right, size: size)

                LaunchLogoGlyph()
                    .opacity(resolvedOpacity)
                    .scaleEffect(0.985 + (0.015 * resolvedOpacity))

                Circle()
                    .stroke(.white.opacity(0.84 * (1 - resolvedOpacity)), lineWidth: 1.5)
                    .frame(width: size * 0.29, height: size * 0.29)
                    .scaleEffect(1.85 - (0.85 * focusProgress))
                    .blur(radius: 2.5 * (1 - focusProgress))

                LaunchFlashBurst(progress: flashProgress)
                    .frame(width: size * 0.43, height: size * 0.43)
                    .position(x: size * 0.79, y: size * 0.24)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.9), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size * 0.18, height: size * 1.25)
                    .rotationEffect(.degrees(16))
                    .offset(x: glintPosition * size * 1.3)
                    .blendMode(.plusLighter)
                    .mask { LaunchLogoGlyph() }
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .shadow(color: .black.opacity(0.13), radius: 26, y: 16)
        }
    }

    @ViewBuilder
    private func shutterPiece(_ piece: ShutterPiece, size: CGFloat) -> some View {
        let remaining = 1 - progress
        let movement = CGSize(
            width: piece.movement.width * remaining,
            height: piece.movement.height * remaining
        )

        LaunchLogoGlyph()
            .mask { ShutterPieceMask(piece: piece) }
            .scaleEffect(0.82 + (0.18 * progress))
            .rotationEffect(.degrees(piece.rotation * remaining))
            .offset(x: movement.width * size, y: movement.height * size)
            .blur(radius: 5 * remaining)
            .opacity(1 - resolvedOpacity)
    }
}

private struct LaunchLogoGlyph: View {
    var body: some View {
        Color.white
            .mask {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(1.28)
                    .grayscale(1)
                    .contrast(10)
                    .luminanceToAlpha()
            }
            .accessibilityHidden(true)
    }
}

private enum ShutterPiece {
    case top
    case left
    case right

    var movement: CGSize {
        switch self {
        case .top: CGSize(width: -0.08, height: -0.31)
        case .left: CGSize(width: -0.30, height: 0.19)
        case .right: CGSize(width: 0.31, height: 0.18)
        }
    }

    var rotation: Double {
        switch self {
        case .top: -17
        case .left: -14
        case .right: 18
        }
    }
}

private struct ShutterPieceMask: Shape {
    let piece: ShutterPiece

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch piece {
        case .top:
            path.move(to: point(0, 0, in: rect))
            path.addLine(to: point(1, 0, in: rect))
            path.addLine(to: point(1, 0.40, in: rect))
            path.addLine(to: point(0.50, 0.56, in: rect))
            path.addLine(to: point(0.32, 0.62, in: rect))
            path.addLine(to: point(0, 0.46, in: rect))
            path.closeSubpath()
        case .left:
            path.move(to: point(0, 0.30, in: rect))
            path.addLine(to: point(0.34, 0.38, in: rect))
            path.addLine(to: point(0.55, 0.70, in: rect))
            path.addLine(to: point(0.44, 1, in: rect))
            path.addLine(to: point(0, 1, in: rect))
            path.closeSubpath()
        case .right:
            path.move(to: point(0.48, 0.33, in: rect))
            path.addLine(to: point(1, 0.24, in: rect))
            path.addLine(to: point(1, 1, in: rect))
            path.addLine(to: point(0.40, 1, in: rect))
            path.addLine(to: point(0.52, 0.65, in: rect))
            path.closeSubpath()
        }

        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + (rect.width * x), y: rect.minY + (rect.height * y))
    }
}

private struct LaunchOrbitView: View {
    let rotation: Double
    let opacity: Double

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.05, to: 0.30)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .white.opacity(0.58)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )

            Circle()
                .trim(from: 0.53, to: 0.80)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.52), .white.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )

            Circle()
                .fill(.white.opacity(0.7))
                .frame(width: 4, height: 4)
                .offset(y: -107)
        }
        .rotationEffect(.degrees(rotation))
        .opacity(opacity)
    }
}

private struct LaunchFlashBurst: View {
    let progress: Double

    private var visibility: Double {
        guard progress > 0 else { return 0 }
        return max(0, 1 - progress)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.75), lineWidth: 1.5)
                .scaleEffect(0.3 + (0.8 * progress))

            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: 2, height: 12)
                    .offset(y: -30 - (8 * progress))
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
        .opacity(visibility)
        .blur(radius: progress * 0.8)
    }
}
