# Privacy and data handling

This document describes the local-vision, developer product-search, and optional photo try-on build. YouCam receives data only when the user explicitly creates a try-on.

Each executable bundle includes an Apple `PrivacyInfo.xcprivacy` manifest for the required-reason APIs it uses. The manifests declare no tracking and no tracking domains. App Store privacy answers still require final account-specific review.

## Account identity

The main app requires Google Sign-In. Firebase Authentication processes and retains the authentication account identifier, Google email, display name/photo reference, sign-in tokens, and signed access claims according to the Firebase/Google configuration and policies. Stylezam does not use Firestore for profile storage. The editable Stylezam display name, username, and style note are keyed by Firebase UID in local `UserDefaults` on the iPhone.

Developer access is accepted only from a refreshed Firebase ID token containing `developer: true`. Developer Debug remains hidden from other accounts in Debug and Release builds. The approved-email allowlist and Firebase Admin service-account credential stay in a local administrator environment and are never bundled into the iOS application.

The app links Firebase Analytics Core without IDFA collection capability. Identifier-for-Vendor collection is disabled in `Info.plist`. If Analytics collection is enabled for the Firebase project, aggregate app-use events can be sent to Firebase after startup, so the public privacy policy and App Store privacy answers must match the final console and runtime configuration before release.

## What stays on the iPhone

- The bundled Core ML garment model and compiled representation.
- Live preview inference, boxes, masks, quality guidance, and duplicate fingerprints.
- Accepted camera/import/share/screen images.
- Individual garment box crops and structured detection records. Raw
  transparent-mask output is shown only during the local Vision Inspector run.
- Per-garment Stylezam AI conversation history and generated follow-up prompts.
- The recent iOS 27 screen-frame buffer, which remains in memory rather than becoming a rolling recording.

Search credentials are stored in the device-only Keychain. They are never stored in Library JSON. The ignored local `.env` file is a development bootstrap only and is not part of the app bundle. Provider settings inside the app are status-only; users cannot paste, read, or replace a service key.

The capture and garment-detection pipeline has no remote inference call. The separate Try On workspace uploads the chosen person photo and selected product images to YouCam, polls the generated task, and downloads the result. Users see this disclosure next to the action.

## User-controlled input

- Camera access uses Apple’s camera permission.
- Photo import uses Apple’s system picker.
- Clipboard is read only after the user taps Paste image.
- The Share extension runs only after the user chooses Stylezam.
- iOS 27 screen capture begins only after Apple’s system picker grants a filter.
- While that authorized iOS 27 stream is active, two agreeing on-device garment observations can automatically save one source frame and its local crops. Repeated frames are perceptually suppressed.
- Protected content can appear blank; Stylezam does not bypass platform protection.
- iOS owns screen-capture indicators and privacy UI.

The app does not analyze every camera or screen frame. Both live paths have independent default-on automatic-capture controls, are throttled, and pause automatic ML work under serious thermal pressure. Camera inference backs off on an unchanged empty view and stops repeating after an unchanged view is saved; it resumes immediately when the view changes. Live Screen runs a bounded global detector on newly sampled content, uses low-resolution hashes to decide when a deeper paused-page scan is useful, and stops ML work while a captured or known-empty page remains unchanged. Those hashes stay on device and are never persisted. Developer Debug can optionally retain only the latest authorized frame and detections in memory until the stream restarts or the toggle is disabled. Only an automatic capture or manual shutter result is persisted with its crops.

## Network boundary

Detection, segmentation, cropping, and Library capture remain local. Network activity begins only after the user taps Find similar products, asks the image-aware assistant, opens a merchant link, or loads a product thumbnail.

- Fireworks receives the selected garment crop, the bounded recent conversation, and the new prompt for Qwen vision.
- Serper receives generated or user-refined text, not the photo.
- Lykdat receives the selected crop when chosen as the direct image provider.
- Google Cloud Vision receives the selected crop only when Web Detection is chosen. Stylezam requests no label, text, face, logo, or other Vision feature in that call.
- SearchAPI.io and SerpApi receive only an explicitly configured public image URL.
- Bright Data receives the configured public image URL and zone when selected.

Stylezam never uploads a private crop to an anonymous image host to satisfy a Google Lens URL requirement.

Photo try-on requires network access. The user must consent immediately before submission. YouCam documents a file-retention period of up to 30 days, while generated result links expire sooner; the app discloses this in the Try On workspace. Stylezam requests immediate deletion after downloading each finished task, but the documented 30-day automatic-retention boundary remains the fallback if that request fails. A prototype YouCam token can be stored in the device Keychain. Before release, replace direct bearer authentication with a scoped server-side proxy and align remote deletion behavior with the active YouCam agreement.

## Deletion

Users can clear one garment conversation, delete individual scans, completed product searches, saved products, and previews, or clear the Library. A scan deletion removes its source image, associated crop files, chat history, and associated search history. Clearing Library removes captures, crops, conversations, searches, saved products, and appearance previews. The usage ledger is intentionally separate because clearing local history does not restore provider credits. Stopping live screen capture clears its in-memory frame buffer.

## Release checklist

Before public App Store distribution:

- publish a user-facing privacy policy and support URL;
- confirm Privacy Nutrition Label answers against the final feature set;
- review whether people, visible logos, or screen content create additional regional obligations;
- verify deletion behavior on a signed physical-device build;
- conduct legal review of the bundled model and dataset notices.
- move provider credentials behind a production server-side broker before distributing the app to untrusted users;

This is an engineering description, not legal advice.
