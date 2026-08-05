import AppIntents
import Foundation

struct StartStylezamCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Look"
    static let description = IntentDescription(
        "Open Stylezam to scan clothing from the camera or authorized screen content."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "stylezam://capture-request")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
