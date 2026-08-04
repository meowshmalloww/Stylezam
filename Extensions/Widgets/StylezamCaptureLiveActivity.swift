import ActivityKit
import SwiftUI
import WidgetKit

struct StylezamCaptureLiveActivity: Widget {
    private let cobalt = Color(red: 0.078, green: 0.361, blue: 1)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StylezamCaptureActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.failed ? "exclamationmark" : "viewfinder")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(context.state.failed ? .red : cobalt)
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
                    Image(systemName: context.state.failed ? "exclamationmark" : "viewfinder")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(context.state.failed ? .red : cobalt)
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
                Image(systemName: context.state.isComplete ? "checkmark" : "viewfinder")
                    .foregroundStyle(context.state.failed ? .red : cobalt)
            } compactTrailing: {
                if context.state.itemCount > 0 {
                    Text(context.state.itemCount, format: .number)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(cobalt)
                }
            } minimal: {
                Image(systemName: context.state.isComplete ? "checkmark" : "viewfinder")
                    .foregroundStyle(context.state.failed ? .red : cobalt)
            }
            .widgetURL(URL(string: "stylezam://library"))
            .keylineTint(cobalt)
        }
    }
}
