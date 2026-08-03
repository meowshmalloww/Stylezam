import SwiftUI
import WidgetKit

struct StylezamCaptureControl: ControlWidget {
    static let kind = "com.stylezam.app.capture-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartStylezamCaptureIntent()) {
                Label("Capture a Look", systemImage: "viewfinder")
            }
        }
        .displayName("Capture a Look")
        .description("Open Stylezam from Control Center, the Lock Screen, or the Action Button.")
    }
}

