import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
struct StylezamLiveScreenControl: ControlWidget {
    static let kind = "com.stylezam.app.live-screen-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenStylezamIntent(target: .liveScreen)) {
                Label("Live Screen", systemImage: "rectangle.dashed.badge.record")
            }
        }
        .displayName("Live Screen")
        .description("Open Stylezam and immediately choose a screen using Apple's system picker.")
    }
}
