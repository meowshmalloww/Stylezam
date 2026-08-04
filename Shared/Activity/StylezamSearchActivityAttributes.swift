import ActivityKit
import Foundation

struct StylezamSearchActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var progress: Double
        var resultCount: Int
        var isComplete: Bool
        var failed: Bool
    }

    var searchID: String
    var query: String?
}

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
