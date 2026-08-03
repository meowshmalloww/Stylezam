import Foundation
import UserNotifications

actor NotificationService {
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
        } catch {
            return false
        }
    }

    func searchFinished(resultCount: Int, searchID: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Your Stylezam matches are ready"
        content.body = resultCount == 1
            ? "1 product match is ready to review."
            : "\(resultCount) product matches are ready to review."
        content.sound = .default
        content.userInfo = ["searchID": searchID]
        let request = UNNotificationRequest(
            identifier: "stylezam-search-\(searchID)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

