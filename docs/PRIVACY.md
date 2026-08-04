# Privacy and data handling

This document describes the implemented capture/understanding release. Product retrieval and virtual try-on are disabled, so their providers receive nothing.

Each executable bundle includes an Apple `PrivacyInfo.xcprivacy` manifest for the required-reason APIs it actually uses. The manifests declare no tracking domains and no tracking. App Store privacy-label answers still need a final account-specific review before distribution; the manifests do not replace that submission step.

## What stays on the iPhone

- The downloadable Core ML garment model and its compiled representation.
- Live preview inference, boxes, masks, quality guidance, and duplicate fingerprints.
- Original saved looks and individual crop files in the Stylezam Library.
- The backend service token in Keychain-backed settings.
- The recent iOS 27 screen-frame buffer, which remains in memory and is not written as a rolling recording.

The app does not upload every camera frame. A still is processed after the shutter, and Live submits only an accepted automatic or manual capture.

## What is sent

After on-device segmentation, Stylezam sends only the candidate garment crops required for labeling, plus their generated item IDs, local class labels, confidence values, and normalized boxes. The full original look is not part of the garment-label request.

The request goes to the user-configured Stylezam HTTPS service using a bearer token. The service checks decoded dimensions, applies EXIF orientation, strips embedded metadata, and preserves segmented alpha masks as PNG (ordinary opaque images are re-encoded as JPEG). It then sends the crop batch as Base64 image inputs to Qwen3.7 Plus through Fireworks.

Qwen3.7 Plus is a closed-weight model hosted directly by Fireworks. Fireworks’s launch material describes its governance and data-handling commitments, while the general zero-retention documentation is specifically worded for open-model inference. Confirm the current Qwen3.7 Plus and account terms before release rather than assuming the open-model wording applies unchanged. Fireworks can retain service metadata such as token counts: [Qwen3.7 Plus launch](https://fireworks.ai/blog/qwen-3p7-plus), [Fireworks data handling](https://docs.fireworks.ai/guides/security_compliance/data_handling).

## Temporary backend storage

Normalized crop files exist only for the duration of the label call. The route deletes them in a `finally` block on success, provider error, quota error, or cancellation. The server persists aggregate provider-call counts in SQLite so it can enforce the UTC-month limit. It does not persist Qwen prompts or label responses as garment-analysis jobs.

The model files are immutable and are served only through bearer-authenticated endpoints. Their hashes and provenance are public facts in the manifest, but the deployment does not expose an unauthenticated static model directory.

## Camera and screen consent

- Camera access uses Apple’s camera permission.
- Photo import uses Apple’s picker.
- Clipboard is read only after an explicit paste action.
- The Share extension runs only after the user chooses Stylezam.
- iOS 27 screen capture begins only after Apple’s system content-sharing picker grants a filter.
- A screen frame is submitted only after the user invokes the Stylezam capture control or accepts an in-app capture.
- Protected/DRM content can be blank; Stylezam must not attempt to bypass that behavior.
- iOS owns screen-capture indicators and privacy UI.

## User controls

The Library can delete individual scans or clear local scans. Developer Debug can remove the downloaded model pack, change the server, replace the service token, change the item limit, and disable Live automatic capture. Stopping screen capture clears the in-memory frame buffer.

## Production checklist

Before any public App Store distribution:

- publish a user-facing privacy policy and support URL;
- complete App Store privacy disclosures for photos, user content, diagnostics, and the Fireworks data path actually enabled;
- confirm Fireworks account logging remains opt-out/default-zero-retention as expected;
- replace the shared test bearer token with per-user/session authentication;
- add server-side retention monitoring and a deletion audit;
- review whether captured people, visible logos, or screen content creates additional regional privacy obligations;
- conduct legal review of the model/dataset notices and provider terms.

This is an engineering description, not legal advice.
