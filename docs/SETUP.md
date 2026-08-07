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

## 2B. Configure StoreKit plans

StoreKit product IDs are `com.stylezam.app.plus.monthly`, `com.stylezam.app.plus.annual`, `com.stylezam.app.pro.monthly`, and `com.stylezam.app.pro.annual`. Create them in one subscription group in App Store Connect. Stylezam loads localized prices, calculates the annual discount from the configured App Store prices, verifies transactions on device, and supports Restore Purchases.

## 3. Configure private developer search

```bash
cp .env.example .env
chmod 600 .env
```

Add only the providers you intend to test. `.env` is ignored by Git and is not bundled into the app. `scripts/install_on_device.sh` passes the values into one Debug launch; Stylezam immediately stores them in the device-only Keychain. Developer Debug is status-only—keys cannot be viewed, pasted, or replaced inside the app. Rotate a key in the local `.env`, then reinstall/relaunch the Debug build.

The visual path sends one request for a selected garment to the next eligible visual provider, then advances the persisted route for the next search. Lykdat and Google Cloud Vision Web Detection accept selected crop bytes directly. SearchAPI.io, SerpApi, and Bright Data Lens require an explicitly configured public HTTPS crop URL; Stylezam never publishes a private crop to make them eligible. Fireworks powers the separate persistent Stylezam AI chat. After the user explicitly chooses **Find similar** or **Find cheaper**, Stylezam sends Qwen-generated keyword text, not the photo, to the next eligible Serper, SearchAPI.io, SerpApi, or Bright Data text-shopping route. Each action calls only one provider.

### Google Cloud Vision Web Detection

1. Attach a Cloud Billing account to the Google Cloud project. Google requires billing to be enabled before Vision runs, even though its pricing tier lists the first 1,000 units per month as free.
2. Enable **Cloud Vision API** in the Google Cloud project that owns the key.
3. In **APIs & Services → Credentials**, restrict the key's API target to **Cloud Vision API** and its application restriction to the iOS bundle ID `com.stylezam.app`. Stylezam sends that bundle ID in `X-Ios-Bundle-Identifier`.
4. Add `STYLEZAM_GOOGLE_VISION_API_KEY` to the ignored `.env`, reinstall/launch the Debug build, then choose **Google Cloud Vision Web Detection** under Developer Debug → Product search.
5. Confirm Search Usage & Diagnostics reports `Google Vision` after each explicit search.

Each request contains one image and only one `WEB_DETECTION` feature, making the Stylezam action one Vision feature unit. The local monthly setting defaults to 1,000, can be lowered, and cannot be raised past 1,000. A separate counter reserves the unit before networking and is not cleared with diagnostics. This is a device-side safety boundary: key reuse, another client, reinstalling the app, or deleting app data is outside it, so Google Cloud restrictions and monitoring remain required. Web Detection returns pages and matching or visually similar images; it does not promise shopping listings or prices.

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
- the six-page first-run experience supports forward, back, and swipe navigation and completes only from its final page;
- the six-page first-run experience appears once for the current onboarding version and does not add a replay control to Settings;
- Google Sign-In restores the account after relaunch;
- profile edits survive relaunch locally and sign-out returns to the required login screen;
- Free is the fallback public plan; configured Plus/Pro monthly and annual products load localized prices from StoreKit and restore verified entitlements;
- Stylezam AI voice input refuses server speech recognition, keeps audio transient, and places the on-device transcript in the editable composer;
- a Library-wide AI question retrieves no more than four metadata records and sends no more than two additional relevant crops;
- Debug and Release builds require a Firebase `developer: true` custom claim for Developer Debug and unlimited usage;
- Developer Debug reports the model as Built in;
- rear/front camera switching, flash availability, pinch zoom, and the displayed 0.5× / 1× / 2× / 3× zoom controls where supported;
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
- Google Vision stops locally at the configured limit and never allows a value above 1,000;
- Stylezam AI remembers prior turns for the selected piece, generates usable follow-up prompts, and clears only the selected conversation from its menu;
- Find similar and Find cheaper each make one Fireworks request followed by one request to the next eligible rotating keyword-shopping provider;
- Stylezam AI returns a schema-valid answer instead of a generic unreadable-response error, and failed turns expose a retry action;
- shopping cards show currency-formatted prices and expose a percentage only for a provider score or reproducible query overlap;
- completed searches remain under Library → Matches and can be deleted;
- Photos and clipboard import;
- offline capture works with Wi-Fi and cellular disabled;
- Live Activity and Dynamic Island presentations;
- Share and Control Center handoff when the App Group provisions.

Measure first-run and warm inference time, memory, battery, and thermals on the oldest supported device you intend to ship.

## 7. iOS 27 screen support

Extracting Apple’s ScreenCaptureKit sample ZIP is only a reference step. It does not install an SDK, add a framework to Stylezam, or enable the feature on a phone.

To finish verification:

1. move the extracted beta to `/Applications/Xcode-beta.app` or keep it beside the Stylezam project, open it once, accept its license, and install its required components;
2. run `./scripts/check.sh`; the script automatically selects a nearby Xcode 27 beta and rejects an older iOS SDK, or honors an explicit `DEVELOPER_DIR`;
3. run Apple’s sample separately on the intended device;
4. regenerate and open Stylezam with that Xcode;
5. compile the conditional ScreenCaptureKit adapter;
6. add both **Capture a Look** and **Live Screen** from the Control Center gallery; their typed `OpenIntent` handoff does not require an App Group entitlement;
7. use Live Screen, choose **Share Entire Screen**, return to stable fashion content, and confirm the automatic detector creates a high-resolution Library scan without another shutter tap;
8. test stop, denial, interruption, protected content, memory pressure, and app termination.

See [iOS 27 live screen](IOS27_SCREEN_CAPTURE.md). Keep Apple’s sample as reference code rather than copying its entire project into Stylezam.

## 8. YouCam photo try-on

Try On is optional and does not affect local garment detection. Accepted garment crops enter the local persistent wardrobe and Try On rail in the off state without a key or network request. Opening Try On from a piece activates only that piece; the user can then add others. A later explicit successful product search best-effort attaches a shoppable product to the exact source rail item without replacing or redownloading its detected crop; this enrichment does not change whether the search succeeded. For a prototype build, add `STYLEZAM_YOUCAM_API_KEY` to the ignored `.env` file. `scripts/install_on_device.sh` passes that value only to the Debug launch, and the app imports it into the device-only Keychain.

The app separates YouCam inputs into Outfit, Hand/Wrist, and Face/Neck photo contexts because several jewelry endpoints require closer framing than clothing. It infers the context from the selected pieces and person photo, then keeps the manual picker available as a correction. An Outfit photo can still apply a necklace with the clothing look. Selected pieces that do not match the active context stay parked and are excluded before any paid request. The Try On workspace opens its in-app camera front-facing, shows a transparent three-second countdown before capture, supports rear/front switching, pinch and preset zoom, or Photos import. Person photos persist locally and can be reused by swiping. The expandable Pieces/Shop rail persists selection state and available merchant links; removing a rail entry does not delete its wardrobe item.

Images are normalized to YouCam's supported bounds and remain under 10 MB. The UI verifies basic credential connectivity, requires explicit upload consent, shows the real request phase and exact task count, and explains YouCam's documented retention boundary. One Create action applies compatible selected items sequentially through category-specific tasks, using each result as the source for the next item; it is not a one-call multi-garment operation. Clothes use V4, including `change_shoes = false` when shoes are not the selected category. Lower-body references must visibly show the garment being worn by one clear person rather than as a standalone product image. For a detected lower-body piece, Stylezam stores the full originating frame as a separate durable, best-effort reference candidate while continuing to show its tight crop in the rail. Strong bedding/furniture references and implausible single-accessory full-scene outputs are blocked locally. The rail reports missing state, blocks Create when needed, and lets the user replace the reference from Photos. Identical full-frame bytes share one content-addressed file. Optional post-processing can apply enhancement, lighting, background removal, or background replacement. **View as video** requests a five-second YouCam image-to-video v2 result at 480p, 720p, or 1080p and provides a replay control that does not cover the generated image. Saving records the still plus applied and parked item manifests and their available purchase links.

The feature-cost connection check does not prove that the account is entitled to every category or image-to-video operation. Before treating this workflow as release-ready, run a real entitled-key smoke test on a physical device covering multi-item composition, lower-body reference handling, video generation/playback, save/relaunch, and remote cleanup.

Do not distribute an app containing a shared YouCam bearer credential. Before release, put authentication and YouCam calls behind a scoped Stylezam server, rotate all development keys, add abuse/rate controls, and complete the provider data-retention review.

## 9. Release checks

- Run `./scripts/check.sh` from a clean checkout.
- Build Debug and Release for simulator and physical-device SDKs.
- Confirm no provider key or development secret is present in source, Git history intended for publication, or the app bundle.
- Verify the compiled app contains one model copy, not both source and compiled packages.
- Test offline capture and Library deletion on a signed device.
- Complete privacy disclosures and model/dataset legal review.
