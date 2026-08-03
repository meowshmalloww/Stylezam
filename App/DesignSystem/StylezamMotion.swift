import Foundation
import SwiftUI

enum StylezamMotion {
    static let softSpring = Animation.spring(response: 0.62, dampingFraction: 0.86)
    static let quickSpring = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let revealSpring = Animation.spring(response: 0.72, dampingFraction: 0.84)
}

/// A slow, code-native light field used behind important moments. It adds motion
/// without suggesting that a search phase has happened before the backend reports it.
struct LivingCobaltBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.38, blue: 1),
                            StylezamDesign.cobalt,
                            StylezamDesign.cobaltDeep,
                            Color(red: 0.015, green: 0.04, blue: 0.18),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Color.cyan.opacity(0.34 * intensity))
                        .frame(width: width * 0.88, height: width * 0.88)
                        .blur(radius: 60)
                        .offset(
                            x: reduceMotion ? width * 0.25 : sin(time * 0.31) * width * 0.27,
                            y: reduceMotion ? -height * 0.25 : cos(time * 0.27) * height * 0.24 - height * 0.2
                        )

                    Circle()
                        .fill(Color.indigo.opacity(0.5 * intensity))
                        .frame(width: width * 0.96, height: width * 0.96)
                        .blur(radius: 68)
                        .offset(
                            x: reduceMotion ? -width * 0.2 : cos(time * 0.23) * width * 0.31,
                            y: reduceMotion ? height * 0.28 : sin(time * 0.29) * height * 0.24 + height * 0.3
                        )

                    LinearGradient(
                        colors: [.white.opacity(0.13 * intensity), .clear, .black.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .drawingGroup()
            }
        }
        .accessibilityHidden(true)
    }
}

struct OrbitingBrandMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 132
    var markOpacity = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rotation = reduceMotion ? 18.0 : time.truncatingRemainder(dividingBy: 12) * 30
            let breath = reduceMotion ? 1.0 : 1 + sin(time * 1.15) * 0.025

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
                Circle()
                    .trim(from: 0.04, to: 0.42)
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.02),
                                .cyan.opacity(0.82),
                                .white.opacity(0.02),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation))

                BrandMarkView(size: size * 0.72, cornerRadius: size * 0.16)
                    .opacity(markOpacity)
                    .scaleEffect(breath)
                    .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
            }
            .frame(width: size, height: size)
        }
    }
}

struct MotionArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isForward = false

    var color: Color = .primary

    var body: some View {
        Image(systemName: "arrow.right")
            .foregroundStyle(color)
            .offset(x: isForward && !reduceMotion ? 4 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    isForward = true
                }
            }
            .accessibilityHidden(true)
    }
}

private struct MotionRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    let delay: Double
    let distance: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible || reduceMotion ? 0 : 8)
            .offset(y: isVisible || reduceMotion ? 0 : distance)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.985)
            .onAppear {
                guard !isVisible else { return }
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(StylezamMotion.revealSpring.delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

extension View {
    func motionReveal(delay: Double = 0, distance: CGFloat = 18) -> some View {
        modifier(MotionRevealModifier(delay: delay, distance: distance))
    }

    func motionScrollDepth() -> some View {
        scrollTransition(.animated(.spring(response: 0.45, dampingFraction: 0.86))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.7)
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
        }
    }
}

struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.06 : 0.16),
                radius: configuration.isPressed ? 4 : 18,
                y: configuration.isPressed ? 2 : 10
            )
            .animation(StylezamMotion.quickSpring, value: configuration.isPressed)
    }
}

struct EvidenceScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedProgress = 0.0

    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(StylezamDesign.cobalt.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: revealedProgress)
                .stroke(
                    AngularGradient(
                        colors: [StylezamDesign.cobalt, .cyan, StylezamDesign.cobalt],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: StylezamDesign.cobalt.opacity(0.25), radius: 8)
            VStack(spacing: -2) {
                Text(score, format: .number)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(score)))
                Text("score")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .onAppear {
            if reduceMotion {
                revealedProgress = Double(score) / 100
            } else {
                withAnimation(.spring(response: 1.05, dampingFraction: 0.82).delay(0.16)) {
                    revealedProgress = Double(score) / 100
                }
            }
        }
    }
}

struct AnimatedProgressCapsule: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [StylezamDesign.cobalt, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
                    .shadow(color: StylezamDesign.cobalt.opacity(0.28), radius: 7)
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: progress)
        .accessibilityValue(Text(progress, format: .percent))
    }
}
