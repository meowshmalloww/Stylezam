import AppIntents

struct StylezamShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartStylezamCaptureShortcutIntent(),
            phrases: [
                "Capture a look with \(.applicationName)",
                "Find this outfit with \(.applicationName)",
            ],
            shortTitle: "Capture a Look",
            systemImageName: "viewfinder"
        )
        AppShortcut(
            intent: SearchStylezamImageIntent(),
            phrases: [
                "Search this image with \(.applicationName)",
                "Search this screenshot with \(.applicationName)",
            ],
            shortTitle: "Search an Image",
            systemImageName: "photo.badge.magnifyingglass"
        )
    }
}

private struct StartStylezamCaptureShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Look"
    static let description = IntentDescription(
        "Open Stylezam to capture clothing with the camera."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        StylezamShared.requestCapture()
        StylezamShared.signalExternalRequest()
        return .result()
    }
}
