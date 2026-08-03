# Privacy and data handling

Stylezam is designed around explicit capture actions and minimum provider disclosure. This document describes the repository defaults; a production operator still needs a public privacy policy and App Store privacy labels matching its deployment.

## What stays on the iPhone

- Bookmarked product records.
- Capture history and normalized capture copies.
- Backend URL and notification preference.
- Up to 15 seconds of throttled iOS 27 live-screen frames, held in memory only and cleared when capture stops.
- A completed appearance-preview file in the temporary directory until the system clears it or the user replaces it; the user can explicitly export it to Photos or another app.

The local library uses the App Group container so the app can import Share-extension attachments. A pending shared file is deleted immediately after the main app consumes it.

## What goes to the Stylezam backend

- Search text the user submits.
- The selected/captured image for an image search.
- A person image only after the user taps Generate try-on.
- The chosen product-image URL and garment category for try-on.

Uploads are bounded at 10 MB, decoded as images, EXIF-transposed, converted to RGB JPEG, and written under random names. This re-encoding removes normal embedded metadata, including GPS EXIF metadata.

## What can go to configured providers

- SerpApi Shopping receives the retrieval text. Lens receives a temporary/public Stylezam image URL and an optional text refinement.
- eBay Browse receives the retrieval text and/or a Base64 copy of the search image.
- Ollama receives the image locally at the configured Ollama host; keep that URL on a trusted network.
- Grounding DINO, SAM2, and CLIP run in the backend process and make no inference API request, although model weights are downloaded from their configured repositories.
- YouCam receives the person image plus a merchant product-image URL for an explicit virtual try-on job. Its current API terms say user submissions are retained for one day and AI-generated content for 30 days before automatic deletion. The published Clothes v3 operations do not include an early-delete endpoint.

Do not enable a provider until its terms, data-processing behavior, and user disclosures fit the production product.

## Retention and deletion

The development backend retains original search uploads so jobs survive restarts. Temporary selected/segmentation crops are deleted after each pipeline run. For try-on, the backend person photo is deleted after a successful or failed processing run; the copied result remains only until the iPhone downloads it and sends the delete request.

- Deleting a capture locally also attempts `DELETE /v1/searches/{id}`.
- Clear captures and bookmarks deletes the local library and requests deletion for its known backend searches.
- `DELETE /v1/try-ons/{id}` removes the backend person image and locally copied result.
- The iPhone automatically calls the try-on delete endpoint after it has atomically saved the completed preview as a local temporary file.

Client-requested deletion is best-effort when the phone is offline. Provider-side YouCam deletion follows its published automatic retention because Clothes v3 currently exposes only file upload, task create, and task status operations. A production account system should still add authenticated server-side “delete all my data” and retention jobs before public launch.

## Tracking and commerce

The app contains no ad SDK or affiliate redirect system. Ranking removes common tracking query parameters before deduplication, while the user-visible merchant action opens the provider’s original product URL. External merchant pages may conduct their own tracking under their policies.

## Screen capture

Apple’s picker is mandatory for iOS 27 full-display capture. Stylezam does not start it silently. Protected content may be blank. Only an explicit Capture a Look action submits the latest authorized frame to search.

## Security boundaries

- Provider keys belong only in backend environment variables.
- Production transport should be HTTPS.
- Public media ingress for Lens makes a randomized media URL fetchable; protect the deployment and delete media when no longer needed.
- The included backend is single-operator infrastructure, not a complete public multi-tenant identity system.
