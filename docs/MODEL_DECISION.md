# On-device model decision

Decision recorded on 2026-08-03 and updated for the bundled local architecture on 2026-08-04.

## Active stack

| Stage | Selection | Runs where | Runtime cost |
| --- | --- | --- | --- |
| Boxes, masks, and item classes | RF-DETR-Seg-Small garment checkpoint | Core ML on iPhone | No inference API call |
| Thresholding and duplicate suppression | Native Swift | iPhone | Local CPU |
| High-resolution box-crop generation | ImageIO/Core Graphics | iPhone | Local CPU |
| Adaptive detail detection | Bounded overlapping square tiles | iPhone still photos | 4–6 additional sequential predictions when permitted |
| Transparent mask diagnostics | Core Graphics | Vision Inspector only | Local CPU |
| Persistence and inspection | Native SwiftUI/Foundation | iPhone | Local storage |

There is no active processing host, model server, GPU worker, image-language API, or laptop dependency.

## Why RF-DETR-Seg-Small

The selected checkpoint is [`resoa/garment-detector-seg`](https://huggingface.co/resoa/garment-detector-seg), revision `f1b64c11fa42d2f7455708b7a05f81c015461427`. Its model card declares Apache-2.0 and says it is trained on Fashionpedia. RF-DETR’s open-source package and Apache-designated small segmentation weights are Apache-2.0: [RF-DETR repository](https://github.com/roboflow/rf-detr).

One compact model supplies both item geometry and instance masks, has fashion-specific classes rather than generic COCO labels, converts through RF-DETR’s Core ML exporter, and fits in the iOS bundle at 61.7 MB.

## Coverage boundary

Fashionpedia supplies useful clothing, footwear, bag, watch, and accessory item classes but not item classes for rings, bracelets, necklaces, or earrings. Stylezam documents that gap rather than guessing those items from an unreliable whole-image label.

## Candidates not shipped

| Candidate | Decision |
| --- | --- |
| Grounding detector + promptable mask model + embedding model | Three runtimes duplicate the selected model’s work and substantially increase size, latency, memory, and license surface. |
| Generic YOLO segmentation variants | Not selected because evaluated open variants added license obligations unnecessary for this release. |
| Prompt-oriented mobile mask models | Useful for future user-selected refinement, but still require a fashion detector/classifier. |
| Apple foreground-instance masks | Kept only as code-level fallback capability; the production capture path requires the bundled fashion model for classes. |
| Hosted image-language labeling | Removed from this build. It would reintroduce credentials, retention questions, network latency, and per-call cost. |
| Product and virtual try-on services | Deferred until separate quality, privacy, and cost benchmarks are complete. |

## Runtime bounds

- Default item limit: 5.
- Developer maximum: 12.
- Live-preview source ceiling: 1600 pixels on the longest side.
- Accepted-image source ceiling: 5120 pixels on the longest side.
- Model input: 384 × 384 FP32 normalized tensor.
- Accepted still-photo detail: one full-frame prediction plus four tiles for
  roughly 1080p–3K sources, or six tiles for 4K–5K sources at nominal thermal
  state. This yields approximately 686 px and 1029 px of effective long-edge
  detector detail respectively while every individual tensor remains 384×384.
- Processing scheduler: 9-second internal still-photo budget with crop reserve.
- Power and heat protection: no detail tiles in Low Power Mode; reduced tiling
  at fair thermal pressure; no tiling at serious or critical pressure.
- Live and screen modes: always single-pass to bound sustained CPU use.
- Class confidence threshold: 0.35.
- Same-class duplicate suppression: IoU above 0.74.
- Preview mode: boxes/classes only; no crop or mask-byte materialization.
- Accepted capture: readable 94%-quality JPEG box crops are persisted locally.
- Vision Inspector: raw transparent masks are generated on demand and are not
  part of normal capture latency or Library art.

The app stores no model-provider credentials because the active model is bundled.
