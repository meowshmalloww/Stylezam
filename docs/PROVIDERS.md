# Providers and model decision

Research and benchmark decision recorded on 2026-08-03.

## Active stack

| Stage | Selection | Runs where | Cost boundary |
| --- | --- | --- | --- |
| Garment boxes, masks, and initial classes | RF-DETR-Seg-Small garment checkpoint | Core ML on iPhone | No inference API call |
| Crop validation and visible attributes | MiniMax M3 through Fireworks | Fireworks serverless | One call per look, app-side monthly cap |
| Model/package delivery and request controls | Stylezam FastAPI service | Daytona CPU sandbox | 2 CPU, 4 GB, 10 GB, no GPU |

There is no Qwen route, OpenAI route, local model server, or GPU inference route in the active capture pipeline.

## Why RF-DETR-Seg-Small

The selected checkpoint is [`resoa/garment-detector-seg`](https://huggingface.co/resoa/garment-detector-seg), revision `f1b64c11fa42d2f7455708b7a05f81c015461427`. Its model card declares Apache-2.0 and says it is trained on Fashionpedia. RF-DETR’s open-source package and Apache-designated small segmentation weights are Apache-2.0; its own comparison table marks common YOLO alternatives AGPL-3.0: [RF-DETR repository](https://github.com/roboflow/rf-detr).

It was selected because one compact model supplies both item geometry and masks, converts through RF-DETR’s native Core ML exporter, runs on the phone, and keeps the Daytona service free of heavyweight ML dependencies.

The model is not a complete jewelry detector. Fashionpedia has watch, clothing, footwear, bag, and accessory classes but no item classes for rings, bracelets, necklaces, or earrings. That gap is documented rather than delegated to an image-language model without a reliable crop.

## Why MiniMax M3 on Fireworks

Fireworks lists `accounts/fireworks/models/minimax-m3` as a native multimodal model with image input, and its launch example uses the OpenAI-compatible chat-completions shape used by Stylezam: [MiniMax M3 model page](https://fireworks.ai/models/fireworks/minimax-m3), [launch example](https://fireworks.ai/blog/minimax-m3-launch).

Stylezam sends one request containing all candidate crops and a JSON Schema. The request uses temperature zero and a bounded output-token count. MiniMax may:

- reject a false or unusable crop;
- normalize the category;
- write a short visible-fact display name;
- list visible colors, materials, patterns, construction details, and readable text;
- return a brand only when visible text or an unmistakable logo supports it.

MiniMax does not decide the mask and does not search for products in this release.

Fireworks currently prices MiniMax M3 serverless by input and output tokens. The default `STYLEZAM_FIREWORKS_MONTHLY_CAP=100` blocks the 101st Stylezam request in a UTC month, but the first 100 remain billable according to the user’s Fireworks account. This application cap is not an account billing control. Fireworks separately documents prepaid credits and a configurable monthly spend limit that pauses all account API requests when reached; set it with `firectl quota update monthly-spend-usd --value <USD>` before production use: [Fireworks account quotas](https://docs.fireworks.ai/guides/quotas_usage/account-quotas).

## Candidates not shipped

| Candidate | Decision |
| --- | --- |
| Grounded SAM2/SAM3 on Daytona | Rejected for V1: model downloads, memory, and CPU latency do not fit the 2-core/4 GB service target. |
| Grounding DINO + SAM2 + CLIP | Rejected for V1: three runtimes duplicate work now performed by the phone and substantially expand the dependency and license surface. |
| YOLO segmentation families | Not selected: the evaluated open variants carry AGPL obligations that are unnecessary for this release. |
| EdgeTAM | Not selected as the primary detector: it is prompt-oriented and would still require a separate fashion detector/classifier. |
| Apple foreground-instance masks | Retained only as a manual-photo fallback; they do not provide garment classes. |
| Qwen API | Removed by product decision. |
| YouCam | Deferred. No key is required and virtual try-on stays disabled. |
| SerpApi/eBay/product retrieval | Deferred until the product-search benchmark. |

## Quotas and overload controls

- Default phone item limit: 5.
- Developer Debug maximum: 12, matching the server cap.
- Maximum normalized image: 10 MB each.
- Maximum decoded dimensions: 20 million pixels per image.
- Maximum normalized crop batch: 20 MB.
- Maximum incoming request body, including multipart overhead: 24 MB.
- Concurrent complete crop normalization-and-Fireworks batches: 2 per backend process.
- Fireworks monthly request cap: configurable, 100 by default.
- The SQLite cap persists across ordinary restarts on the same `/data` disk, but a destroyed/recreated sandbox or deleted database resets it; it is not an account-wide Fireworks budget.
- A product or try-on flag must be explicitly enabled before those older route implementations can run.

Provider credentials remain backend-only. The iPhone stores only the Stylezam service URL and its bearer token in Developer Debug/Keychain.
