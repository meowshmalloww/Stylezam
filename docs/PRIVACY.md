# Privacy and data handling

This document describes the local-vision, developer product-search, and optional photo try-on build. Detected crops can enter the local wardrobe and Try On rail automatically in the off state, but YouCam receives data only when the user explicitly selects pieces, consents, and creates a try-on or motion preview.

Each executable bundle includes an Apple `PrivacyInfo.xcprivacy` manifest for the required-reason APIs it uses. The manifests declare no tracking and no tracking domains. App Store privacy answers still require final account-specific review.

## Account identity

The main app requires Google Sign-In. Firebase Authentication processes and retains the authentication account identifier, Google email, display name/photo reference, sign-in tokens, and signed access claims according to the Firebase/Google configuration and policies. Stylezam does not use Firestore for profile storage. The editable Stylezam display name, username, and style note are keyed by Firebase UID in local `UserDefaults` on the iPhone.

Developer access is accepted only from a refreshed Firebase ID token containing `developer: true`. Developer Debug remains hidden from other accounts in Debug and Release builds. The approved-email allowlist and Firebase Admin service-account credential stay in a local administrator environment and are never bundled into the iOS application.

The app links Firebase Analytics Core without IDFA collection capability. Identifier-for-Vendor collection is disabled in `Info.plist`. If Analytics collection is enabled for the Firebase project, aggregate app-use events can be sent to Firebase after startup, so the public privacy policy and App Store privacy answers must match the final console and runtime configuration before release.

## What stays on the iPhone

- The bundled Core ML garment model and compiled representation.
- Live preview inference, boxes, masks, quality guidance, and duplicate fingerprints.
- Accepted camera/import/share images. For Live Screen, Library persists the confirmed garment crop rather than the full display frame or status-area chrome. The one exception is a separate, content-addressed lower-body try-on reference captured during the same transaction, as described below; it is not used as the scan cover.
- Individual garment box crops and structured detection records. Raw
  transparent-mask output is shown only during the local Vision Inspector run.
- Persistent wardrobe items, Try On rail membership and selected/off state, reusable person-photo history, and a separate local full-frame reference candidate for lower-body pieces that need worn-garment context. Identical reference bytes share a content-addressed file.
- Saved Past Try-On stills and item manifests, including any merchant metadata and purchase URLs already attached to those items.
- Per-garment Stylezam AI conversation history and generated follow-up prompts.
- Compact per-garment visual signatures used to recognize an item already in Library. They contain no recoverable source photograph and are deleted with the scan.
- The recent iOS 27 screen-frame buffer and latest Inspector frame, which remain in memory rather than becoming a rolling recording.
- Spoken Stylezam AI audio. The app requires on-device speech recognition support, discards the audio session after transcription, and sends only the editable question text when the user submits it.

Search credentials are stored in the device-only Keychain. They are never stored in Library JSON. The ignored local `.env` file is a development bootstrap only and is not part of the app bundle. Provider settings inside the app are status-only; users cannot paste, read, or replace a service key.

The capture and garment-detection pipeline has no remote inference call. Accepted garment crops are promoted to the persistent rail locally with selection off. For detected lower-body pieces, a full source-frame copy is retained locally as a best-effort candidate for YouCam's worn-garment requirement while the crop remains the visible thumbnail. Stylezam cannot validate locally that the frame visibly shows the garment worn by one clear person. The rail reports ready/missing state and lets the user add or replace that reference. Identical reference frames are content-deduplicated. The separate Try On workspace uploads the chosen person photo and only the explicitly selected references compatible with that photo context to YouCam after upload consent, polls each sequential category task, and downloads the result. Selected incompatible pieces stay parked locally. Next to consent, the app explains that a lower-body upload uses the full reference frame rather than the displayed crop and that the frame can contain people, surroundings, or page content. **View as video** separately uploads the completed still for an image-to-video task.

## User-controlled input

- Camera access uses Apple’s camera permission.
- Photo import uses Apple’s system picker.
- Clipboard is read only after the user taps Paste image.
- The Share extension runs only after the user chooses Stylezam.
- iOS 27 screen capture begins only after Apple’s system picker grants a filter.
- While that authorized iOS 27 stream is active, two agreeing on-device garment observations can automatically save confirmed local crops. Repeated frames and garments already in Library are perceptually suppressed.
- Protected content can appear blank; Stylezam does not bypass platform protection.
- iOS owns screen-capture indicators and privacy UI.

The app does not analyze every camera or screen frame. Both live paths have independent default-on automatic-capture controls, are throttled, and pause automatic ML work under serious thermal pressure. Camera inference backs off on an unchanged empty view and stops repeating after an unchanged view is saved; it resumes immediately when the view changes. Live Screen runs a bounded global detector on newly sampled content, uses low-resolution page hashes to decide when a deeper paused-page scan is useful, and stops ML work while a captured or known-empty page remains unchanged. Those temporary page hashes are not persisted. Compact garment signatures do persist with accepted crops so front/rear Live camera and Live Screen share the same repeat memory across launches. Developer Debug always retains only the latest authorized frame and detections in memory while the stream is active. Only an accepted automatic capture or manual shutter result is persisted with its crops.

## Network boundary

Detection, segmentation, cropping, Library capture, automatic wardrobe/rail promotion, rail toggles, person-photo reuse, and speech audio remain local. Detection never starts a product search, downloads merchant imagery, or calls YouCam. Network activity begins only after the user explicitly starts product search, submits an AI question, opens a merchant link, loads a remote product thumbnail, opens Try On with a configured key (a credential-only feature-cost check), creates a consented try-on, or requests a motion preview. The connection check uploads no user image.

- Fireworks receives the selected garment crop, bounded recent conversation, submitted text, and no more than two additional relevant Library crops selected by local metadata retrieval.
- Serper, SearchAPI.io, SerpApi, or Bright Data receives generated or user-refined text when chosen by the rotating keyword route, not the photo.
- Lykdat receives the selected crop when chosen as the direct image provider.
- Google Cloud Vision receives the selected crop only when Web Detection is chosen. Stylezam requests no label, text, face, logo, or other Vision feature in that call.
- SearchAPI.io and SerpApi receive an explicitly configured public image URL only for their Lens routes.
- Bright Data receives the configured public image URL and zone only for Lens; its text-shopping route receives the query instead.

Stylezam never uploads a private crop to an anonymous image host to satisfy a Google Lens URL requirement.

Photo try-on requires network access. The user must consent immediately before submission. Multi-item looks upload the evolving person image and one reference per sequential category task; this is not a single multi-garment request. Enabled finishing operations upload the evolving result to YouCam enhancement, lighting, background-removal, or background-replacement tasks. The motion option uploads the completed still and requests a five-second 480p, 720p, or 1080p YouCam image-to-video v2 result. YouCam documents a file-retention period of up to 30 days, while generated result links expire sooner; the app discloses this in the Try On workspace. Stylezam requests immediate deletion after downloading each finished task, but the documented 30-day automatic-retention boundary remains the fallback if that request fails. A prototype YouCam token can be stored in the device Keychain. Before release, replace direct bearer authentication with a scoped server-side proxy and align remote deletion behavior with the active YouCam agreement.

## Deletion

Users can clear one garment conversation; individually or multi-select delete scans, completed product searches, saved products, and appearance previews; delete individual wardrobe items, person photos, and Past Try-Ons; remove an item from the rail without deleting it from the wardrobe; or clear the Library. A scan deletion removes its source image, associated crop files and visual signatures, chat history, and associated search history; any lower-body reference already copied into the wardrobe remains with that reusable wardrobe item. Deleting a wardrobe item removes its current rail entry and display crop; its content-addressed try-on reference is removed when no other wardrobe item uses the same bytes. Clearing Library removes captures, crops, signatures, conversations, searches, saved products, wardrobe/rail state and all remaining reference files, reusable person photos, Past Try-On stills and manifests, and appearance previews. The usage ledger is intentionally separate because clearing local history does not restore provider credits. Stopping live screen capture clears its in-memory frame buffer.

## Release checklist

Before public App Store distribution:

- publish a user-facing privacy policy and support URL;
- confirm Privacy Nutrition Label answers against the final feature set;
- review whether people, visible logos, or screen content create additional regional obligations;
- verify deletion behavior on a signed physical-device build;
- conduct legal review of the bundled model and dataset notices.
- move provider credentials behind a production server-side broker before distributing the app to untrusted users;

This is an engineering description, not legal advice.
