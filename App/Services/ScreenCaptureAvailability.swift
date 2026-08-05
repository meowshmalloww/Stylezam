import Foundation
import UIKit

@MainActor
enum ScreenCaptureAvailability {
    static var isSDKAvailable: Bool {
        LiveScreenCaptureManager.isSupportedBySDK
    }

    static var summary: String {
        isSDKAvailable
            ? "Available through Apple’s system content-sharing picker."
            : LiveScreenCaptureManager.unsupportedSummary
    }

    static var isDeviceOSSupported: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    static var badge: String {
        if isSDKAvailable { return "AVAILABLE" }
        if isDeviceOSSupported { return "REBUILD NEEDED" }
        return "iOS 27"
    }

    static var deviceSummary: String {
        "iOS \(UIDevice.current.systemVersion)"
    }

    static var buildSummary: String {
        #if canImport(ScreenCaptureKit)
        "iOS 27 ScreenCaptureKit included"
        #else
        "Built without the iOS 27 ScreenCaptureKit SDK"
        #endif
    }

    static var recoverySummary: String? {
        guard !isSDKAvailable else { return nil }
        if isDeviceOSSupported {
            return "This iPhone is compatible, but the installed Stylezam build does not contain the iOS 27 screen-capture code. Update this Mac to macOS 26.4 or later, install Xcode 27, then rebuild and reinstall Stylezam."
        }
        return "Live Screen requires iOS 27. Screenshot Shortcut, Share, Photos, clipboard, and camera capture remain available on this device."
    }
}
