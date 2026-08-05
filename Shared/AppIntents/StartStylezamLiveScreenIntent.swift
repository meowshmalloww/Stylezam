import AppIntents
import Foundation

struct StartStylezamLiveScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Live Screen"
    static let description = IntentDescription(
        "Open Stylezam and show Apple's picker to choose the screen you want to scan."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "stylezam://live-screen")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
