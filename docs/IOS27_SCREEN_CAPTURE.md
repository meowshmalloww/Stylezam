# iOS 27 live screen capture

## Product decision

Live screen is a consent-based capture source, not an app tab. The user starts it from Capture & Controls using Apple’s system content-sharing picker. Once an authorized stream exists, the Stylezam Control Center or Action Button control acts as the shutter. iOS owns the privacy indicator; Stylezam does not draw a custom blue border over other apps. Stylezam also starts a local “Live screen active” Live Activity for supported Dynamic Island and Lock Screen surfaces, then ends it when the stream stops or is interrupted.

The Control Center controls open explicit `stylezam://live-screen` and
`stylezam://capture-request` routes. They do not depend on App Group shared
defaults, so the handoff also works in free Personal Team builds where Apple
does not provision the App Group entitlement.

The feature is iOS 27-only. iOS 18–26 continue to support camera, Photos, Share, clipboard, Screenshot Shortcut, and Control Center entry into the normal capture sheet.

## Existing adapter

The repository already contains a conditional `LiveScreenCaptureManager`:

1. `SCContentSharingPicker.shared` presents Apple’s picker.
2. The picker observer supplies an `SCContentFilter` after consent.
3. An `SCStream` receives screen output on a serial queue.
4. JPEG frames are throttled and held in a short rolling in-memory buffer.
5. The capture App Intent writes a shared timestamp and opens Stylezam.
6. `AppModel` consumes a recent frame and runs the same on-device segmentation/Library pipeline as a photo.
7. Stopping or losing the stream clears state and surfaces an honest status.

The source is guarded by `canImport(ScreenCaptureKit)` and iOS availability checks, so Xcode 26 builds the unavailable branch rather than a ReplayKit simulation.

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

## Current blocker on this Mac

The installed environment is Xcode 26.6 on macOS 26.2 with the iOS 26.5 SDK. Apple lists Xcode 27 beta 4 as requiring macOS 26.4 or later. Therefore the iOS 27 branch cannot be truthfully compiled or device-verified here yet: [Xcode system requirements](https://developer.apple.com/xcode/system-requirements).

## Privacy and platform limits

- Stylezam cannot silently select a display or app.
- Protected/DRM output may be blank and must remain blank.
- The frame buffer stays in memory and is cleared when capture stops.
- A frame leaves the phone only as accepted garment crops after a user capture action.
- The system indicator and Dynamic Island/Live Activity are the allowed status surfaces.
- A custom overlay surrounding another app is not part of this design.
- If the OS suspends or terminates Stylezam and no valid recent frame exists, the normal camera sheet opens instead of fabricating a screen result.
