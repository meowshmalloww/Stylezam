import Foundation

enum ScreenCaptureAvailability {
    static var isSDKAvailable: Bool {
        LiveScreenCaptureManager.isSupportedBySDK
    }

    static var summary: String {
        isSDKAvailable
            ? "Available through Apple’s system content-sharing picker."
            : "Install Xcode 27 to compile iOS 27 ScreenCaptureKit support. Camera, Photos, Share, and Control Center capture remain available."
    }
}
