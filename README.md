# Stylezam

Stylezam is a native iPhone product-discovery app for fashion: capture an item, retrieve source-backed product matches, compare observed offers, save the result, and optionally send a real person photo through YouCam AI Clothes v3 for virtual try-on.

This repository contains a functional first version, not a simulated demo:

- Native SwiftUI app using iOS Liquid Glass controls and the approved cobalt/black/white editorial system.
- Camera, Photos, clipboard, text, Share extension, Screenshot Shortcut, Control Center, and Action Button entry points.
- A tappable multi-item Look Stack that submits a real region-focused follow-up search.
- An iOS 27 ScreenCaptureKit path that uses Apple’s full-display picker when compiled with Xcode 27.
- Live Activities and Dynamic Island search progress.
- FastAPI backend with persistent SQLite jobs and sanitized local media.
- Real adapters for SerpApi Shopping/Lens, eBay Browse text/image search, Ollama vision, optional Grounding DINO + SAM2 + CLIP, and YouCam AI Clothes v3.
- Source-evidence labels and direct merchant URLs; no generated listings or affiliate redirects.
- Backend-enforced calendar-month provider caps and deletion endpoints.

## Quick start

```bash
./scripts/bootstrap_backend.sh
cp backend/.env.example backend/.env
./scripts/run_backend.sh
```

In another terminal:

```bash
./scripts/generate_project.sh
open Stylezam.xcodeproj
```

The default app URL is `http://127.0.0.1:8000`, which works in iOS Simulator. A physical iPhone needs an HTTPS deployment/tunnel or a backend address reachable from the phone.

Without provider credentials the service still starts, reports its capabilities, accepts jobs, and fails those jobs with a truthful configuration error. It never fills the UI with sample products.

For a public backend, deploy the included Docker service and persistent disk with `render.yaml`. Set `STYLEZAM_PUBLIC_BASE_URL` to the service's HTTPS origin, set a strong `STYLEZAM_API_TOKEN`, and enter the same token in the iPhone Settings screen. The API token is optional for local development and stored in the iPhone Keychain when present.

## Configure a useful first stack

The recommended initial search stack is:

1. SerpApi for fixed-monthly Shopping and Google Lens retrieval.
2. eBay Browse as a second source for text and Base64 image search.
3. Ollama `gemma3:4b` for local, factual image understanding.
4. YouCam AI Clothes v3 only for user-initiated try-on.

Copy `backend/.env.example` to `backend/.env`, add only the providers you want, and keep the local monthly caps at or below your account budgets. See [Provider limits](docs/PROVIDERS.md) and [Setup](docs/SETUP.md).

## Project map

- `App/` — iPhone app, features, networking, and design system.
- `Extensions/Widgets/` — Control Widget and Live Activity/Dynamic Island UI.
- `Extensions/Share/` — image/text Share extension.
- `Shared/` — app-group keys, App Intent, and Activity attributes.
- `backend/` — FastAPI service, providers, ranking, persistence, and tests.
- `render.yaml` + `backend/Dockerfile` — a single-instance HTTPS deployment with persistent SQLite/media storage.
- `design-concepts/stylezam-ios-v2-liquid-glass/` — approved screen references.
- `docs/` — architecture, UI direction, provider, privacy, setup, and iOS 27 notes.
- `project.yml` — XcodeGen source of truth. Regenerate after target/file changes.

## Verification

```bash
./scripts/check.sh
```

The backend API also exposes interactive OpenAPI documentation at `http://127.0.0.1:8000/docs` while it is running. See the research-backed [UI direction](docs/UI_DIRECTION.md) for the implemented visual hierarchy.

## Before TestFlight

Replace the placeholder bundle IDs and app-group ID, choose your Apple development team, provision the App Group and `screen-capture` background mode, use a production HTTPS backend, configure provider privacy disclosures, and validate the iOS 27 path with Xcode 27 on a physical iPhone. The exact checklist is in [Setup](docs/SETUP.md).
