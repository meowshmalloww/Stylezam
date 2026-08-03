import UIKit
import UserNotifications

extension Notification.Name {
    static let stylezamOpenSearch = Notification.Name("stylezam.open-search")
}

final class StylezamAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let searchID = response.notification.request.content.userInfo["searchID"] as? String
        else { return }
        StylezamShared.defaults.set(searchID, forKey: StylezamShared.pendingSearchIDKey)
        await MainActor.run {
            NotificationCenter.default.post(name: .stylezamOpenSearch, object: searchID)
        }
    }
}
