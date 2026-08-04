# Setup and device checklist

## 1. Verify the repository

From the repository root:

```bash
./scripts/check.sh
```

The check performs four concrete validations:

1. verifies the bundled Core ML package byte counts and SHA-256 hashes;
2. verifies its Fashionpedia class order and license metadata;
3. regenerates the Xcode project and builds the app, widget, and Share extension;
4. confirms the built `.app` contains the compiled `.mlmodelc` and model manifest.

The model source lives at:

```text
App/Resources/Models/StylezamGarmentSegmentation.mlpackage
```

It is compiled by Xcode and included with the application. There is no separate model download or service configuration.

## 2. Generate and sign the iOS project

```bash
./scripts/generate_project.sh
open Stylezam.xcodeproj
```

`project.yml` is the source of truth for targets. Choose a Development Team for the app, Share extension, and widget extension. Replace the placeholder identifiers if your team cannot claim them:

- App: `com.stylezam.app`
- Widget: `com.stylezam.app.widgets`
- Share: `com.stylezam.app.share`
- Intended App Group: `group.com.stylezam.shared`

The checked-in entitlement files remain minimal so the main app can be signed by a free Personal Team. If your team supports App Groups, add the capability to all three targets and use the exact identifier in `Shared/AppGroup.swift`.

A free Personal Team can install the main app for seven-day device testing, but profiles expire and some extension capabilities may be unavailable. The final signed entitlements—not the source declarations alone—determine whether cross-process Share, Control Widget, and App Group handoff work.

## 3. Local vision inspection

Open Settings → Developer Debug → Vision Inspector. Choose a real photo or reuse the newest Library capture. The inspector runs the same bundled detector and crop generator used by production capture and shows:

- the source image with actual bounding boxes;
- model ID/version and bundle state;
- class labels and confidence;
- normalized geometry;
- transparent crops on light and dark backgrounds;
- crop dimensions and byte counts;
- measured local execution time;
- copyable diagnostic JSON without image bytes.

No inspector action uploads the photo or crops.

## 4. Physical-device checks

On the connected iPhone, verify:

- the app launches without a model-setup sheet or network configuration;
- Developer Debug reports the model as Built in;
- rear/front camera switching and flash availability;
- manual Photo capture;
- Live mode guidance, automatic capture, manual override, and cooldown;
- five-item default and the 1–12 developer limit;
- crop overlays align with portrait and landscape sources;
- transparent crop edges look correct on both light and dark backgrounds;
- repeated Live captures are suppressed;
- scan deletion removes source and crop files;
- Photos and clipboard import;
- offline capture works with Wi-Fi and cellular disabled;
- Live Activity and Dynamic Island presentations;
- Share and Control Center handoff when the App Group provisions.

Measure first-run and warm inference time, memory, battery, and thermals on the oldest supported device you intend to ship.

## 5. iOS 27 screen support

Extracting Apple’s ScreenCaptureKit sample ZIP is only a reference step. It does not install an SDK, add a framework to Stylezam, or enable the feature on a phone.

To finish verification:

1. install an Xcode version containing the iOS 27 SDK;
2. run Apple’s sample separately on the intended device;
3. regenerate and open Stylezam with that Xcode;
4. compile the conditional ScreenCaptureKit adapter;
5. confirm the screen-capture usage description/background behavior accepted by Xcode;
6. use Apple’s system picker and confirm a recent real frame becomes a Library scan;
7. test stop, denial, interruption, protected content, memory pressure, and app termination.

See [iOS 27 live screen](IOS27_SCREEN_CAPTURE.md). Keep Apple’s sample as reference code rather than copying its entire project into Stylezam.

## 6. Release checks

- Run `./scripts/check.sh` from a clean checkout.
- Build Debug and Release for simulator and physical-device SDKs.
- Confirm no provider key or development secret is present in source, Git history intended for publication, or the app bundle.
- Verify the compiled app contains one model copy, not both source and compiled packages.
- Test offline capture and Library deletion on a signed device.
- Complete privacy disclosures and model/dataset legal review.
