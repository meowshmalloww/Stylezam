# UI direction

Research checked on 2026-08-03. The current visual direction stays in place; this release adds functional camera and model states without turning the app into a scanning gimmick.

## Principles

- Editorial fashion content on white, with cobalt used sparingly for identity and primary state.
- Native San Francisco typography and semantic system symbols.
- Liquid Glass for navigation and compact action chrome, not as a decorative card texture.
- Real imagery is the visual focus; empty states never impersonate results.
- Motion is short, interruptible, and tied to user action or real state.
- Reduce Motion replaces the cold-launch reveal with a brief fade and removes nonessential transitions.

Apple’s guidance treats Liquid Glass as a control/navigation material that remains distinct from content, and recommends restraint with color: [materials](https://developer.apple.com/design/human-interface-guidelines/materials), [color](https://developer.apple.com/design/human-interface-guidelines/color), [layout](https://developer.apple.com/design/human-interface-guidelines/layout).

## Implemented pages

### Launch

The exact selected app mark resolves into the Stylezam wordmark, using the same cobalt/white palette as the icon. It has no percentage, fake loading bar, traced substitute logo, or endlessly looping shape.

### Home

Home is a calm overview with a compact identity header, a restrained editorial introduction, direct entry points, recent scans, and saved pieces when they exist. It is not a camera viewfinder and does not imitate Shazam’s circle.

### Capture

The center tab action opens a custom full-screen camera. Photo/Live modes, flash, automatic Live toggle, shutter, front/rear switch, garment outlines, and one-line guidance are reachable without Apple’s legacy image-picker camera chrome. Controls use dark translucent media chrome so the scene stays legible; no decorative scan waves or random circles are added.

### Search

Search is the future product-retrieval workspace. Today it can accept an image and route it through the real capture/understanding pipeline into Library. Text product retrieval remains visibly unavailable until implemented; the page must not show fake listings, prices, or progress.

### Library

Library groups recent scans and their detected pieces as media, with meaningful empty states. Relative age uses minutes, days, weeks, and months—never second-by-second counters or year labels. A scan reveals its source look, analysis state, crops, and visible labels.

### Settings

Consumer-facing rows cover Capture & Controls, Notifications, Privacy, model setup, and help. Backend address, bearer token, server capability state, item-limit slider, automatic Live behavior, and model removal live in Developer Debug. Provider/model selection stays backend-only; Qwen3.7 Plus, OpenAI, eBay, SerpApi, YouCam, local model servers, and GPU switches are not presented as consumer choices.

## Accessibility and performance

- Semantic buttons and accessibility labels cover camera controls.
- Dynamic Type is allowed to wrap instead of shrinking important copy into illegibility.
- Information is not encoded by color alone.
- Preview inference is throttled and never runs continuously while a capture analysis is active.
- Core ML is cached after its first load.
- Candidate crops are created only for the accepted capture, not every preview frame.
- Idle Home, Search, Library, and Settings pages perform no continuous animation.
