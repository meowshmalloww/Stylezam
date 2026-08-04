import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
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
        notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
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

    private enum Keys {
        static let notificationsEnabled = "stylezam.notifications-enabled"
        static let maxDetectedItems = "stylezam.max-detected-items"
        static let liveAutoCaptureEnabled = "stylezam.live-auto-capture-enabled"
    }
}
