import AppIntents
import UniformTypeIdentifiers

struct SearchStylezamImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Image with Stylezam"
    static let description = IntentDescription(
        "Open Stylezam and search the clothing visible in an image from a previous Shortcut action."
    )
    static let openAppWhenRun = true

    @Parameter(
        title: "Image",
        description: "A screenshot or fashion image to search.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try StylezamShared.storePendingImage(image.data, origin: "screenCapture")
        return .result(dialog: "Opening Stylezam with this image.")
    }
}
