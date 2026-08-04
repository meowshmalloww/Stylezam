# Setup and device checklist

## Current toolchain boundary

The repository builds its iOS 26 feature set with Xcode 26.6 and the iOS 26.5 SDK. Apple’s current requirements say Xcode 27 beta 4 needs macOS Tahoe 26.4 or later and supplies the iOS 27 SDK: [Xcode system requirements](https://developer.apple.com/xcode/system-requirements).

This Mac is currently on macOS 26.2, so the real ScreenCaptureKit-for-iOS branch cannot be compiled here yet. Camera, Photos, Share, App Intents, local Live Activities, Dynamic Island UI, model download, segmentation, crop labeling, and Library behavior remain buildable on iOS 26.

## 1. Verify the backend and model pack

From the repository root:

```bash
./scripts/bootstrap_backend.sh
./scripts/check.sh
```

The verified model pack lives at:

```text
backend/.data/model-packs/garment-rfdetr-seg-small/1.0.1/
```

It is an iPhone Core ML artifact, not a server inference dependency. The production container serves the pack but never loads it into memory.

Local backend execution exists for tests and API development:

```bash
cp backend/.env.example backend/.env
./scripts/run_backend.sh
```

The iPhone app intentionally does not accept this localhost address. A physical phone must use the deployed HTTPS service.

## 2. Create the Daytona CPU sandbox

### Daytona dashboard

Use the versioned public container rather than a generic Ubuntu or `daytona-medium` environment:

```text
ghcr.io/meowshmalloww/stylezam-backend:0.1.0
```

Create one sandbox with:

- name `stylezam-api`;
- Source → Image using the exact version above;
- 2 vCPU, 4 GiB memory, 10 GiB storage, and 0 GPU;
- US region;
- auto-stop `0`, auto-archive `10080`, auto-delete disabled, and Ephemeral off;
- Public HTTP Preview on and Block All Network Access off;
- no labels, registry credentials, snapshot, or volume.

Add these values through Daytona Environment Variables, not a repository `.env` file:

```text
STYLEZAM_API_TOKEN=<a new random password used again in the iPhone app>
STYLEZAM_FIREWORKS_API_KEY=<a private Fireworks key that has never been shared>
STYLEZAM_FIREWORKS_MONTHLY_CAP=100
```

The container already selects production mode, `/data`, the bundled model-pack path, Qwen3.7 Plus, port 8000, and disabled product-search/try-on defaults. The Fireworks account’s separate $50 monetary limit must already be enabled in Fireworks.

### Command-line alternative

Install and authenticate Daytona only when you are ready to deploy. The official CLI install on macOS is:

```bash
brew install daytonaio/cli/daytona
```

Then choose secrets in your shell. Do not commit them:

```bash
openssl rand -hex 32
export STYLEZAM_API_TOKEN="paste-the-random-output-here-and-enter-the-same-value-on-the-phone"
export STYLEZAM_FIREWORKS_API_KEY="your-fireworks-api-key"
export STYLEZAM_FIREWORKS_MONTHLY_CAP=100
./scripts/create_daytona.sh
```

`STYLEZAM_API_TOKEN` is not supplied by Stylezam or Fireworks. It is a private bearer token you create to protect your own deployed API. The Fireworks credential is a different secret and stays on the backend only.

Before adding the Fireworks key to Daytona, set and confirm a small provider-side monthly budget. Fireworks documents that reaching this limit pauses API requests across the account:

```bash
firectl quota update monthly-spend-usd --value 50
firectl quota list
```

The `$50` limit is the chosen account-wide ceiling and affects the entire Fireworks account, not only Stylezam. Keep `STYLEZAM_FIREWORKS_MONTHLY_CAP` as the separate, lower-level call-count guard. See [Fireworks account quotas](https://docs.fireworks.ai/guides/quotas_usage/account-quotas).

The helper requests:

- 2 CPU cores;
- 4096 MB RAM;
- 10 GB disk;
- public sandbox ingress for the iPhone;
- auto-stop disabled and auto-delete disabled;
- no GPU allocation;
- product search and virtual try-on disabled.

Daytona documents `--auto-stop 0` as disabled and exposes the CPU, memory, disk, public, Dockerfile, and environment flags used by the script: [Daytona CLI](https://www.daytona.io/docs/en/tools/cli/). A public preview link is intentionally protected by Stylezam’s own bearer token. The client also sends Daytona’s documented warning-skip header on manifest, file, and API calls: [Daytona preview URLs](https://www.daytona.io/docs/en/preview/).

After creation:

1. Open the sandbox in Daytona.
2. Copy the public HTTPS preview URL for port 8000.
3. Confirm `<url>/v1/health` returns `status: ok`.
4. In Stylezam, open Settings → Developer Debug.
5. Enter that URL and the same `STYLEZAM_API_TOKEN`.
6. Tap the service test.
7. On Wi-Fi, download the garment model when the app offers setup.

To verify the vision stages independently of Library persistence, open Settings → Developer Debug → Vision Inspector. Choose a real photo or reuse the newest Library capture. The inspector runs the same detector and transparent-crop generator used by production capture, then shows boxes, class confidence, normalized geometry, crop dimensions, byte sizes, and local timing. “Send crops for detailed labels” is deliberately separate and calls the same authenticated Qwen3.7 Plus route only when tapped. The copied diagnostic JSON omits image bytes and credentials.

Do not use a signed preview URL for a ten-day test: Daytona currently limits signed preview URLs to 24 hours. Use a public sandbox plus the Stylezam bearer token.

For Daytona billing safety, open Wallet and set automatic top-up Threshold and Target to `0`. Daytona documents that this disables automatic top-up, but it does not document an account spend-limit pause equivalent to Fireworks. Treat the `$200` credit as a wallet balance, watch the per-sandbox spend, and explicitly delete the sandbox at the end of the ten-day test. Stopping alone still reserves billable disk; archiving or deleting stops sandbox billing. See [Daytona billing](https://www.daytona.io/docs/billing).

### What cannot be completed without your accounts

The repository does not contain your Daytona login, Fireworks key, or service token. Therefore an actual sandbox and a real Qwen3.7 Plus response cannot be created by source code alone. The mocked provider test verifies request structure without spending a call.

## 3. Generate and sign the iOS project

```bash
./scripts/generate_project.sh
open Stylezam.xcodeproj
```

`project.yml` is the source of truth for target structure. Set a Development Team for the app, Share extension, and widget extension. Replace the placeholder identifiers if your team cannot claim them:

- App: `com.stylezam.app`
- Widget: `com.stylezam.app.widgets`
- Share: `com.stylezam.app.share`
- Intended App Group: `group.com.stylezam.shared`

The checked-in entitlement files are empty so the main app can remain signable by a free Personal Team. If an eligible team is available, add the App Groups capability to all three targets in Xcode, select the exact identifier in `Shared/AppGroup.swift`, and confirm Xcode writes `com.apple.security.application-groups` into all three entitlement files. Those files survive project regeneration because `project.yml` references them directly.

Apple permits free Personal Team device testing, but says App IDs, devices, and provisioning profiles expire after seven days and must be periodically rebuilt/reinstalled: [Apple membership comparison](https://developer.apple.com/support/compare-memberships/). Advanced capabilities and distribution belong to the paid program, so App Group/extension provisioning may still be the limiting part of a free-signing build. The main app can be device-tested without paying; all extension behavior must be verified against the capabilities Xcode actually grants your Personal Team.

## 4. Physical-device checks

On the connected iPhone, verify:

- rear and front camera switching;
- flash availability on the active camera;
- manual Photo capture;
- Live mode guidance, automatic capture, manual override, and cooldown;
- five-item default and Developer Debug slider;
- model download refuses cellular and succeeds on Wi-Fi;
- checksum failure leaves no active partial pack;
- crop overlays align with portrait and landscape source images;
- scan deletion removes the original and crop files;
- imported Photos and clipboard input;
- Share extension input only if the same App Group successfully provisions on the app and extension;
- Live Activity Lock Screen and Dynamic Island presentations;
- Control Center/Action Button intent, if the App Group provisions;
- backend-unavailable behavior still saves the scan locally.

## 5. The Apple ScreenCaptureKit ZIP

Extracting Apple’s sample ZIP is only the first reference step. It does not install an SDK, add the framework to Stylezam, copy entitlements, or enable the feature on the phone.

To finish iOS 27 screen support later:

1. Update this Mac to macOS 26.4 or later.
2. Install Xcode 27 beta and select it with `xcode-select` or Xcode Settings.
3. Open and run Apple’s sample separately to confirm the phone/SDK combination.
4. Regenerate and open Stylezam with Xcode 27.
5. Compile the existing conditional ScreenCaptureKit adapter against the iOS 27 SDK.
6. Confirm the `screen-capture` background mode and `NSScreenCaptureUsageDescription` are accepted by Xcode.
7. Sign and run on the iOS 27 phone.
8. Use Apple’s content-sharing picker, leave Stylezam, invoke the Control Center capture, and confirm a real recent frame becomes a Library scan.
9. Test stop, denial, interruption, protected-content, memory-pressure, and app-termination behavior.

See [iOS 27 live screen](IOS27_SCREEN_CAPTURE.md). The extracted sample should remain reference code; do not drop the whole sample project into Stylezam.

## 6. Release checks

- Run `./scripts/check.sh`.
- Run the Python dependency vulnerability audit described in `THIRD_PARTY_NOTICES.md`.
- Build the pinned production Dockerfile in Daytona and inspect its final image scan.
- Test the real Fireworks request with non-sensitive clothing photos and a very low monthly cap.
- Rotate test service tokens before sharing the app.
- Confirm no API key is in the Xcode project, Git history, or app bundle.
- Complete privacy disclosures and legal/license review before public distribution.
