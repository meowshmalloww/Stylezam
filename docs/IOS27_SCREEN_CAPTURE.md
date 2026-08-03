# iOS 27 live screen capture

## UX decision

Live screen is not an app tab. The user authorizes it through Apple’s system content-sharing picker from the capture section in Settings. Once active, Stylezam can continue receiving the selected display stream under the iOS 27 `screen-capture` background mode. The existing Control Center/Action Button control is the capture shutter.

This keeps two important boundaries visible:

- Stylezam cannot silently start a full-display stream.
- The user does not have to return to an artificial “live screen” page for each search.

## Implemented flow

1. `LiveScreenCaptureManager.presentSystemPicker()` configures and presents `SCContentSharingPicker.shared`.
2. `SCContentSharingPickerObserver` receives the user-selected `SCContentFilter`.
3. Stylezam starts an `SCStream` with a `.screen` output on a serial queue.
4. Frames are throttled to one JPEG roughly every 0.8 seconds and retained in a rolling in-memory buffer for at most 15 seconds.
5. The Capture a Look App Intent writes a shared timestamp and opens the app.
6. If a real frame exists, `AppModel` favors one captured roughly 1.8 seconds before the Control Center tap so the system overlay is less likely to cover the fashion content, then submits it to the same `/v1/searches` image pipeline. Otherwise the regular capture sheet opens.
7. The user can stop the stream in Settings; unexpected stream termination is surfaced there.

The implementation is conditional on `canImport(ScreenCaptureKit)`. This repository therefore builds with Xcode 26, whose iOS SDK does not expose the framework, and activates the real adapter when built with the iOS 27 SDK.

Apple’s current sample and API entry point: [Capturing screen content on iOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios).

## Required configuration

- Background mode: `screen-capture`
- Privacy string: `NSScreenCaptureUsageDescription`
- iOS 27 SDK to compile the ScreenCaptureKit branch
- iOS 27 device to run it
- App Group for the Control Widget timestamp

Apple’s current iOS sample documents the `screen-capture` background mode and system picker; it does not document a manually entered `com.apple.developer.screen-recording` entitlement. Configure background execution through Xcode, keep the usage description in the app plist, and let the signed iOS 27 build/system picker determine availability. Do not add a guessed entitlement key.

## Expected limitations

- Protected/DRM video can be blank and should remain blank.
- System privacy UI and indicators are controlled by iOS.
- A capture can contain private screen information. Stylezam sends a frame only after the user invokes Capture a Look.
- Buffered frames never go to disk. The submitted frame is normalized again by the backend, where metadata is removed.
- If iOS suspends or terminates the app, no stale on-disk screen frame is substituted; the normal capture sheet opens.

## Xcode 26 behavior

Camera, Photos, clipboard, Share, Control Center, Action Button, local Live Activities, and Dynamic Island all remain available. Settings explains that Xcode 27 is required. There is no ReplayKit simulation and no fake “live screen” animation.
