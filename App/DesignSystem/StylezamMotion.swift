import SwiftUI

enum StylezamMotion {
    static let softSpring = Animation.spring(response: 0.62, dampingFraction: 0.86)
    static let quickSpring = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let revealSpring = Animation.spring(response: 0.72, dampingFraction: 0.84)
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
