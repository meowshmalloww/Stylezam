import Foundation

enum StylezamShared {
    static let appGroupIdentifier = "group.com.stylezam.shared"
    static let captureRequestKey = "stylezam.capture-requested-at"
    static let pendingImageKey = "stylezam.pending-image-name"
    static let pendingTextKey = "stylezam.pending-text"
    static let pendingOriginKey = "stylezam.pending-origin"
    static let pendingSearchIDKey = "stylezam.pending-search-id"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    static func requestCapture() {
        defaults.set(Date().timeIntervalSince1970, forKey: captureRequestKey)
    }

    /// Persists an image for the main app to consume after an App Intent or extension handoff.
    /// The relative path is stored only after the atomic file write succeeds, so the app never
    /// observes a half-written capture.
    @discardableResult
    static func storePendingImage(
        _ data: Data,
        origin: String = "shareExtension"
    ) throws -> String {
        guard let containerURL else {
            throw CocoaError(.fileNoSuchFile)
        }
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
