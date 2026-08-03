import AppIntents

struct StylezamShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartStylezamCaptureIntent(),
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
