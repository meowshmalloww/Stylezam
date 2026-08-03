# UI direction

Research checked on 2026-08-03. This is the implementation rationale for the first native iPhone version, not a mood-board-only deliverable.

## Direction

Stylezam uses an editorial fashion layer for content and an iOS-native Liquid Glass layer for actions. The visual system is intentionally narrow:

- Cobalt is a small brand accent; content uses black, white, and semantic system colors.
- San Francisco system type carries the entire hierarchy, with restrained tracking only for small editorial labels.
- Large real capture/product imagery with restrained labels.
- Liquid Glass only on navigation, floating composers, and media action bars—not in the content layer.
- Two product columns on iPhone, preserving useful image scale and readable names.
- Empty states use native `ContentUnavailableView` and direct copy; they never impersonate products, merchants, or search results.
- Idle pages perform no continuous animation. Motion is short, native, and tied to touch, navigation, or real job-state changes.

## Research translated into UI decisions

Apple describes Liquid Glass as a material for controls and navigation that lets the content layer remain visually distinct. Apple also advises applying color to glass sparingly. That is why cobalt marks the primary action and active state while most glass remains neutral: [Apple materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Apple color](https://developer.apple.com/design/human-interface-guidelines/color), [Apple layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Apple toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).

The commerce hierarchy takes cues from current editorial fashion apps rather than generic dashboard cards:

- SSENSE emphasizes search/filtering and a restrained product grid. Its current App Store feedback also explicitly favors the more legible two-column presentation over a denser grid: [SSENSE on the App Store](https://apps.apple.com/us/app/ssense-shop-designer-fashion/id1418754101).
- Mytheresa emphasizes curated discovery plus practical search and filtering: [Mytheresa on the App Store](https://apps.apple.com/us/app/mytheresa-shop-luxury-brands/id484615570).
- Vogue’s fashion/runway experience supports the large-image, low-chrome editorial treatment used for Stylezam’s capture and Look Stack: [Vogue on the App Store](https://apps.apple.com/us/app/vogue-fashion-shopping/id289380413).

These are references for hierarchy and restraint, not screens copied into the app.

Capture is a central native tab-bar action rather than Home’s visual identity. This keeps the camera immediately available from anywhere while allowing Home to work as a useful editorial overview instead of imitating a camera app or music-recognition screen.

## Implemented screen system

### Launch

Apple’s static launch color hands off to a brief in-app identity sequence: the selected icon resolves from blur and rotation, the Stylezam name reveals from left to right, and the editorial tagline fades in before Home appears. It runs only during a cold process launch, contains no fake progress indicator, and collapses to a short fade when Reduce Motion is enabled.

### Home

A compact brand header appears once above a restrained editorial banner, direct Photos and Search shortcuts, a horizontal Recent shelf, and saved-piece previews when the user has them. The artwork is static, geometric, and subordinate to the content. Home contains no viewfinder, radial scan button, connection dot, Settings shortcut, provider copy, gradient, or continuously animated decoration.

### Capture

The center Camera item opens Apple’s full-screen photo camera with the physical iPhone’s rear/front switch, shutter, flash, retake, and Use Photo controls. Accepting the photo starts understanding automatically and moves into Search; there is no intermediate import canvas or “Find products” button. Photos, clipboard images, and text remain in Search rather than appearing in the Camera route.

### Search and Look Stack

The landing page is one universal composer: product text plus an optional image from Photos, Camera, or Paste. The image input is a dedicated vector add-image tile rather than a text-heavy “Reference” control. It contains no “describe an item” instruction and no duplicate photo-search card. Search progress uses the native determinate linear indicator and real backend phases, without gradient fill, phase dots, or glass content panels. The toolbar uses the system compose action for a new search instead of a floating plus. When vision returns multiple boxes, the original capture becomes a tappable Look Stack. Selecting a box submits another real search using that normalized region. Results use a two-column grid with explicit evidence tiers.

### Product evidence

The product page separates upstream identity evidence from visual similarity. “Exact,” “likely,” “similar,” and “inspired” remain evidence labels, never guarantees. Direct merchant URLs and observed offers remain visible.

### Appearance preview

Try-on is a full-screen visual stage with glass controls. The result is called an appearance preview and explicitly does not predict size or fit. A completed preview is downloaded to the iPhone for share/save before Stylezam requests deletion of its backend copy.

### Archive and Setup

Library has three explicit collections—Recent, Saved, and Try-ons—presented as a native category bar and two-column media grids. Relative dates use minutes, days, weeks, and months only, avoiding noisy second-level updates and year labels. It stays empty until the user performs real actions, and completed try-ons are copied into durable local storage automatically.

Consumer Settings is a native grouped list linking to Capture & Controls, Notifications, and Privacy. Screenshot Shortcut, Control Center/Action Button, Share, and consent-based iOS 27 live screen have their own tutorial page. Backend address, service token, OpenAI/Fireworks/Qwen state, local DINO/SAM2/CLIP state, and optional YouCam state live only in Developer Debug. Retrieval-provider infrastructure is not presented as an iPhone preference.

## Accessibility and platform behavior

- Controls use semantic SwiftUI buttons, labels, headings, and system symbols.
- Text content supports Dynamic Type; editorial titles can wrap vertically rather than scale to illegibility.
- Match meaning is written in text and is never conveyed by color alone.
- System permission/picker UI remains system-owned.
- Tab bar and glass behavior use native iOS 26 APIs, including scroll minimization.
