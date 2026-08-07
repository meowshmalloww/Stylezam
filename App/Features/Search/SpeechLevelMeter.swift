import SwiftUI

struct SpeechLevelMeter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(StylezamDesign.cobalt)
                    .frame(width: 3, height: barHeight(index))
                    .animation(.spring(response: 0.16, dampingFraction: 0.72), value: level)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let shape: [Float] = [0.46, 0.78, 1, 0.72, 0.42]
        return 5 + CGFloat(max(0.08, level) * shape[index]) * 20
    }
}
