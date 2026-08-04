# Privacy and data handling

This document describes the implemented local-vision and optional photo try-on release. Product retrieval remains unavailable. YouCam receives data only when the user explicitly creates a try-on.

Each executable bundle includes an Apple `PrivacyInfo.xcprivacy` manifest for the required-reason APIs it uses. The manifests declare no tracking and no tracking domains. App Store privacy answers still require final account-specific review.

## What stays on the iPhone

- The bundled Core ML garment model and compiled representation.
- Live preview inference, boxes, masks, quality guidance, and duplicate fingerprints.
- Accepted camera/import/share/screen images.
- Individual transparent garment crops and structured detection records.
- The recent iOS 27 screen-frame buffer, which remains in memory rather than becoming a rolling recording.

The capture and garment-detection pipeline has no remote inference call. The separate Try On workspace uploads the chosen person photo and selected product images to YouCam, polls the generated task, and downloads the result. Users see this disclosure next to the action.

## User-controlled input

- Camera access uses Apple’s camera permission.
- Photo import uses Apple’s system picker.
- Clipboard is read only after the user taps Paste image.
- The Share extension runs only after the user chooses Stylezam.
- iOS 27 screen capture begins only after Apple’s system picker grants a filter.
- A screen frame becomes a saved scan only after an in-app or system capture action.
- Protected content can appear blank; Stylezam does not bypass platform protection.
- iOS owns screen-capture indicators and privacy UI.

The app does not analyze every camera frame continuously. Live preview is throttled; only a stable automatic capture or manual shutter result is persisted with its crops.

## Network boundary

Local garment understanding does not require network access. Older Library data from an earlier development build can contain saved product URLs and remote product image URLs; those links are fetched or opened only when the user views the legacy product entry. They are not part of the capture pipeline.

Photo try-on requires network access. The user must consent immediately before submission. YouCam documents a file-retention period of up to 30 days, while generated result links expire sooner; the app discloses this in the Try On workspace. Stylezam requests immediate deletion after downloading each finished task, but the documented 30-day automatic-retention boundary remains the fallback if that request fails. A prototype YouCam token can be stored in the device Keychain. Before release, replace direct bearer authentication with a scoped server-side proxy and align remote deletion behavior with the active YouCam agreement.

## Deletion

Users can delete individual scans or clear the Library. A scan deletion removes its source image and all associated crop files. Clearing Library removes captures, crops, saved legacy products, and legacy appearance previews. Stopping live screen capture clears its in-memory frame buffer.

## Release checklist

Before public App Store distribution:

- publish a user-facing privacy policy and support URL;
- confirm Privacy Nutrition Label answers against the final feature set;
- review whether people, visible logos, or screen content create additional regional obligations;
- verify deletion behavior on a signed physical-device build;
- conduct legal review of the bundled model and dataset notices.

This is an engineering description, not legal advice.
