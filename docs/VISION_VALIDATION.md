# Local garment vision validation

Validated August 4, 2026 against model pack `garment-rfdetr-seg-small` version
`1.0.1`. Stylezam runs this model with Core ML on the user's device. No server,
API key, or network request is involved in these tests.

## What is implemented

- Photo-library input, camera input, and the saved-capture path all call the same
  `GarmentVisionEngine`.
- The model emits Fashionpedia class IDs, confidence, normalized bounding boxes,
  and a separate 96×96 mask for each detected item.
- Stylezam exposes the 27 Fashionpedia item categories (IDs 0–26). The remaining
  19 Fashionpedia part classes are not presented as separate Library items.
- Each detection produces a reliable unmasked bounding-box crop for Library.
- When Vision Inspector is open, the model's 96×96 mask also becomes a
  transparent diagnostic PNG with bilinear sampling and a narrow soft alpha
  transition. This raw iOS mask is not generated during normal capture or used
  as the Library thumbnail because device testing exposed incorrect regions.
- The in-app Vision Inspector shows the source overlay, saved box crop,
  transparent cutout, and black/white alpha mask, then reports class ID, label,
  confidence, normalized and pixel-space boxes, image dimensions, PNG byte
  counts, mask coverage, and transparent/soft/opaque alpha counts.

This model identifies item categories and item-specific masks. It does **not**
yet infer brand, material, color, pattern, product name, or retailer metadata.
Those properties require a later visual-language/search stage and must not be
presented as segmentation output.

## Full Fashionpedia validation result

The verifier ran the shipped Core ML package on all 1,158 Fashionpedia validation
images using the app's production decoding rules:

- input resolution: 384×384
- confidence threshold: 0.35
- same-class suppression threshold: box IoU above 0.74
- maximum returned items: 5
- Core ML compute policy: CPU only, matching the iOS production loader
- detections: 4,140
- class-aware precision at box IoU 0.50: **0.8667**
- class-aware recall at box IoU 0.50: **0.7654**
- mean mask IoU for class/box-matched detections on macOS: **0.8114**
- median detection confidence: **0.8764**
- Mac Core ML inference median: **45.76 ms**
- Mac Core ML inference p95: **48.92 ms**

There are 228 validation images with more than five labeled items. The reported
recall therefore includes the app's intentional five-item truncation. These are
simple class-aware IoU measurements for the shipped app pipeline, not COCO mAP,
and should not be compared directly with the model author's mAP figures.

| ID | Fashionpedia item | Truth | Pred. | Matched | Precision | Recall | Mean mask IoU |
|---:|---|---:|---:|---:|---:|---:|---:|
| 0 | shirt, blouse | 102 | 71 | 49 | 0.6901 | 0.4804 | 0.8880 |
| 1 | top, t-shirt, sweatshirt | 477 | 441 | 357 | 0.8095 | 0.7484 | 0.8858 |
| 2 | sweater | 21 | 12 | 7 | 0.5833 | 0.3333 | 0.9337 |
| 3 | cardigan | 12 | 4 | 3 | 0.7500 | 0.2500 | 0.9116 |
| 4 | jacket | 183 | 177 | 144 | 0.8136 | 0.7869 | 0.9098 |
| 5 | vest | 22 | 11 | 10 | 0.9091 | 0.4545 | 0.8765 |
| 6 | pants | 314 | 322 | 288 | 0.8944 | 0.9172 | 0.9145 |
| 7 | shorts | 106 | 94 | 80 | 0.8511 | 0.7547 | 0.8886 |
| 8 | skirt | 162 | 172 | 119 | 0.6919 | 0.7346 | 0.9293 |
| 9 | coat | 104 | 83 | 66 | 0.7952 | 0.6346 | 0.9154 |
| 10 | dress | 508 | 515 | 460 | 0.8932 | 0.9055 | 0.9295 |
| 11 | jumpsuit | 21 | 12 | 5 | 0.4167 | 0.2381 | 0.9042 |
| 12 | cape | 5 | 0 | 0 | — | 0.0000 | — |
| 13 | glasses | 130 | 98 | 94 | 0.9592 | 0.7231 | 0.7316 |
| 14 | hat | 74 | 68 | 62 | 0.9118 | 0.8378 | 0.8455 |
| 15 | head covering / hair accessory | 109 | 69 | 50 | 0.7246 | 0.4587 | 0.6829 |
| 16 | tie | 3 | 2 | 1 | 0.5000 | 0.3333 | 0.7859 |
| 17 | glove | 31 | 28 | 21 | 0.7500 | 0.6774 | 0.7977 |
| 18 | watch | 84 | 36 | 30 | 0.8333 | 0.3571 | 0.6867 |
| 19 | belt | 164 | 113 | 70 | 0.6195 | 0.4268 | 0.7183 |
| 20 | leg warmer | 14 | 2 | 2 | 1.0000 | 0.1429 | 0.9287 |
| 21 | tights, stockings | 122 | 103 | 83 | 0.8058 | 0.6803 | 0.8704 |
| 22 | sock | 87 | 34 | 26 | 0.7647 | 0.2989 | 0.7773 |
| 23 | shoe | 1,566 | 1,466 | 1,388 | 0.9468 | 0.8863 | 0.7094 |
| 24 | bag, wallet | 214 | 173 | 150 | 0.8671 | 0.7009 | 0.8145 |
| 25 | scarf | 48 | 28 | 18 | 0.6429 | 0.3750 | 0.8601 |
| 26 | umbrella | 5 | 6 | 5 | 0.8333 | 1.0000 | 0.9053 |

The strongest masks are generally medium and large garments. Very small or thin
items—especially watches, belts, head accessories, glasses, socks, and shoes—have
lower macOS mask IoU because a 96×96 mask has limited boundary resolution. Rare classes
such as cape, cardigan, leg warmer, and jumpsuit also have weak recall.

These mask-IoU measurements validate the package on macOS Core ML. The same
export's iOS mask tensor does not preserve that semantic quality: device output
can include large incorrect regions even when category and box are correct.
Stylezam therefore treats the mask as a visible diagnostic artifact and uses the
box crop as the product-facing result until the model is reconverted or refined.

## macOS transparent-crop spot check

A representative 12-image macOS subset covered tops, shirt, sweater, cardigan, jacket,
vest, coat, dress, jumpsuit, pants, shorts, skirt, tights, shoes, glasses, hat,
head covering, gloves, watch, belt, scarf, bags, and umbrella.

- 43 transparent PNG crops were generated.
- Every crop contained nonzero foreground and nonzero transparency.
- Every crop contained partial-alpha pixels for antialiased boundaries.
- Mean mask IoU for matched items was 0.8057 on this selected visual-QA subset.

This subset is for crop and rendering inspection only; the full-split result
above is the honest accuracy measurement.

## Physical iPhone test

The signed Debug build was installed and executed on an iPhone 15 Pro Max running
iOS 27.0. Four real Fashionpedia photos ran through the exact production engine,
then the generated JSON and JPEG crop files were copied back from the app container.

| Photo | Items | End-to-end time | Returned categories |
|---|---:|---:|---|
| `row-0000-image-2083.jpg` | 4 | 136.99 ms | jacket, glasses, shirt/blouse, tie |
| `row-0127-image-9834.jpg` | 4 | 145.05 ms | dress, umbrella, belt, belt |
| `row-0423-image-12726.jpg` | 5 | 95.47 ms | tights ×2, shoes ×2, dress |
| `row-0852-image-17958.jpg` | 3 | 101.31 ms | glasses, coat, bag |

All four device runs returned the expected categories and usable boxes. The app
now persists a clean box crop for every item and does not materialize masks
during normal capture. Vision Inspector can generate the raw transparent PNG on
demand; visual inspection showed that it can represent the wrong region on iOS,
so alpha statistics alone are not a mask-quality test. The second photo also
demonstrates a real limitation: a low-confidence 0.3720 duplicate belt survives
the current same-class suppression rule.

A second physical-device session profiled the staged Live Screen watcher. Once
an unchanged screen had been handled, a 21.14-second Time Profiler trace recorded
only two 1 ms running samples for Stylezam and the device remained at the
`Nominal` thermal state. Changing the visible fashion content woke the detector:
a separate 19.13-second trace contained the expected `modelInput`,
`coreMLDetections`, and `analyze` stacks, saved real garment crops, and also
remained thermally `Nominal`. This validates both sides of the scheduler: idle
screens stop repeating Core ML work, while meaningful content changes resume it.

## Accepted-image resolution and adaptive latency

The RF-DETR model itself has a fixed 384×384 tensor. Stylezam does not pretend
that passing a 5K buffer to one prediction changes that tensor. Accepted still
photos now combine a global prediction with overlapping square detail tiles.
Each tile is independently reduced to 384×384, then its boxes are projected into
the accepted source coordinate system and merged across scales. This raises the
effective long-edge detector detail to about 686 px at 1080p and 1029 px at
4K–5K. Library crops are encoded from the retained source pixels as 94%-quality
JPEGs. Live camera preview remains single-pass, backs off after two unchanged
empty results, and stops repeating inference for an unchanged view after a
successful save. Motion or a candidate restores the fast cadence. Live Screen first waits for a
480 px content signature to stabilize, runs one crop-free global-plus-detail
discovery because phone pages are much taller than the model tensor, then uses
one focused tensor for each confirmation. Captured and verified-empty screens
run no additional Core ML until their content signature changes. After either
live path reaches temporal consensus, the
accepted full-quality camera still or device-resolution screen frame uses the
same bounded, thermal-aware detail plan as Photo mode.

The same Fashionpedia photo was resolution-scaled to exercise the complete
source/crop path on the iPhone 15 Pro Max. Scaling a 1K photo does not invent
real detail; this benchmark measures latency and verifies retained output
dimensions.

The original single-pass measurements are retained as the continuous-mode and
thermal-protection baseline. The adaptive still-photo measurements below are
from the signed production engine on the same iPhone.

| Accepted source | Passes | Effective detail | Decode | Tensor prep | Core ML | Output decode | Crop JPEGs | Total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1920×1280 | 5 | ≈686 px | 31.65 ms | 145.57 ms | 422.56 ms | 17.50 ms | 7.83 ms | **625.42 ms** |
| 5120×3415 | 7 | ≈1029 px | 186.58 ms | 201.02 ms | 687.45 ms | 21.94 ms | 48.18 ms | **1,146.25 ms** |
| 2880×5120 five-piece outfit | 7 | ≈1029 px | 65.32 ms | 237.89 ms | 756.11 ms | 26.99 ms | 22.22 ms | **1,108.87 ms** |

At 1920 px, the jacket crop was 1454×870 and 265 KB. At 5120 px, the same
jacket crop was 3848×2332 and 1.16 MB. The second 5K test correctly returned a
dress, two separate tights regions, and two separate shoes. Category labels are
decoded from the model's Fashionpedia logits during the measured
inference/output stages; there is no extra network or VLM-labeling request.

The scheduler checks `ProcessInfo.thermalState` before detail passes and follows
Apple's [thermal-state guidance](https://developer.apple.com/documentation/foundation/processinfo)
to reduce system use as thermal state rises. Low Power Mode also disables detail
passes because Apple documents reduced CPU/GPU performance in its
[`isLowPowerModeEnabled` guidance](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled).
The app runs passes sequentially, never as a parallel CPU burst, and reserves
crop time inside its 9-second internal budget.

## Reproduce

The verifier compiles the source model with `coremlc`, compiles the Swift runner,
executes the same normalization/output decoding as the app, supports both polygon
and compressed COCO RLE truth masks, and writes `report.json`:

```sh
python3 scripts/verify_coreml_garment_model.py \
  --model App/Resources/Models/StylezamGarmentSegmentation.mlpackage \
  --manifest App/Resources/Models/garment-segmentation.json \
  --input /path/to/fashionpedia-validation-images \
  --fashionpedia-annotations /path/to/instances_attributes_val2020.json \
  --output /tmp/stylezam-fashionpedia-results \
  --threshold 0.35 \
  --max-items 5 \
  --runs 1 \
  --metrics-only
```

Remove `--metrics-only` on a smaller image set to generate source overlays and
transparent PNG crops in addition to the JSON diagnostics.

## Sources and licensing

- [Fashionpedia project](https://fashionpedia.github.io/home/index.html)
- [Fashionpedia source and annotations](https://github.com/cvdfoundation/fashionpedia)
- [Fashionpedia paper](https://arxiv.org/abs/2004.12276)
- [Shipped garment model card](https://huggingface.co/resoa/garment-detector-seg)

Fashionpedia is licensed CC BY 4.0. The shipped RF-DETR model is Apache-2.0; the
model manifest records the exact source revision, checkpoint SHA-256, licenses,
and attribution.
