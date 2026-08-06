import ActivityKit
import Foundation

enum StylezamCaptureActivityVisualState: String, Codable, Hashable {
    case watching
    case detecting
    case recognized
    case cropping
    case saved
    case failed
}

struct StylezamCaptureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var itemCount: Int
        var isComplete: Bool
        var failed: Bool
        var visualState: StylezamCaptureActivityVisualState
        /// Changes on every meaningful pipeline transition so WidgetKit can animate repeated
        /// scanning states instead of treating them as identical content.
        var sequence: Int?
    }

    var captureID: String
    var source: String
}
