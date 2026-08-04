# Third-party notices

This inventory accompanies the Stylezam local-vision release. It is not legal advice and should be reviewed before public distribution.

## Bundled garment model

### RF-DETR

- Project: RF-DETR by Roboflow.
- Source: <https://github.com/roboflow/rf-detr>
- Selected family: RF-DETR-Seg-Small, an Apache-designated model.
- License: Apache License 2.0.

Stylezam does not ship RF-DETR Plus components or the Python training runtime.

### Resoa garment checkpoint

- Model: `resoa/garment-detector-seg`.
- Source: <https://huggingface.co/resoa/garment-detector-seg>
- Pinned revision: `f1b64c11fa42d2f7455708b7a05f81c015461427`.
- Checkpoint SHA-256: `aafefc440ea8f3f388e894a898e4270a2eeb6e38a3c3ffd3751d07d0f30b26bb`.
- Model-card license: Apache-2.0.

### Fashionpedia

- Dataset/ontology: Fashionpedia, Jia et al., ECCV 2020.
- Project: <https://fashionpedia.github.io/>
- Paper: <https://arxiv.org/abs/2004.12276>
- Annotation/ontology license: Creative Commons Attribution 4.0 International.
- License page: <https://fashionpedia.github.io/home/data_license.html>

Attribution embedded in the bundled model manifest:

> RF-DETR by Roboflow; garment checkpoint by Resoa; trained on Fashionpedia (CC BY 4.0, Jia et al., ECCV 2020).

The bundled package records the exact source revision, checkpoint hash, compiled model-file hashes, and byte counts in `App/Resources/Models/garment-segmentation.json`.

## Apple frameworks

Stylezam links Apple platform frameworks supplied by the OS/SDK, including SwiftUI, AVFoundation, Vision, Core ML, ActivityKit, WidgetKit, App Intents, PhotosUI, and—when compiled with the iOS 27 SDK—ScreenCaptureKit. Their use is governed by Apple’s SDK and developer agreements rather than the Stylezam Apache license.

## Development-only model tooling

The optional scripts for model research, export, and benchmark can use Python, PyTorch, RF-DETR, Core ML Tools, NumPy, Pillow, PyArrow, and dataset readers in an isolated developer environment. Those Python packages are not linked into or shipped with the iOS application. Audit their active licenses and versions whenever reproducing or replacing the bundled artifact.
