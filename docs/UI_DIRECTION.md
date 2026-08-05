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

Search accepts a fashion reference image, detects its pieces, and lets the user make a bounded request to a configured real visual-search provider. It shows provider results and current observed prices without fake listings, invented confidence, or simulated progress.

### Try On

Try On opens as a focused full-screen workflow from a real product result rather than taking over a permanent tab. It uses a full-height person-photo stage and a horizontal item rail suited to iPhone. Users can add product photos or detected Library pieces, toggle inclusion, remove items, create a sequential YouCam preview, and save the result. It never represents the generated image as proof of physical fit.

### Library

Library groups recent scans and their detected pieces as media, with meaningful empty states. Relative age uses minutes, days, weeks, and months—never second-by-second counters or year labels. A scan reveals its source look, analysis state, crops, and visible labels.

### Settings

Consumer-facing rows cover Capture & Controls, Notifications, and Privacy. Developer Debug contains the bundled-model state, Vision Inspector, item-limit slider, and automatic Live behavior. There is no connection form, token field, model download/removal control, or provider selector.

## Accessibility and performance

- Semantic buttons and accessibility labels cover camera controls.
- Dynamic Type is allowed to wrap instead of shrinking important copy into illegibility.
- Information is not encoded by color alone.
- Preview inference is throttled and never runs continuously while a capture analysis is active.
- Core ML is cached after its first load.
- Candidate crops are created only for the accepted capture, not every preview frame.
- Idle Home, Search, Library, and Settings pages perform no continuous animation.
