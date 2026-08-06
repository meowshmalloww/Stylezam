import ActivityKit
import SwiftUI
import WidgetKit

struct StylezamCaptureLiveActivity: Widget {
    private let cobalt = Color(red: 0.078, green: 0.361, blue: 1)
    private let savedGreen = Color(red: 0.16, green: 0.76, blue: 0.38)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StylezamCaptureActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: symbol(for: context.state.visualState))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint(for: context.state.visualState))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: context.state.sequence ?? 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.phase)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.attributes.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if context.state.itemCount > 0 {
                    Text(context.state.itemCount, format: .number)
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(cobalt)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
            .animation(.snappy(duration: 0.42), value: context.state.sequence ?? 0)
            .widgetURL(URL(string: "stylezam://library"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(for: context.state.visualState))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tint(for: context.state.visualState))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: context.state.sequence ?? 0)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.phase)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.itemCount > 0 {
                        Text(context.state.itemCount, format: .number)
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(cobalt)
                            .contentTransition(.numericText())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 9) {
                        ScanStageRail(
                            state: context.state.visualState,
                            sequence: context.state.sequence ?? 0,
                            cobalt: cobalt,
                            savedGreen: savedGreen
                        )
                        HStack {
                            Text(context.attributes.source)
                            Spacer()
                            Text(stageCaption(for: context.state.visualState))
                                .contentTransition(.interpolate)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(for: context.state.visualState))
                    .foregroundStyle(tint(for: context.state.visualState))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: context.state.sequence ?? 0)
            } compactTrailing: {
                if context.state.itemCount > 0 {
                    Text(context.state.itemCount, format: .number)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(cobalt)
                }
            } minimal: {
                Image(systemName: symbol(for: context.state.visualState))
                    .foregroundStyle(tint(for: context.state.visualState))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: context.state.sequence ?? 0)
            }
            .widgetURL(URL(string: "stylezam://library"))
            .keylineTint(cobalt)
            .contentMargins(.horizontal, 12, for: .expanded)
        }
    }

    private func symbol(for state: StylezamCaptureActivityVisualState) -> String {
        switch state {
        case .watching: "viewfinder"
        case .detecting: "viewfinder.circle"
        case .recognized: "viewfinder.circle.fill"
        case .cropping: "crop"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func tint(for state: StylezamCaptureActivityVisualState) -> Color {
        switch state {
        case .saved: savedGreen
        case .failed: .red
        default: cobalt
        }
    }

    private func stageCaption(for state: StylezamCaptureActivityVisualState) -> String {
        switch state {
        case .watching: "Watching"
        case .detecting: "Scanning"
        case .recognized: "Recognized"
        case .cropping: "Making crop"
        case .saved: "In Library"
        case .failed: "Needs attention"
        }
    }
}

private struct ScanStageRail: View {
    let state: StylezamCaptureActivityVisualState
    let sequence: Int
    let cobalt: Color
    let savedGreen: Color

    private let stages: [StylezamCaptureActivityVisualState] = [
        .watching, .detecting, .recognized, .cropping, .saved,
    ]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                Circle()
                    .fill(color(for: stage))
                    .frame(width: stage == state ? 9 : 6, height: stage == state ? 9 : 6)
                    .shadow(
                        color: stage == state ? color(for: stage).opacity(0.65) : .clear,
                        radius: 5
                    )
                    .accessibilityHidden(true)
                if index < stages.count - 1 {
                    Capsule()
                        .fill(index < currentIndex ? cobalt : Color.secondary.opacity(0.22))
                        .frame(height: 2)
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: sequence)
        .accessibilityLabel("Capture progress: \(state.rawValue)")
    }

    private var currentIndex: Int {
        stages.firstIndex(of: state) ?? 0
    }

    private func color(for stage: StylezamCaptureActivityVisualState) -> Color {
        if state == .failed { return .red }
        if stage == .saved, currentIndex >= stages.count - 1 { return savedGreen }
        let index = stages.firstIndex(of: stage) ?? 0
        return index <= currentIndex ? cobalt : Color.secondary.opacity(0.24)
    }
}
