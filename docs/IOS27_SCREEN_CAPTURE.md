# iOS 27 live screen capture

## Product decision

Live screen is a consent-based capture source, not an app tab. The user starts it from Capture & Controls using Apple’s system content-sharing picker. After the user chooses **Share Entire Screen**, the authorized stream continues while Stylezam is in the background. Stylezam samples it on device and automatically saves a garment only after label, position, perceptual appearance, and quality agree across three analyzed frames. The Capture a Look control remains a manual shutter. iOS owns the privacy indicator; Stylezam does not draw a custom blue border over other apps. Stylezam also starts a local “Live screen active” Live Activity for supported Dynamic Island and Lock Screen surfaces, then ends it when the stream stops or is interrupted.

The controls use an `OpenIntent` with a typed capture destination. The app handles
that intent with SwiftUI's `onAppIntentExecution` and opens either the camera or
Apple's screen picker after startup. This is important: `OpenURLIntent` supports
universal HTTPS links, not `stylezam://` custom schemes, so a custom-scheme
ControlWidget action can silently do nothing.

Live Screen is iOS 27-only. iOS 18–26 continue to support camera, Photos, Share, clipboard, and Screenshot Shortcut. The typed Control Center controls require iOS 26; on iOS 26, Capture a Look works and Live Screen explains that screen streaming requires iOS 27.

## Existing adapter

The repository already contains a conditional `LiveScreenCaptureManager`:

1. `SCContentSharingPicker.shared` presents Apple’s picker.
2. The picker observer supplies an `SCContentFilter` after consent.
3. An `SCStream` receives screen output on a serial queue.
4. Complete frames are rotation-corrected, encoded directly from their Core Image buffers at device resolution, thermally throttled, and held in a short rolling in-memory buffer.
5. A cheap four-region, 480 px fingerprint waits for scrolling or video motion to settle before Core ML runs.
6. One crop-free global-plus-detail discovery keeps items near the top, middle, or bottom of a tall page visible. Later confirmation frames run one focused model tensor around the strongest item; three matching garment observations are required before automatic capture.
7. Captured, duplicate, and twice-verified empty screens enter a four-second nominal watch cadence and run no further Core ML until the screen fingerprint changes.
8. Garment-region perceptual deduplication remains a second guard against Library duplicates.
9. `AppModel` sends the accepted full-resolution frame through the same bounded detail-tile, crop, Library, Live Activity, and notification pipeline as a camera still.
10. The Capture a Look `OpenIntent` remains an immediate manual shutter for the authorized stream.
11. Stopping or losing the stream clears frame state and surfaces an honest status.

Live camera and Live Screen have separate automatic-capture preferences. Both default on; disabling the camera auto-shutter does not disable background screen detection.

The source is guarded by `canImport(ScreenCaptureKit)` and iOS availability checks, so an older SDK builds the unavailable branch rather than a ReplayKit simulation. Apple does not include ScreenCaptureKit in the iOS Simulator SDK; picker and streaming validation therefore require a physical iPhone.

Apple’s API and sample are the reference: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [Capturing screen content on iOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios).

## Why extracting Apple’s ZIP is not enough

The ZIP is a sample Xcode project. Extraction only makes its source files available to read. It does not install Xcode 27, install the iOS 27 SDK, change Stylezam’s build settings, add background modes, provision App Groups, sign extensions, or validate your phone.

The correct sequence is:

1. Update the Mac to at least macOS 26.4.
2. Install Xcode 27 beta; Apple currently lists that combination as required for the iOS 27 SDK.
3. Build Apple’s sample by itself on the iOS 27 phone.
4. Build Stylezam with Xcode 27 so the existing conditional code becomes active.
5. Resolve any beta-API signature changes against the installed SDK.
6. Confirm the `screen-capture` background mode and `NSScreenCaptureUsageDescription` in the signed app.
7. Test picker consent, denial, stream interruption, app backgrounding/termination, protected content, and real Control Center capture.

Do not copy the entire sample project into Stylezam. Compare the sample’s current API calls and required configuration with Stylezam’s small adapter.

## Current verification

- Xcode 27 beta 4 and its iOS 27 device SDK compile the ScreenCaptureKit adapter.
- The signed app and widget extension build and install on the connected iOS 27 iPhone.
- The installed physical-device build presents Apple's real Screen Sharing picker with Stylezam selected and the **Share Entire Screen** consent action.
- Automatic capture coordination is covered by deterministic tests for three-frame stabilization, low-quality interruption, stationary duplicate suppression, new-garment acceptance, garment-hash stability, unchanged-screen suppression, and changed-screen resumption.
- A tall-screen integration test places a product near the top of a 1290×2796 frame and verifies detail-aware preview detection plus a crop larger than the model's 384×384 tensor.
- An automated iOS 27 simulator test opens the real Control Center, installs the Stylezam Live Screen control, taps it, and verifies that Stylezam reaches the foreground.
- The same simulator cannot verify Apple's sharing picker because its SDK omits ScreenCaptureKit. The physical-device UI-test runner requires its own provisioning profile; without that profile, stream authorization remains a manual device step because Apple requires explicit user consent.

## Privacy and platform limits

- Stylezam cannot silently select a display or app.
- iOS requires Stylezam to present the system picker and does not provide an API to programmatically return to the previously used app.
- Protected/DRM output may be blank and must remain blank.
- The frame buffer stays in memory and is cleared when capture stops.
- A stable automatic capture becomes a local source image and local garment crops. Nothing is uploaded until the user explicitly starts Search or Try On.
- The system indicator and Dynamic Island/Live Activity are the allowed status surfaces.
- A custom overlay surrounding another app is not part of this design.
- If the OS suspends or terminates Stylezam and no valid recent frame exists, the normal camera sheet opens instead of fabricating a screen result.
