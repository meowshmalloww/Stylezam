import AppIntents

struct StartStylezamCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Look"
    static let description = IntentDescription(
        "Open Stylezam to scan clothing from the camera or authorized screen content."
    )
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @MainActor
    func perform() async throws -> some IntentResult {
        StylezamShared.requestCapture()
        StylezamShared.signalExternalRequest()
        return .result()
    }
}
