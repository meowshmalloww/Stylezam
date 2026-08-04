import Foundation

enum StylezamShared {
    static let appGroupIdentifier = "group.com.stylezam.shared"
    static let captureRequestKey = "stylezam.capture-requested-at"
    static let liveScreenRequestKey = "stylezam.live-screen-requested-at"
    static let pendingImageKey = "stylezam.pending-image-name"
    static let pendingTextKey = "stylezam.pending-text"
    static let pendingOriginKey = "stylezam.pending-origin"
    static let pendingScanIDKey = "stylezam.pending-scan-id"
    static let externalRequestNotification = Notification.Name("stylezam.external-request")

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    /// App Intents that execute in the main app can still hand off files when a
    /// free Personal Team profile cannot provision App Groups. Share-extension
    /// handoff across separate sandboxes continues to require the App Group.
    static var handoffContainerURL: URL {
        if let containerURL { return containerURL }
        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "StylezamHandoff", directoryHint: .isDirectory)
    }

    static func requestCapture() {
        defaults.set(Date().timeIntervalSince1970, forKey: captureRequestKey)
    }

    static func requestLiveScreen() {
        defaults.set(Date().timeIntervalSince1970, forKey: liveScreenRequestKey)
    }

    static func signalExternalRequest() {
        NotificationCenter.default.post(name: externalRequestNotification, object: nil)
    }

    /// Persists an image for the main app to consume after an App Intent or extension handoff.
    /// The relative path is stored only after the atomic file write succeeds, so the app never
    /// observes a half-written capture.
    @discardableResult
    static func storePendingImage(
        _ data: Data,
        origin: String = "shareExtension"
    ) throws -> String {
        let containerURL = handoffContainerURL
        let directory = containerURL.appending(path: "Pending", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let relativePath = "Pending/\(UUID().uuidString).image"
        try data.write(
            to: containerURL.appending(path: relativePath),
            options: .atomic
        )
        defaults.set(relativePath, forKey: pendingImageKey)
        defaults.set(origin, forKey: pendingOriginKey)
        return relativePath
    }
}
