import SwiftUI

struct LaunchExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var markOpacity = 0.0
    @State private var markScale = 0.72
    @State private var markRotation = -7.0
    @State private var markBlur = 12.0
    @State private var nameReveal = 0.0
    @State private var taglineOpacity = 0.0
    @State private var exitScale = 1.0
    @State private var exitOpacity = 1.0

    var body: some View {
        ZStack {
            StylezamDesign.cobalt
                .ignoresSafeArea()

            VStack(spacing: 24) {
                BrandMarkView(size: 142, cornerRadius: 32)
                    .scaleEffect(markScale * exitScale)
                    .rotationEffect(.degrees(markRotation))
                    .blur(radius: markBlur)
                    .opacity(markOpacity)
                    .shadow(color: .black.opacity(0.16), radius: 28, y: 18)

                VStack(spacing: 8) {
                    Text("Stylezam")
                        .font(.system(size: 38, weight: .semibold, design: .default))
                        .tracking(-1.2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mask(alignment: .leading) {
                            GeometryReader { proxy in
                                Rectangle()
                                    .frame(width: proxy.size.width * nameReveal)
                            }
                        }

                    Text("FIND THE LOOK")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.68))
                        .opacity(taglineOpacity)
                }
                .frame(width: 166, alignment: .leading)
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
            withAnimation(.easeOut(duration: 0.22)) {
                markOpacity = 1
                markScale = 1
                markRotation = 0
                markBlur = 0
                nameReveal = 1
                taglineOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        withAnimation(.spring(response: 0.72, dampingFraction: 0.72)) {
            markOpacity = 1
            markScale = 1
            markRotation = 0
            markBlur = 0
        }

        try? await Task.sleep(for: .milliseconds(470))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.58)) {
            nameReveal = 1
        }
        withAnimation(.easeOut(duration: 0.38).delay(0.18)) {
            taglineOpacity = 1
        }

        try? await Task.sleep(for: .milliseconds(1_240))
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
