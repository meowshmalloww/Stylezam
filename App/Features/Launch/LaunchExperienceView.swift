import SwiftUI

struct LaunchExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var backgroundBloom = 0.0
    @State private var topEntry = 0.0
    @State private var leftEntry = 0.0
    @State private var rightEntry = 0.0
    @State private var flashEntry = 0.0
    @State private var apertureClosure = 0.0
    @State private var captureImpulse = 0.0
    @State private var resolvedOpacity = 0.0
    @State private var wordmarkReveal = 0.0
    @State private var taglineOpacity = 0.0
    @State private var poweredOpacity = 0.0
    @State private var exposureOpacity = 0.0
    @State private var exitScale = 1.0
    @State private var exitOpacity = 1.0

    var body: some View {
        ZStack {
            launchBackground

            VStack(spacing: 22) {
                ShutterAssemblyMark(
                    topEntry: topEntry,
                    leftEntry: leftEntry,
                    rightEntry: rightEntry,
                    flashEntry: flashEntry,
                    apertureClosure: apertureClosure,
                    captureImpulse: captureImpulse,
                    resolvedOpacity: resolvedOpacity
                )
                .frame(width: 188, height: 188)
                .frame(width: 232, height: 232)

                VStack(spacing: 8) {
                    CascadingWordmark(reveal: wordmarkReveal)
                        .frame(width: 182, height: 47)

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
                    .offset(y: 8 * (1 - poweredOpacity))
                    .padding(.bottom, 28)
            }
            .scaleEffect(exitScale)
            .opacity(exitOpacity)

            Color.white
                .ignoresSafeArea()
                .opacity(exposureOpacity)
                .blendMode(.screen)
                .allowsHitTesting(false)
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
            .scaleEffect(0.68 + (0.48 * backgroundBloom))
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
            topEntry = 1
            leftEntry = 1
            rightEntry = 1
            flashEntry = 1
            resolvedOpacity = 1
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
        }
        withAnimation(.spring(response: 0.68, dampingFraction: 0.70)) {
            topEntry = 1
        }

        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.72, dampingFraction: 0.68)) {
            leftEntry = 1
        }

        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.74, dampingFraction: 0.70)) {
            rightEntry = 1
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.58)) {
            flashEntry = 1
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.65, 0, 0.8, 0.2, duration: 0.26)) {
            apertureClosure = 1
        }

        try? await Task.sleep(for: .milliseconds(275))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.62)) {
            apertureClosure = 0
            captureImpulse = 1
        }
        withAnimation(.easeIn(duration: 0.055)) {
            exposureOpacity = 0.78
        }

        try? await Task.sleep(for: .milliseconds(70))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.32)) {
            exposureOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            resolvedOpacity = 1
            captureImpulse = 0
        }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.48)) {
            wordmarkReveal = 1
        }

        try? await Task.sleep(for: .milliseconds(310))
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

private struct CascadingWordmark: View {
    let reveal: Double

    private let letters = Array("Stylezam")

    var body: some View {
        HStack(spacing: -1.4) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                let progress = letterProgress(index)
                Text(String(letter))
                    .font(.system(size: 39, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .opacity(progress)
                    .blur(radius: 4 * (1 - progress))
                    .offset(y: 9 * (1 - progress))
                    .rotation3DEffect(
                        .degrees(-28 * (1 - progress)),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.7
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityHidden(true)
    }

    private func letterProgress(_ index: Int) -> Double {
        let start = Double(index) * 0.065
        return min(1, max(0, (reveal - start) / 0.55))
    }
}

private struct ShutterAssemblyMark: View {
    let topEntry: Double
    let leftEntry: Double
    let rightEntry: Double
    let flashEntry: Double
    let apertureClosure: Double
    let captureImpulse: Double
    let resolvedOpacity: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                shutterPiece(.top, progress: topEntry, size: size)
                shutterPiece(.left, progress: leftEntry, size: size)
                shutterPiece(.right, progress: rightEntry, size: size)
                flashPiece(progress: flashEntry, size: size)

                LaunchLogoGlyph()
                    .opacity(resolvedOpacity)
                    .scaleEffect(0.992 + (0.008 * resolvedOpacity))
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .scaleEffect(1 + (0.018 * captureImpulse))
            .shadow(
                color: .white.opacity(0.5 * captureImpulse),
                radius: 30 * captureImpulse
            )
            .shadow(color: .black.opacity(0.13), radius: 26, y: 16)
        }
    }

    @ViewBuilder
    private func shutterPiece(
        _ piece: ShutterPiece,
        progress: Double,
        size: CGFloat
    ) -> some View {
        let remaining = CGFloat(1 - progress)
        let closure = CGFloat(apertureClosure)
        let entryMovement = CGSize(
            width: piece.entryMovement.width * remaining,
            height: piece.entryMovement.height * remaining
        )
        let closureMovement = CGSize(
            width: piece.closureMovement.width * closure,
            height: piece.closureMovement.height * closure
        )

        LaunchLogoGlyph()
            .mask { ShutterPieceMask(piece: piece) }
            .scaleEffect(
                (0.58 + (0.42 * CGFloat(progress))) * (1 - (0.045 * closure))
            )
            .rotationEffect(
                .degrees(
                    (piece.entryRotation * Double(remaining))
                        + (piece.closureRotation * apertureClosure)
                )
            )
            .rotation3DEffect(
                .degrees(piece.entryTilt * Double(remaining)),
                axis: piece.entryAxis,
                perspective: 0.68
            )
            .offset(
                x: (entryMovement.width + closureMovement.width) * size,
                y: (entryMovement.height + closureMovement.height) * size
            )
            .blur(radius: 5 * remaining)
            .opacity(progress * (1 - resolvedOpacity))
    }

    @ViewBuilder
    private func flashPiece(progress: Double, size: CGFloat) -> some View {
        let remaining = CGFloat(1 - progress)

        LaunchLogoGlyph()
            .mask { ShutterPieceMask(piece: .flash) }
            .scaleEffect(
                0.2 + (0.8 * CGFloat(progress)) + (0.16 * CGFloat(captureImpulse)),
                anchor: UnitPoint(x: 0.79, y: 0.25)
            )
            .rotation3DEffect(
                .degrees(75 * Double(remaining)),
                axis: (x: 1, y: 0.25, z: 0),
                perspective: 0.72
            )
            .offset(y: size * 0.06 * remaining)
            .blur(radius: 3 * remaining)
            .opacity(progress * (1 - resolvedOpacity))
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
    case flash

    var entryMovement: CGSize {
        switch self {
        case .top: CGSize(width: -0.20, height: -0.28)
        case .left: CGSize(width: -0.30, height: 0.22)
        case .right: CGSize(width: 0.31, height: 0.20)
        case .flash: .zero
        }
    }

    var closureMovement: CGSize {
        switch self {
        case .top: CGSize(width: 0, height: 0.065)
        case .left: CGSize(width: 0.057, height: -0.034)
        case .right: CGSize(width: -0.057, height: -0.034)
        case .flash: .zero
        }
    }

    var entryRotation: Double {
        switch self {
        case .top: -28
        case .left: -24
        case .right: 27
        case .flash: 0
        }
    }

    var closureRotation: Double {
        switch self {
        case .top, .left, .right: 11
        case .flash: 0
        }
    }

    var entryTilt: Double {
        switch self {
        case .top: 68
        case .left: -62
        case .right: 64
        case .flash: 0
        }
    }

    var entryAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        switch self {
        case .top: (x: 1, y: 0.2, z: 0)
        case .left: (x: 0.15, y: 1, z: 0)
        case .right: (x: -0.15, y: 1, z: 0)
        case .flash: (x: 1, y: 0, z: 0)
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
            path.move(to: point(0.48, 0.31, in: rect))
            path.addLine(to: point(1, 0.29, in: rect))
            path.addLine(to: point(1, 1, in: rect))
            path.addLine(to: point(0.40, 1, in: rect))
            path.addLine(to: point(0.52, 0.65, in: rect))
            path.closeSubpath()
        case .flash:
            path.addRoundedRect(
                in: CGRect(
                    x: rect.minX + (rect.width * 0.70),
                    y: rect.minY + (rect.height * 0.17),
                    width: rect.width * 0.18,
                    height: rect.height * 0.16
                ),
                cornerSize: CGSize(width: rect.width * 0.05, height: rect.height * 0.05)
            )
        }

        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + (rect.width * x), y: rect.minY + (rect.height * y))
    }
}
