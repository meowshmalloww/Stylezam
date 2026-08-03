import SwiftUI

struct LaunchExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var tileOpacity = 0.0
    @State private var tileScale = 0.82
    @State private var topPiece = LogoPieceState.topStart
    @State private var leftPiece = LogoPieceState.leftStart
    @State private var rightPiece = LogoPieceState.rightStart
    @State private var exactMarkOpacity = 0.0
    @State private var constructedMarkOpacity = 1.0
    @State private var revealedCharacterCount = 0
    @State private var taglineOpacity = 0.0
    @State private var exitScale = 1.0
    @State private var exitOpacity = 1.0

    private let nameCharacters = Array("Stylezam")

    var body: some View {
        ZStack {
            StylezamDesign.cobalt
                .ignoresSafeArea()

            VStack(spacing: 24) {
                assembledMark
                    .frame(width: 148, height: 148)
                    .scaleEffect(exitScale)
                    .shadow(color: .black.opacity(0.16), radius: 28, y: 18)

                VStack(spacing: 8) {
                    HStack(spacing: -1.2) {
                        ForEach(Array(nameCharacters.enumerated()), id: \.offset) { index, character in
                            Text(String(character))
                                .font(.system(size: 38, weight: .semibold, design: .default))
                                .foregroundStyle(.white)
                                .opacity(index < revealedCharacterCount ? 1 : 0)
                                .offset(y: index < revealedCharacterCount ? 0 : 12)
                                .blur(radius: index < revealedCharacterCount ? 0 : 5)
                                .animation(
                                    .spring(response: 0.34, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.045),
                                    value: revealedCharacterCount
                                )
                        }
                    }
                    .frame(height: 46)

                    Text("FIND THE LOOK")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.68))
                        .opacity(taglineOpacity)
                }
                .frame(width: 178)
            }
            .scaleEffect(exitScale)
            .opacity(exitOpacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stylezam. Find the look.")
        .task { await play() }
    }

    private var assembledMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(StylezamDesign.cobaltDeep)
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .opacity(tileOpacity)
                .scaleEffect(tileScale)

            ZStack {
                LaunchLogoPiece(kind: .top)
                    .modifier(LogoPieceMotion(state: topPiece))
                LaunchLogoPiece(kind: .left)
                    .modifier(LogoPieceMotion(state: leftPiece))
                LaunchLogoPiece(kind: .right)
                    .modifier(LogoPieceMotion(state: rightPiece))
            }
            .opacity(constructedMarkOpacity)

            BrandMarkView(size: 148, cornerRadius: 32)
                .opacity(exactMarkOpacity)
        }
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            tileOpacity = 1
            tileScale = 1
            constructedMarkOpacity = 0
            withAnimation(.easeOut(duration: 0.22)) {
                exactMarkOpacity = 1
                revealedCharacterCount = nameCharacters.count
                taglineOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            tileOpacity = 1
            tileScale = 1
        }

        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
            topPiece = .settled
        }

        try? await Task.sleep(for: .milliseconds(85))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.7)) {
            leftPiece = .settled
        }

        try? await Task.sleep(for: .milliseconds(85))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.7)) {
            rightPiece = .settled
        }

        try? await Task.sleep(for: .milliseconds(360))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            exactMarkOpacity = 1
            constructedMarkOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        withAnimation {
            revealedCharacterCount = nameCharacters.count
        }

        try? await Task.sleep(for: .milliseconds(470))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            taglineOpacity = 1
        }

        try? await Task.sleep(for: .milliseconds(820))
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.24)) {
            exitScale = 1.035
            exitOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(230))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

private struct LogoPieceState {
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var opacity: Double
    var blur: CGFloat

    static let topStart = LogoPieceState(
        x: 0, y: -74, rotation: -13, scale: 0.82, opacity: 0, blur: 8
    )
    static let leftStart = LogoPieceState(
        x: -68, y: 38, rotation: -16, scale: 0.82, opacity: 0, blur: 8
    )
    static let rightStart = LogoPieceState(
        x: 68, y: 38, rotation: 16, scale: 0.82, opacity: 0, blur: 8
    )
    static let settled = LogoPieceState(
        x: 0, y: 0, rotation: 0, scale: 1, opacity: 1, blur: 0
    )
}

private struct LogoPieceMotion: ViewModifier {
    let state: LogoPieceState

    func body(content: Content) -> some View {
        content
            .scaleEffect(state.scale)
            .rotationEffect(.degrees(state.rotation))
            .offset(x: state.x, y: state.y)
            .blur(radius: state.blur)
            .opacity(state.opacity)
    }
}

private struct LaunchLogoPiece: View {
    let kind: LaunchLogoPieceShape.Kind

    var body: some View {
        LaunchLogoPieceShape(kind: kind)
            .fill(Color(red: 1.0, green: 0.985, blue: 0.94))
            .frame(width: 148, height: 148)
    }
}

private struct LaunchLogoPieceShape: Shape {
    enum Kind {
        case top
        case left
        case right
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .top: topPath(in: rect)
        case .left: leftPath(in: rect)
        case .right: rightPath(in: rect)
        }
    }

    private func topPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.50, 0.11, in: rect))
        path.addCurve(
            to: point(0.36, 0.28, in: rect),
            control1: point(0.45, 0.08, in: rect),
            control2: point(0.41, 0.18, in: rect)
        )
        path.addCurve(
            to: point(0.34, 0.42, in: rect),
            control1: point(0.32, 0.34, in: rect),
            control2: point(0.31, 0.38, in: rect)
        )
        path.addCurve(
            to: point(0.51, 0.56, in: rect),
            control1: point(0.36, 0.49, in: rect),
            control2: point(0.44, 0.53, in: rect)
        )
        path.addCurve(
            to: point(0.66, 0.41, in: rect),
            control1: point(0.55, 0.58, in: rect),
            control2: point(0.61, 0.44, in: rect)
        )
        path.addCurve(
            to: point(0.72, 0.42, in: rect),
            control1: point(0.69, 0.39, in: rect),
            control2: point(0.72, 0.39, in: rect)
        )
        path.addCurve(
            to: point(0.62, 0.52, in: rect),
            control1: point(0.73, 0.46, in: rect),
            control2: point(0.68, 0.50, in: rect)
        )
        path.addCurve(
            to: point(0.70, 0.48, in: rect),
            control1: point(0.65, 0.51, in: rect),
            control2: point(0.68, 0.50, in: rect)
        )
        path.addCurve(
            to: point(0.67, 0.28, in: rect),
            control1: point(0.72, 0.44, in: rect),
            control2: point(0.70, 0.35, in: rect)
        )
        path.addCurve(
            to: point(0.50, 0.11, in: rect),
            control1: point(0.61, 0.18, in: rect),
            control2: point(0.55, 0.10, in: rect)
        )
        path.closeSubpath()
        return path
    }

    private func leftPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.25, 0.48, in: rect))
        path.addCurve(
            to: point(0.10, 0.76, in: rect),
            control1: point(0.18, 0.49, in: rect),
            control2: point(0.12, 0.66, in: rect)
        )
        path.addCurve(
            to: point(0.18, 0.84, in: rect),
            control1: point(0.09, 0.81, in: rect),
            control2: point(0.12, 0.83, in: rect)
        )
        path.addCurve(
            to: point(0.40, 0.83, in: rect),
            control1: point(0.26, 0.86, in: rect),
            control2: point(0.36, 0.86, in: rect)
        )
        path.addCurve(
            to: point(0.47, 0.61, in: rect),
            control1: point(0.46, 0.79, in: rect),
            control2: point(0.47, 0.70, in: rect)
        )
        path.addCurve(
            to: point(0.41, 0.56, in: rect),
            control1: point(0.47, 0.57, in: rect),
            control2: point(0.44, 0.56, in: rect)
        )
        path.addCurve(
            to: point(0.25, 0.48, in: rect),
            control1: point(0.33, 0.55, in: rect),
            control2: point(0.29, 0.48, in: rect)
        )
        path.closeSubpath()
        return path
    }

    private func rightPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.61, 0.55, in: rect))
        path.addCurve(
            to: point(0.52, 0.62, in: rect),
            control1: point(0.57, 0.54, in: rect),
            control2: point(0.53, 0.57, in: rect)
        )
        path.addCurve(
            to: point(0.55, 0.84, in: rect),
            control1: point(0.51, 0.72, in: rect),
            control2: point(0.50, 0.82, in: rect)
        )
        path.addCurve(
            to: point(0.62, 0.82, in: rect),
            control1: point(0.58, 0.86, in: rect),
            control2: point(0.62, 0.85, in: rect)
        )
        path.addCurve(
            to: point(0.58, 0.66, in: rect),
            control1: point(0.65, 0.77, in: rect),
            control2: point(0.60, 0.70, in: rect)
        )
        path.addCurve(
            to: point(0.62, 0.83, in: rect),
            control1: point(0.59, 0.70, in: rect),
            control2: point(0.65, 0.77, in: rect)
        )
        path.addCurve(
            to: point(0.85, 0.82, in: rect),
            control1: point(0.70, 0.85, in: rect),
            control2: point(0.80, 0.85, in: rect)
        )
        path.addCurve(
            to: point(0.86, 0.73, in: rect),
            control1: point(0.90, 0.81, in: rect),
            control2: point(0.90, 0.77, in: rect)
        )
        path.addCurve(
            to: point(0.70, 0.50, in: rect),
            control1: point(0.81, 0.61, in: rect),
            control2: point(0.76, 0.50, in: rect)
        )
        path.addCurve(
            to: point(0.61, 0.55, in: rect),
            control1: point(0.66, 0.49, in: rect),
            control2: point(0.63, 0.51, in: rect)
        )
        path.closeSubpath()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
}
