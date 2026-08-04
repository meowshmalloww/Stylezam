import ActivityKit
import Foundation

struct StylezamCaptureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var itemCount: Int
        var isComplete: Bool
        var failed: Bool
    }

    var captureID: String
    var source: String
}
