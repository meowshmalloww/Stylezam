# Setup and device checklist

## 1. Backend

From the repository root:

```bash
./scripts/bootstrap_backend.sh
cp backend/.env.example backend/.env
```

Edit `backend/.env`. The API can start without credentials, but at least SerpApi or eBay must be configured to return product results. Keep every monthly cap at or below the budget you intend to allow.

Run it:

```bash
./scripts/run_backend.sh
```

Verify:

```bash
curl http://127.0.0.1:8000/v1/health
curl http://127.0.0.1:8000/v1/capabilities
```

If `STYLEZAM_API_TOKEN` is set, include `Authorization: Bearer <token>` for every `/v1` endpoint except `/v1/health`. Enter the same token in Stylezam Settings; the app stores it in the iPhone Keychain.

Optional local vision:

```bash
.venv/bin/pip install -e 'backend[vision]'
ollama pull gemma3:4b
```

Then set `STYLEZAM_OLLAMA_ENABLED=true` and/or `STYLEZAM_LOCAL_VISION_ENABLED=true`. The model weights are downloaded by their respective runtimes and can require several gigabytes.

## 2. Generate the Xcode project

```bash
./scripts/generate_project.sh
open Stylezam.xcodeproj
```

`project.yml` is the project source of truth. Do not make structural target changes only in the generated `.xcodeproj`, because regeneration will replace them.

## 3. Replace signing identifiers

The repository uses placeholders:

- App: `com.stylezam.app`
- Widget extension: `com.stylezam.app.widgets`
- Share extension: `com.stylezam.app.share`
- App Group: `group.com.stylezam.shared`

Choose unique identifiers in `project.yml`, then replace the app-group ID in:

- `Shared/AppGroup.swift`
- `App/Stylezam.entitlements`
- `Extensions/Widgets/StylezamWidgets.entitlements`
- `Extensions/Share/StylezamShare.entitlements`

Regenerate the project, select your Apple development team for all three targets, and enable the matching App Group in Certificates, Identifiers & Profiles.

## Production backend deployment

The repository includes `backend/Dockerfile` and a Render Blueprint at `render.yaml`. The Blueprint attaches `/data` as a persistent disk because SQLite jobs and sanitized media must survive restarts. Create the Blueprint from the repository, then provide the prompted secrets:

- `STYLEZAM_API_TOKEN` — a long random value shared only with your iPhone app.
- `STYLEZAM_PUBLIC_BASE_URL` — the final `https://...` origin, with no trailing slash.
- At least one product retrieval credential: SerpApi, eBay, or both.
- `STYLEZAM_YOUCAM_API_KEY` if virtual try-on should be enabled.

The standard container intentionally leaves Ollama and Grounding DINO/SAM2/CLIP disabled. Those local models require a separate GPU-capable deployment and several large model downloads; enabling their flags on the standard CPU container is not production-safe. Image search still works through eBay image search and/or SerpApi Lens, and the API always accepts, normalizes, stores, and deletes photo uploads independently of local ML.

## 4. Backend address

Simulator can use the default `http://127.0.0.1:8000`. A real phone cannot use the Mac’s loopback address.

For device development, use one of:

- A production/staging HTTPS deployment.
- An HTTPS tunnel to the Mac development server.
- The Mac’s LAN IP if the phone and Mac are on the same trusted network.

Open Stylezam → Setup and replace the service URL, then tap Test. Production should use HTTPS; do not add broad App Transport Security exceptions.

## 5. Screenshot Shortcut, Control Center, Action Button, and Share

After installing a signed build:

1. In Shortcuts, create a Shortcut with `Take Screenshot` followed by `Search Image with Stylezam`. The image parameter connects to the previous action automatically.
2. Open Control Center and add Stylezam’s Capture a Look control.
3. On an Action Button device, choose Controls in the Action Button settings and assign Capture a Look.
4. In another app’s Share sheet, use Edit Actions if Search with Stylezam is not initially visible.

The App Intent and Share extension depend on the App Group being present in all provisioning profiles.

## 6. Live Activity and Dynamic Island

Live Activities are local and do not require APNs. The app starts one after a backend search job is accepted, updates it while polling, and ends it after completion or failure. Test on a Dynamic Island device for compact/minimal presentation and on a non-Island device for Lock Screen presentation.

## 7. iOS 27 live screen

The current Xcode 26 build compiles a truthful unavailable state. To enable live screen capture:

1. Open with Xcode 27 and compile against the iOS 27 SDK.
2. Use a physical iPhone on iOS 27; Simulator is not sufficient for final capture validation.
3. Keep the `screen-capture` background mode and `NSScreenCaptureUsageDescription` privacy string. Apple’s current sample does not document a manually entered screen-recording entitlement key.
4. Open Stylezam → Setup → Choose a screen, then select content in Apple’s picker.
5. From another app, invoke the Stylezam Control Center/Action Button control to search a recent authorized frame.

See [iOS 27 screen capture](IOS27_SCREEN_CAPTURE.md) for behavior and limitations.

## 8. Release checklist

- Deploy the backend over HTTPS behind authentication/rate limiting appropriate to your audience.
- Set exact CORS origins if a web client is added; the iOS app does not need CORS.
- Back up the SQLite database and media directory or replace them with managed persistence/object storage before multi-instance deployment.
- Confirm provider licenses, quotas, and caps.
- Test deletion and account/data-retention behavior.
- Complete App Store privacy labels based on the exact providers enabled in production.
- Add support and privacy-policy URLs to App Store Connect.
- Archive a Release build and run Apple’s validation.
- Test camera, Photos, clipboard permission behavior, Share, Control Center, Action Button, Live Activity, Dynamic Island, product links, and YouCam on physical devices.
