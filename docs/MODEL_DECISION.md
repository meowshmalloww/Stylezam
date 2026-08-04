# On-device model decision

Decision recorded on 2026-08-03 and updated for the bundled local architecture on 2026-08-04.

## Active stack

| Stage | Selection | Runs where | Runtime cost |
| --- | --- | --- | --- |
| Boxes, masks, and item classes | RF-DETR-Seg-Small garment checkpoint | Core ML on iPhone | No inference API call |
| Thresholding and duplicate suppression | Native Swift | iPhone | Local CPU |
| Transparent crop generation | Core Graphics | iPhone | Local CPU |
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
| Product retrieval services | Deferred until a separate provider passes quality, privacy, and cost benchmarks. |
| YouCam photo try-on | Added as an explicit, consent-gated network workflow; the local capture and detection stack remains unchanged. |

## Runtime bounds

- Default item limit: 5.
- Developer maximum: 12.
- Source image normalization ceiling: 1600 pixels on the longest side.
- Model input: 384 × 384 FP32 normalized tensor.
- Class confidence threshold: 0.35.
- Same-class duplicate suppression: IoU above 0.74.
- Preview mode: boxes/classes only; no crop or mask-byte materialization.
- Accepted capture: masks and transparent crops generated once and persisted locally.

The local vision stack stores no model-provider credentials because the active model is bundled. The optional YouCam prototype can store its bearer credential in the device Keychain; production builds must proxy that credential through a Stylezam server.
