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

    init() {
        backendURLString = UserDefaults.standard.string(forKey: Keys.backendURL)
            ?? "http://127.0.0.1:8000"
        notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        backendToken = KeychainStore.string(for: Keys.backendToken) ?? ""
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
    }
}
