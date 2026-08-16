import Foundation
import UserNotifications

actor NotificationService {
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge]
            )
        } catch {
            return false
        }
    }

    func captureFinished(
        itemCount: Int,
        scanID: UUID,
        detectionReady: Bool
    ) async {
        let content = UNMutableNotificationContent()
        content.title = detectionReady
            ? "Your Stylezam capture is ready"
            : "Capture saved on this iPhone"
        if itemCount == 0 {
            content.body = "The look is in your Library. No distinct fashion pieces were confirmed."
        } else if itemCount == 1 {
            content.body = detectionReady
                ? "1 piece was detected on this iPhone and is ready to review."
                : "1 piece is saved locally."
        } else {
            content.body = detectionReady
                ? "\(itemCount) pieces were detected on this iPhone and are ready to review."
                : "\(itemCount) pieces are saved locally."
        }
        content.userInfo = ["scanID": scanID.uuidString]
        let request = UNNotificationRequest(
            identifier: "stylezam-capture-\(scanID.uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
