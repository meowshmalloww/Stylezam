# Architecture

## Current boundary

Stylezam implements local fashion capture, garment instance detection, crop creation, inspection, persistent wardrobe and try-on state, explicitly triggered product retrieval, and optional photo-based virtual try-on backed by YouCam.

## Photo try-on

After an accepted scan is persisted, each accepted garment crop is added to the local wardrobe and persistent Try On rail with selection off. Opening Try On from a piece activates only that piece; additional items require explicit selection. A lower-body item keeps two durable local media roles: the tight crop shown in wardrobe/rail UI and a separate full originating frame retained as a best-effort candidate for YouCam's worn-garment reference. Detection identifies the garment region but cannot validate locally that a photo or web frame visibly shows the garment worn by one clear person. The rail therefore exposes ready/missing state, blocks Create when a selected lower-body reference is missing, and lets the user add or replace the worn photo. Identical reference bytes use one content-addressed file shared by wardrobe metadata records. This capture-side promotion performs no product search, thumbnail load, or YouCam call. If the user later starts a product search and it succeeds, Stylezam best-effort matches the source scan and garment identifiers and updates that same rail record with the merchant product and purchase link. Search success is independent from this optional enrichment.

The Try On workspace keeps a reusable person-photo history from Stylezam's zoom-capable front/rear camera or Photos. The stage pages through prior photos and an add-photo page. Its expandable rail has **Pieces** and **Shop** views: users can select or deselect several pieces, remove rail entries without deleting the underlying wardrobe item, add items from the wardrobe, and open available merchant links. Stylezam infers Outfit, Hand/Wrist, or Face/Neck from the selected pieces and person photo, caches that answer, and preserves the manual correction control. Selected pieces that do not match the active photo context stay parked on the rail instead of being submitted to a likely failing paid task.

After the user explicitly enables upload consent, one Create action sorts the compatible selected rail items into a stable render order and passes them to `YouCamTryOnService.render`. The action discloses the exact number of YouCam tasks it will start. The service runs one category-specific asynchronous task per item and uses each downloaded result as the source photo for the next task. Clothing uses Clothes V4 with an explicit upper-body, lower-body, or full-body category and keeps `change_shoes` false unless shoes are selected; bags, scarves, shoes, and hats use dedicated endpoints; jewelry uses dedicated 2D VTO endpoints. A local broad classifier blocks strong bedding/furniture references, and a post-result scene check rejects implausible full-person or full-scene replacement for a single non-clothes item. Enabled enhancement, lighting, background removal, and background replacement run afterward as explicit additional tasks. Stylezam requests deletion of each finished remote task and associated media, including after local cancellation.

**View as video** uploads the completed still to YouCam image-to-video v2 and requests a five-second output at the selected 480p, 720p, or 1080p resolution. Provider cost is shown as changeable provider pricing rather than a fixed app promise. The replay control remains outside the image focal area. The downloaded video is temporary rather than a saved Library artifact. Saving a still creates a Past Try-On record containing the rendered image, person-photo/context metadata, and a snapshot of every rail item at that moment. The snapshot records the pieces actually applied to that photo plus the toggled-off or context-incompatible rail items, and retains embedded merchant details and purchase URLs even if the live rail later changes.

The workspace verifies basic credential connectivity through YouCam's feature-cost endpoint, exposes the actual upload/task/polling phase, and translates provider errors into retake or product-image guidance. That check does not prove that the account is entitled to every category or image-to-video operation. YouCam clothes also requires a lower-body reference to visibly show the garment being worn by one clear person rather than as a standalone product image. A detected item's separately persisted full source frame is only a candidate for that request and cannot be validated locally; the user-facing rail warns about the rule, allows replacement, and keeps the display crop separate. Identical reference frames remain content-deduplicated. A complete real entitled-key, physical-device smoke test remains outstanding.

The prototype bearer credential is stored in the device Keychain or imported from an ignored `.env` file for a Debug launch. Production distribution requires a server-side credential proxy rather than embedding a shared bearer token in the app.

## Capture data flow

```mermaid
sequenceDiagram
    participant User
    participant Input as Camera / import / share / screen
    participant CoreML as Bundled RF-DETR Core ML
    participant Post as Local post-processing
    participant Library as Local Library

    User->>Input: Choose or accept a frame
    Input->>CoreML: 384 × 384 global prediction
    Input->>CoreML: Bounded square detail tiles for accepted still photos
    CoreML-->>Post: Query boxes, class logits, mask logits per pass
    Post->>Post: Threshold, item-class filter, IoU suppression, cap
    Post->>Post: Materialize readable full-detail box crops
    Post->>Library: Save source image, records, and box-crop JPEGs
    Library-->>User: Show captured look and individual pieces
```

No camera frame or accepted photo is sent during detection. A selected garment crop leaves the device only after the user starts a product search or asks the image-aware assistant.

## Product search data flow

The default private developer route is:

1. persist a logical search reservation before networking;
2. send the selected crop directly to Lykdat Global Search or Google Cloud Vision Web Detection;
3. select the provider result group that best matches the chosen local garment label;
4. normalize, cap, display, and persist the real provider results.

Every accepted detected piece enters the persistent Try On rail locally with selection off. Each piece in Library Recent exposes both explicit routes directly. **Find products & prices** hands the existing scan and garment identifiers to Search and starts one provider request only when no saved search exists. A successful search best-effort enriches the exact source rail item with the first shoppable result; enrichment failure remains nonfatal and does not consume another search. **Try on crop** activates only the chosen already-saved crop without performing a product search. The router selects the next eligible visual provider, records the attempt, advances the cursor, and wraps after the final provider.

Stylezam AI is separate: each garment has a bounded, locally persisted conversation. On-device token embeddings retrieve relevant structured garment metadata across the local Library first. A turn sends the selected crop, recent conversation context, and at most two additional locally available relevant crops to Fireworks Qwen 3.7 Plus. It never enumerates or uploads the complete Library. Spoken input uses Apple's on-device recognition requirement, keeps audio transient, and inserts only editable text into the composer. Qwen returns both the response and relevant follow-up questions. Only when the user explicitly taps **Find similar** or **Find cheaper** does Stylezam ask Qwen for grounded shopping keywords that can coordinate with the retrieved owned pieces, then sends one generated text query—not the private Library—to the next eligible Serper, SearchAPI.io, SerpApi, or Bright Data keyword route. Cheaper-result presentation orders comparable priced results from lower to higher and leaves products without a parsed price afterward.

StoreKit 2 is the source of paid entitlement state on device. The client displays App Store localized prices and verifies transactions before changing its local plan.

The default is one successful product search per garment. Logical reservations and provider counts survive relaunches. Failed requests remain in the diagnostic ledger because providers may still count them, but they do not consume the user's successful-search allowance and can be retried.

Lykdat Global Search and Google Cloud Vision Web Detection accept binary image data. The Google adapter sends one image with exactly one `WEB_DETECTION` feature and reserves one unit in a separately persisted, non-increasable 1,000-unit monthly safety counter before networking. SearchAPI.io, SerpApi, and Bright Data Lens accept public image URLs, so Stylezam refuses to publish a private crop automatically. Their separate keyword routes accept text and do not require an image URL.

## Inputs

The custom AVFoundation camera owns preview, rear/front switching, flash, pinch and preset optical zoom, manual shutter, and Live mode. The Try On camera reuses the same zoom controller. Photos, clipboard images, App Intents, Share input, and an authorized iOS 27 screen frame converge on `AppModel.processCapture`.

The Share and cross-process control paths require the same App Group entitlement across signed targets. A Personal Team can test the main app but may not provision every extension capability.

## Bundled Core ML model

`App/Resources/Models/StylezamGarmentSegmentation.mlpackage` is part of the application resources. Xcode compiles it to `StylezamGarmentSegmentation.mlmodelc` while building the app. `ModelPackManager` resolves the compiled resource and loads the adjacent verified manifest; it has no downloader, network monitor, staging directory, or removable model state.

The model accepts a `1 × 3 × 384 × 384` normalized tensor and produces query boxes, class logits, and masks. Stylezam:

1. scores Fashionpedia item classes 0–26;
2. rejects confidence below 0.35 and very small boxes;
3. suppresses high-IoU duplicate boxes of the same class;
4. keeps the configured maximum, five by default and 12 at most;
5. creates a high-quality JPEG directly from the accepted source image for
   Library. Vision Inspector can separately materialize the raw transparent
   mask cutout for diagnosis.

The model object is cached by `GarmentVisionEngine` and configured with
`MLComputeUnits.cpuOnly`. Device verification found that this model export
returns all-zero class logits through the iOS GPU/Neural Engine path; CPU-only
execution returns the expected boxes and classes. Continuous camera preview
stays single-pass and skips mask-array materialization and crop
creation. Live preview uses a stricter 0.55 confidence threshold, rejects
near-identical competing boxes, and requires the same region and label to agree
across consecutive sampled frames. Once Live consensus is reached, AVFoundation
takes a full-quality still rather than saving the compact preview JPEG. Accepted
Photo and Live images add overlapping square detail passes when the source
resolution, power mode, thermal state, and remaining 9-second budget allow it.
Tile detections are projected into source coordinates, edge-clipped tile
results are rejected, and cross-scale duplicates are suppressed before the
configured item cap is applied.

## Live capture

Live mode samples preview frames rather than processing every camera frame. Candidate confidence, garment area, clipping, luminance, and sharpness contribute to capture guidance. A low-resolution content gate backs an unchanged empty scene off to one inference every 2.4 seconds after two empty results; motion or any candidate immediately returns to the normal fast cadence. A lightweight temporal tracker smooths boxes and only displays a category after two agreeing observations on the same region. Automatic capture requires three stable tracked signatures, a ready frame, and a cooldown. The shutter remains available at all times.

Recent Live and screen box crops use a perceptual dHash guard to suppress obvious repeats. These are deterministic capture heuristics, not biometric or identity recognition and not calibrated accuracy guarantees.

Live Screen samples at a 0.85-second nominal active cadence. Newly sampled
content receives one immediate full-screen tensor instead of waiting for the
entire page or video frame to become motionless. If that quick pass is empty and
the next low-resolution content signature agrees, the engine performs one
detail-aware discovery pass; a found region is confirmed with one focused
tensor. Two agreeing label/box/appearance observations promote the original
device-resolution frame to the accepted still pipeline. The continuous Live
Activity changes symbol and text for scanning, recognition, crop generation,
and save completion. Developer Debug retains only the latest authorized analyzed
frame in memory while the stream runs and renders the model's actual boxes and
crops inside Stylezam; the app never attempts to draw an overlay over another app.

## Local persistence

The Library stores source images, readable garment box-crop JPEGs,
durable full-frame try-on reference candidates for detected lower-body pieces, class/confidence/box records, capture source, per-garment chat history, persistent wardrobe items, current rail membership and selection, reusable person photos, and Past Try-On images and manifests under the app container. Reference blobs are content-addressed, so identical full frames are written once and deleted only after the last wardrobe record stops referring to them. A try-on manifest snapshots the items actually applied plus the parked and toggled-off rail items, records separate display/reference media digests, and embeds available product metadata and purchase links so later rail edits do not rewrite the saved look.
The current raw mask is diagnostic-only because its iOS regions are not reliable
enough for a product-facing cutout. A bounded snapshot keeps the most recent
media. Deleting a scan removes its source and crop files; clearing Library
removes all local media and saved legacy records.

Live screen preview frames remain in a short in-memory rolling buffer, and the
latest authorized analyzed frame remains available to Live Screen Inspector
while that stream runs. Stopping capture clears both in-memory surfaces.

## Item coverage

The emitted item classes cover shirts/blouses, tops, sweaters, cardigans, jackets, vests, pants, shorts, skirts, coats, dresses, jumpsuits, capes, glasses, hats/head coverings, ties, gloves, watches, belts, leg warmers, tights/stockings, socks, shoes, bags/wallets, scarves, and umbrellas.

Part/detail classes such as sleeves, collars, pockets, zippers, and sequins are not emitted as separate Library pieces. Rings, bracelets, necklaces, and earrings require a future benchmarked accessory detector or explicit crop workflow.

## iOS 27 screen path

ScreenCaptureKit code is compiled only when the installed SDK exposes it. Apple’s system content-sharing picker supplies authorization; Stylezam cannot silently begin a display stream or return to the previous app. Complete frames are orientation-corrected, cropped to the application-safe content region, encoded directly from their Core Image buffers, thermally throttled, and buffered in memory. A 480 px, four-region difference hash rejects moving frames before Core ML runs; it samples the central content area and excludes system-status and toolbar bands. After two visually stable samples, one crop-free global-plus-detail discovery prevents tall pages from hiding small or edge-positioned garments; later confirmation frames use one square focus region around the discovered item. Two agreeing garment observations are required before the accepted device-resolution frame enters the normal crop, duplicate, Library, Live Activity, and notification pipeline. Captured and twice-verified empty screens are sampled only every four seconds at nominal thermal state until their content hash changes. Low Power Mode and elevated thermal pressure lengthen the cadence; serious pressure keeps a reduced cooling cadence so status remains observable, while critical pressure pauses automatic work. iOS owns the system privacy indicator, and Stylezam does not draw an imitation recording border over other apps.

## Failure behavior

- Missing or invalid bundled model: capture stops with a clear reinstall/build error; it does not silently switch to fabricated labels.
- No garment above threshold: the source can still be saved with zero pieces.
- Duplicate Live/screen item: no duplicate scan is added.
- Missing provider key/zone: no request is reserved or dispatched; Search names the missing configuration.
- Per-piece or monthly local limit reached: the request stops before networking.
- Dispatched provider failure: the attempt remains visible in Search Diagnostics and is not silently retried.
- Post-search rail enrichment failure: the real search remains saved and usable; the local crop stays on the rail.
- YouCam connection check succeeds but a category or video task is not entitled: the real provider error is shown; connectivity is not presented as an entitlement guarantee.
- iOS 18–26: screen capture reports unavailable; camera, Photos, clipboard, and Share paths continue.
