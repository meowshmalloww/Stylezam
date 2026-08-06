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
            .widgetURL(URL(string: "stylezam://library"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(for: context.state.visualState))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tint(for: context.state.visualState))
                        .contentTransition(.symbolEffect(.replace))
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
                    Text(context.attributes.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: symbol(for: context.state.visualState))
                    .foregroundStyle(tint(for: context.state.visualState))
                    .contentTransition(.symbolEffect(.replace))
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
            }
            .widgetURL(URL(string: "stylezam://library"))
            .keylineTint(cobalt)
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
}
