import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    var backendURLString: String {
        didSet {
            UserDefaults.standard.set(backendURLString, forKey: Keys.backendURL)
        }
    }

    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    var backendToken: String {
        didSet {
            KeychainStore.set(
                backendToken.trimmingCharacters(in: .whitespacesAndNewlines),
                for: Keys.backendToken
            )
        }
    }

    var maxDetectedItems: Int {
        didSet {
            maxDetectedItems = min(12, max(1, maxDetectedItems))
            UserDefaults.standard.set(maxDetectedItems, forKey: Keys.maxDetectedItems)
        }
    }

    var liveAutoCaptureEnabled: Bool {
        didSet {
            UserDefaults.standard.set(liveAutoCaptureEnabled, forKey: Keys.liveAutoCaptureEnabled)
        }
    }

    init() {
        backendURLString = UserDefaults.standard.string(forKey: Keys.backendURL)
            ?? ""
        notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        backendToken = KeychainStore.string(for: Keys.backendToken) ?? ""
        let storedMax = UserDefaults.standard.integer(forKey: Keys.maxDetectedItems)
        maxDetectedItems = storedMax == 0 ? 5 : min(12, max(1, storedMax))
        if UserDefaults.standard.object(forKey: Keys.liveAutoCaptureEnabled) == nil {
            liveAutoCaptureEnabled = true
        } else {
            liveAutoCaptureEnabled = UserDefaults.standard.bool(
                forKey: Keys.liveAutoCaptureEnabled
            )
        }
    }

    func client() throws -> APIClient {
        let token = backendToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return try APIClient(
            baseURLString: backendURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            bearerToken: token.isEmpty ? nil : token
        )
    }

    private enum Keys {
        static let backendURL = "stylezam.backend-url"
        static let notificationsEnabled = "stylezam.notifications-enabled"
        static let backendToken = "stylezam.backend-token"
        static let maxDetectedItems = "stylezam.max-detected-items"
        static let liveAutoCaptureEnabled = "stylezam.live-auto-capture-enabled"
    }
}
