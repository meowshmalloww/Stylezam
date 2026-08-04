import AppIntents

struct StartStylezamCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Look"
    static let description = IntentDescription(
        "Open Stylezam to scan clothing from the camera or authorized screen content."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        StylezamShared.requestCapture()
        return .result()
    }
}
