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

It is compiled by Xcode and included with the application. There is no separate model download. Local capture works without search credentials.

## 2. Configure required Firebase Google Sign-In

Stylezam requires a Firebase-authenticated Google account after first-run onboarding. Authentication identity and signed role claims live in Firebase Auth; the editable Stylezam profile and Library remain local. Stylezam does not use Firestore for profiles.

1. Create a Firebase project and add an Apple app with bundle ID `com.stylezam.app`.
2. In Firebase **Authentication → Sign-in method**, enable **Google**.
3. After saving the Google provider, download a fresh `GoogleService-Info.plist`. Confirm it contains `CLIENT_ID`, `REVERSED_CLIENT_ID`, and `IS_SIGNIN_ENABLED = YES`, then place it at:

   ```text
   App/Resources/GoogleService-Info.plist
   ```

4. Copy the local URL-scheme template:

   ```bash
   cp Config/Firebase.local.xcconfig.example Config/Firebase.local.xcconfig
   ```

5. Open the plist, copy `REVERSED_CLIENT_ID`, and set it as `GOOGLE_REVERSED_CLIENT_ID` in `Config/Firebase.local.xcconfig`.
6. Regenerate the project with `./scripts/generate_project.sh` and rebuild.

Firebase Core, Auth, Google Sign-In, and Analytics Core are managed through Swift Package Manager in `project.yml`. The Analytics variant has no IDFA collection capability, and `Info.plist` disables IDFV collection. Both local configuration files are ignored by Git. Firebase documents that the plist contains project/app identifiers rather than a server secret, but Stylezam keeps the developer-specific file local to prevent accidental cross-project configuration. Never place a Firebase Admin service-account key in the app.

For a second developer, follow [`TEAMMATE_HANDOFF.md`](TEAMMATE_HANDOFF.md).
Share the repository through Git and the Firebase client plist privately. Do not
send the Firebase Admin service-account JSON or Apple signing credentials.

### Grant the two internal developer accounts

Each approved Google account must sign in once before Firebase has a UID for it. Then use the local utility under `tools/firebase-admin`:

```bash
cd tools/firebase-admin
npm install
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/service-account.json
chmod 600 "$GOOGLE_APPLICATION_CREDENTIALS"
export STYLEZAM_DEVELOPER_EMAILS='approved-one@example.com,approved-two@example.com'
npm run grant-developer -- approved-one@example.com
npm run grant-developer -- approved-two@example.com
```

Use the two addresses approved for this project in the environment variable. The script checks the allowlist, preserves existing claims, and assigns `developer: true` plus `plan: "developer"`. It writes no Firestore record. Sign out/in afterward or tap **Refresh developer access**. Debug and Release builds reveal Developer Debug only for a refreshed Firebase ID token containing the signed custom claim.

## 3. Configure private developer search

```bash
cp .env.example .env
chmod 600 .env
```

Add only the providers you intend to test. `.env` is ignored by Git and is not bundled into the app. `scripts/install_on_device.sh` passes the values into one Debug launch; Stylezam immediately stores them in the device-only Keychain. Developer Debug is status-only—keys cannot be viewed, pasted, or replaced inside the app. Rotate a key in the local `.env`, then reinstall/relaunch the Debug build.

The visual path sends one request for a selected garment to the preferred eligible provider chosen in Developer Debug. If that preference cannot accept the current local crop, Stylezam names and uses an eligible fallback. Lykdat accepts selected crop bytes directly. Fireworks powers the separate Stylezam AI chat; Serper is used only when the user turns an AI request into a similar-product search. SearchAPI.io and SerpApi Google Lens require a public HTTPS crop URL. Bright Data requires both that URL and a compatible SERP zone; the currently configured zone authenticates but returns an inner Lens HTTP 502, so it is not eligible until both conditions are corrected.

## 4. Generate and sign the iOS project

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

## 5. Local vision inspection

Open Settings → Developer Debug → Vision Inspector. Choose a real photo or reuse the newest Library capture. The inspector runs the same bundled detector and crop generator used by production capture and shows:

- the source image with actual bounding boxes;
- model ID/version and bundle state;
- class labels and confidence;
- normalized geometry;
- the complete saved bounding-box crop;
- the raw transparent cutout on a checkerboard and its black/white alpha mask;
- source, box-crop, and cutout dimensions and byte counts;
- measured local execution time;
- copyable diagnostic JSON without image bytes.

No inspector action uploads the photo or crops.

## 6. Physical-device checks

On the connected iPhone, verify:

- the app launches without a model-setup sheet or network configuration;
- the five-page first-run experience cannot enter the main app without Google authentication;
- **Replay First Run** under Settings → Developer shows onboarding again without deleting Library data;
- Google Sign-In restores the account after relaunch;
- profile edits survive relaunch locally and sign-out returns to the required login screen;
- Free is the active public plan; Plus/Pro are non-purchasable previews;
- Debug and Release builds require a Firebase `developer: true` custom claim for Developer Debug and unlimited usage;
- Developer Debug reports the model as Built in;
- rear/front camera switching and flash availability;
- manual Photo capture;
- Live mode guidance, automatic capture, manual override, and cooldown;
- Live labels remain hidden until the same region/category agrees across frames,
  overlays do not flicker between near-identical competing boxes, and an
  automatic save uses a full-quality still rather than a preview JPEG;
- five-item default and the 1–12 developer limit;
- crop overlays align with portrait and landscape sources;
- the box crop contains the complete detected region and the separate raw mask
  makes any missing or incorrect region visible;
- repeated Live captures are suppressed;
- scan deletion removes source and crop files;
- one selected garment produces one persisted product-search attempt by default;
- Search diagnostics records the actual provider-call count, latency, outcome, and result count;
- completed searches remain under Library → Matches and can be deleted;
- Photos and clipboard import;
- offline capture works with Wi-Fi and cellular disabled;
- Live Activity and Dynamic Island presentations;
- Share and Control Center handoff when the App Group provisions.

Measure first-run and warm inference time, memory, battery, and thermals on the oldest supported device you intend to ship.

## 7. iOS 27 screen support

Extracting Apple’s ScreenCaptureKit sample ZIP is only a reference step. It does not install an SDK, add a framework to Stylezam, or enable the feature on a phone.

To finish verification:

1. move the extracted beta to `/Applications/Xcode-beta.app`, open it once, and install its required components;
2. select it with `sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer` or set the command-line tools inside Xcode Settings;
3. run Apple’s sample separately on the intended device;
4. regenerate and open Stylezam with that Xcode;
5. compile the conditional ScreenCaptureKit adapter;
6. add both **Capture a Look** and **Live Screen** from the Control Center gallery;
7. use Live Screen and confirm Apple’s picker appears before a recent real frame becomes a Library scan;
8. test stop, denial, interruption, protected content, memory pressure, and app termination.

See [iOS 27 live screen](IOS27_SCREEN_CAPTURE.md). Keep Apple’s sample as reference code rather than copying its entire project into Stylezam.

## 8. YouCam photo try-on

Try On is optional and does not affect local garment detection. For a prototype build, either enter the YouCam API key once in the Try On screen (it is stored in this device's Keychain), or add `STYLEZAM_YOUCAM_API_KEY` to the ignored `.env` file. `scripts/install_on_device.sh` passes that value only to the Debug launch, and the app imports it into the device-only Keychain.

The app separates YouCam inputs into Outfit, Hand/Wrist, and Face/Neck photo contexts because jewelry endpoints require closer framing than clothing. The Try On workspace can take a new front/rear-camera photo or import one from Photos. Images are normalized to YouCam's supported bounds and remain under 10 MB. The UI verifies the connection, requires explicit upload consent, shows the real request phase, and explains YouCam's documented retention boundary.

Do not distribute an app containing a shared YouCam bearer credential. Before release, put authentication and YouCam calls behind a scoped Stylezam server, rotate all development keys, add abuse/rate controls, and complete the provider data-retention review.

## 9. Release checks

- Run `./scripts/check.sh` from a clean checkout.
- Build Debug and Release for simulator and physical-device SDKs.
- Confirm no provider key or development secret is present in source, Git history intended for publication, or the app bundle.
- Verify the compiled app contains one model copy, not both source and compiled packages.
- Test offline capture and Library deletion on a signed device.
- Complete privacy disclosures and model/dataset legal review.
