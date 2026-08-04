import AppIntents
import UniformTypeIdentifiers

struct SearchStylezamImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Image with Stylezam"
    static let description = IntentDescription(
        "Open Stylezam and separate the clothing visible in an image from a previous Shortcut action."
    )
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(
        title: "Image",
        description: "A screenshot or fashion image to scan.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try StylezamShared.storePendingImage(image.data, origin: "screenCapture")
        StylezamShared.signalExternalRequest()
        return .result(dialog: "Opening Stylezam with this image.")
    }
}
