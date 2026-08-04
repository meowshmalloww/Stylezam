import AppIntents

struct StartStylezamLiveScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Live Screen"
    static let description = IntentDescription(
        "Open Stylezam and show Apple's picker to choose the screen you want to scan."
    )
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @MainActor
    func perform() async throws -> some IntentResult {
        StylezamShared.requestLiveScreen()
        StylezamShared.signalExternalRequest()
        return .result()
    }
}
