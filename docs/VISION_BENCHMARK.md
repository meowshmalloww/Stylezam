# Garment model benchmark

Decision date: 2026-08-03.

## Selected artifact

- Architecture: RF-DETR-Seg-Small.
- Checkpoint: [`resoa/garment-detector-seg`](https://huggingface.co/resoa/garment-detector-seg).
- Source revision: `f1b64c11fa42d2f7455708b7a05f81c015461427`.
- Source checkpoint SHA-256: `aafefc440ea8f3f388e894a898e4270a2eeb6e38a3c3ffd3751d07d0f30b26bb`.
- Export: native RF-DETR Core ML, FP16, 384 × 384 MLMultiArray input.
- Published pack: `garment-rfdetr-seg-small/1.0.1`.
- Published size: approximately 59 MB.
- Core ML weight SHA-256: `367113287aa69beb185a4af20e1505b3a1c4fc829b3c0e4ee48788b1e2d48341`.
- Model/checkpoint license declaration: Apache-2.0.
- Dataset: Fashionpedia annotations/ontology, CC BY 4.0.

Fashionpedia’s official license page confirms CC BY 4.0 for annotations and ontology: [Fashionpedia data license](https://fashionpedia.github.io/home/data_license.html). The attribution is embedded in the server manifest and displayed in model setup.

## Qualification result

The source checkpoint was run on eight evenly spaced Fashionpedia validation rows at a 0.35 confidence threshold, 384 resolution, and a five-item cap.

| Measurement | Result |
| --- | ---: |
| Sample count | 8 images |
| MPS warm median | 0.0619 s/image |
| MPS p95 including first-run effect | 0.3676 s/image |
| Class-aware precision at IoU 0.50 | 0.9333 |
| Class-aware recall at IoU 0.50 | 0.8750 |
| Native Core ML cold prediction on this Mac | 0.1336 s |
| Native Core ML warm median on this Mac | 0.0250 s |

This is a smoke benchmark, not a production accuracy claim. Eight linearly sampled validation images are too small to characterize demographic, lighting, camera-motion, jewelry, occlusion, or real-world distribution performance. The Core ML timings are from a six-run verification of the packaged `1.0.1` artifact on this Mac with `ComputeUnit.ALL`; the verifier now uses the same best-class-per-query, minimum-box, same-class IoU suppression, and five-item selection rules as the Swift runtime. They are not iPhone timings. Physical-device thermal, memory, battery, and latency testing remains required.

## Why this candidate won

- Detection and instance masks are produced by one model.
- The small segmentation variant is Apache-designated by RF-DETR.
- The checkpoint has fashion-specific classes instead of generic COCO labels.
- Native Core ML export avoided a custom unverified graph rewrite.
- The phone performs the expensive work, keeping Daytona CPU-only.
- The package is small enough for an explicit Wi-Fi-only first-run download.

Grounded SAM variants were excluded from the 4 GB CPU backend, YOLO variants were avoided for their evaluated AGPL license, and prompt-only mask models still required a separate detector. See [Providers](PROVIDERS.md).

## Reproduce the qualification

The benchmark/export environment is intentionally separate from the runtime backend because it contains PyTorch, RF-DETR, Core ML Tools, NumPy, PyArrow, and the Fashionpedia validation data.

```bash
python scripts/benchmark_garment_model.py \
  --checkpoint /path/to/checkpoint_best_ema.pth \
  --parquet /path/to/fashionpedia-validation.parquet \
  --output /tmp/stylezam-garment-benchmark \
  --device mps \
  --resolution 384 \
  --samples 8 \
  --max-items 5

python scripts/export_garment_coreml.py \
  --checkpoint /path/to/checkpoint_best_ema.pth \
  --output-dir /tmp/stylezam-coreml \
  --resolution 384 \
  --classes 46

python scripts/verify_coreml_garment_model.py \
  --model /tmp/stylezam-coreml/rfdetr-seg-small.mlpackage \
  --image /path/to/representative-look.jpg \
  --output /tmp/stylezam-coreml-overlay.jpg \
  --report /tmp/stylezam-coreml-report.json \
  --classes Config/FashionpediaClasses.json \
  --runs 6

python scripts/package_garment_model.py \
  --model /tmp/stylezam-coreml/rfdetr-seg-small.mlpackage \
  --checkpoint /path/to/checkpoint_best_ema.pth \
  --output-dir backend/.data/model-packs \
  --classes Config/FashionpediaClasses.json \
  --version 1.0.2
```

Published versions are immutable. Packaging refuses to overwrite an existing version.

## Coverage gap

Only class IDs 0–26 become pieces. Part/detail classes 27–45 remain suppressed. Watches are covered; rings, bracelets, necklaces, and earrings are not. V1 should ask for a manual crop or report unsupported rather than claiming a detection that did not occur.
