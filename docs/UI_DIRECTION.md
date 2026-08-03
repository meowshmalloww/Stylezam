# UI direction

Research checked on 2026-08-03. This is the implementation rationale for the first native iPhone version, not a mood-board-only deliverable.

## Direction

Stylezam uses an editorial fashion layer for content and an iOS-native Liquid Glass layer for actions. The visual system is intentionally narrow:

- Cobalt, black, white, and semantic system colors only.
- Editorial serif display type for short page statements; normal system type for controls, details, and evidence.
- Large real capture/product imagery with restrained labels.
- Liquid Glass on navigation, capture controls, filters, progress, and action bars—not as a translucent surface behind every piece of content.
- Two product columns on iPhone, preserving useful image scale and readable names.
- Empty states use the Stylezam brand mark and direct copy; they never impersonate products, merchants, or search results.

## Research translated into UI decisions

Apple describes Liquid Glass as a material for controls and navigation that lets the content layer remain visually distinct. Apple also advises applying color to glass sparingly. That is why cobalt marks the primary action and active state while most glass remains neutral: [Apple materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Apple color](https://developer.apple.com/design/human-interface-guidelines/color), [Apple layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Apple toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).

The commerce hierarchy takes cues from current editorial fashion apps rather than generic dashboard cards:

- SSENSE emphasizes search/filtering and a restrained product grid. Its current App Store feedback also explicitly favors the more legible two-column presentation over a denser grid: [SSENSE on the App Store](https://apps.apple.com/us/app/ssense-shop-designer-fashion/id1418754101).
- Mytheresa emphasizes curated discovery plus practical search and filtering: [Mytheresa on the App Store](https://apps.apple.com/us/app/mytheresa-shop-luxury-brands/id484615570).
- Vogue’s fashion/runway experience supports the large-image, low-chrome editorial treatment used for Stylezam’s capture and Look Stack: [Vogue on the App Store](https://apps.apple.com/us/app/vogue-fashion-shopping/id289380413).

These are references for hierarchy and restraint, not screens copied into the app.

## Implemented screen system

### Home

A compact brand header leads into the product promise: “Find what they’re wearing.” If a real capture exists it becomes the hero; otherwise the final cobalt-and-white Stylezam mark anchors a restrained brand composition without fake fashion photography.

### Capture

Camera, Photos, Paste, image-plus-words, and words-only search share one full-height sheet. A real selected image becomes the primary canvas and text remains an optional refinement. A single primary action starts the real backend job.

### Search and Look Stack

Search progress reflects backend phases rather than a fixed animation. When local vision returns multiple boxes, the original capture becomes a tappable Look Stack. Selecting a box submits another real search using that normalized region. Results use a two-column grid with explicit evidence tiers.

### Product evidence

The product page separates upstream identity evidence from visual similarity. “Exact,” “likely,” “similar,” and “inspired” remain evidence labels, never guarantees. Direct merchant URLs and observed offers remain visible.

### Appearance preview

Try-on is a full-screen visual stage with glass controls. The result is called an appearance preview and explicitly does not predict size or fit. A completed preview is downloaded to the iPhone for share/save before Stylezam requests deletion of its backend copy.

### Archive and Setup

The archive stays empty until the user creates real searches or bookmarks. Setup prioritizes the reliable two-action Screenshot Shortcut, then Control Center/Action Button, Share, and the consent-based iOS 27 live-screen option.

## Accessibility and platform behavior

- Controls use semantic SwiftUI buttons, labels, headings, and system symbols.
- Text content supports Dynamic Type; editorial titles can wrap vertically rather than scale to illegibility.
- Match meaning is written in text and is never conveyed by color alone.
- System permission/picker UI remains system-owned.
- Tab bar and glass behavior use native iOS 26 APIs, including scroll minimization.
