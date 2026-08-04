import Foundation

enum ScreenCaptureAvailability {
    static var isSDKAvailable: Bool {
        LiveScreenCaptureManager.isSupportedBySDK
    }

    static var summary: String {
        isSDKAvailable
            ? "Available through Apple’s system content-sharing picker."
            : LiveScreenCaptureManager.unsupportedSummary
    }
}
