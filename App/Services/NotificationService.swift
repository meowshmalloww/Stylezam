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

    func captureFinished(
        itemCount: Int,
        scanID: UUID,
        detailedLabelsReady: Bool
    ) async {
        let content = UNMutableNotificationContent()
        content.title = detailedLabelsReady
            ? "Your Stylezam capture is ready"
            : "Capture saved on this iPhone"
        if itemCount == 0 {
            content.body = "The look is in your Library. No distinct fashion pieces were confirmed."
        } else if itemCount == 1 {
            content.body = detailedLabelsReady
                ? "1 piece is labeled and ready to review."
                : "1 piece is saved locally; detailed labels are unavailable."
        } else {
            content.body = detailedLabelsReady
                ? "\(itemCount) pieces are labeled and ready to review."
                : "\(itemCount) pieces are saved locally; detailed labels are unavailable."
        }
        content.sound = .default
        content.userInfo = ["scanID": scanID.uuidString]
        let request = UNNotificationRequest(
            identifier: "stylezam-capture-\(scanID.uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
