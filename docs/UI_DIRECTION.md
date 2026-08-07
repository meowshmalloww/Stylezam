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

The center tab action opens a custom full-screen camera. Photo/Live modes, flash, automatic Live toggle, shutter, front/rear switch, pinch and preset optical zoom, garment outlines, and one-line guidance are reachable without Apple’s legacy image-picker camera chrome. Controls use dark translucent media chrome so the scene stays legible; no decorative scan waves or random circles are added.

### Search

Search accepts a fashion reference image, detects its pieces, and lets the user make a bounded request to a configured real visual-search provider. It shows provider results and current observed prices without fake listings, invented confidence, or simulated progress.

### Try On

Try On opens as a focused full-screen workflow rather than taking over a permanent tab. The person-photo stage is swipeable: prior photos are reusable, and the final page adds a new zoom-capable camera or Photos image. An expandable **Pieces / Shop** rail shows the persistent current set. Detected crops arrive off; opening Try On from one piece activates only that piece. Users can deliberately toggle several pieces, remove a rail entry, add a product photo or wardrobe item, and open purchase links for selected, parked, and toggled-off products.

The primary Create action requires explicit upload consent, shows its task count, and composes the compatible selected look through sequential category-specific YouCam tasks. Photo context and presentation are inferred first, while visible manual controls remain available for corrections. Incompatible selected pieces remain visibly parked for another photo type and are not uploaded. Optional enhancement, lighting, background removal, and background replacement are disclosed before submission. After a still is ready, **View as video** supports five-second 480p, 720p, or 1080p output and a non-obstructing replay control. Save creates a Past Try-On entry whose applied/parked item manifest and purchase links remain tied to that saved look. Generated media is never represented as proof of physical fit.

### Library

Library groups recent scans, wardrobe pieces, product matches, and Past Try-Ons as media, with meaningful empty states. Relative age uses minutes, days, weeks, and months—never second-by-second counters or year labels. A scan reveals its source look, analysis state, crops, and visible labels. Wardrobe detail can preview a piece, add or remove it from the persistent rail, open its merchant link, or delete it. Past Try-On detail separates the immutable **Wearing** and **On the rail** manifests and preserves their available purchase links.

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
