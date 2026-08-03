import ActivityKit
import SwiftUI
import WidgetKit

struct StylezamSearchLiveActivity: Widget {
    private let cobalt = Color(red: 0.078, green: 0.361, blue: 1)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StylezamSearchActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "stylezam://search/\(context.attributes.searchID)"))
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
                    if context.state.isComplete {
                        Text("\(context.state.resultCount)")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(cobalt)
                    } else {
                        ProgressView(value: context.state.progress)
                            .progressViewStyle(.circular)
                            .tint(cobalt)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.query ?? "From your capture")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isComplete ? "checkmark" : "viewfinder")
                    .foregroundStyle(context.state.failed ? .red : cobalt)
            } compactTrailing: {
                if context.state.isComplete {
                    Text("\(context.state.resultCount)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(cobalt)
                } else {
                    Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.monospacedDigit())
                }
            } minimal: {
                Image(systemName: context.state.isComplete ? "checkmark" : "viewfinder")
                    .foregroundStyle(context.state.failed ? .red : cobalt)
            }
            .widgetURL(URL(string: "stylezam://search/\(context.attributes.searchID)"))
            .keylineTint(cobalt)
        }
    }

    private func lockScreen(
        _ context: ActivityViewContext<StylezamSearchActivityAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "viewfinder")
                    .foregroundStyle(cobalt)
                Text("STYLEZAM")
                    .font(.headline.weight(.black))
                Spacer()
                if context.state.isComplete {
                    Text(context.state.resultCount == 1 ? "1 match" : "\(context.state.resultCount) matches")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cobalt)
                }
            }
            Text(context.state.phase)
                .font(.title3.weight(.bold))
            if !context.state.isComplete && !context.state.failed {
                ProgressView(value: context.state.progress)
                    .tint(cobalt)
            }
            if let query = context.attributes.query {
                Text(query)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(4)
        .foregroundStyle(.white)
    }
}

