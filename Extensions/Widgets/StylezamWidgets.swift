import SwiftUI
import WidgetKit

@main
struct StylezamWidgets: WidgetBundle {
    var body: some Widget {
        StylezamCaptureLiveActivity()
        if #available(iOS 26.0, *) {
            StylezamCaptureControl()
            StylezamLiveScreenControl()
        }
    }
}
