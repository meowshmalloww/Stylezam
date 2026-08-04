import UIKit
import UserNotifications

extension Notification.Name {
    static let stylezamOpenScan = Notification.Name("stylezam.open-scan")
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
        let userInfo = response.notification.request.content.userInfo
        if let scanID = userInfo["scanID"] as? String {
            StylezamShared.defaults.set(scanID, forKey: StylezamShared.pendingScanIDKey)
            await MainActor.run {
                NotificationCenter.default.post(name: .stylezamOpenScan, object: scanID)
            }
        }
    }
}
