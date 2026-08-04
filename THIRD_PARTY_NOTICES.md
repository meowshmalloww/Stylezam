# Third-party notices

This inventory accompanies the Stylezam capture/understanding release. It is not legal advice and should be reviewed before public distribution.

## Garment model

### RF-DETR

- Project: RF-DETR by Roboflow.
- Source: <https://github.com/roboflow/rf-detr>
- Selected family: RF-DETR-Seg-Small, an Apache-designated model.
- License: Apache License 2.0.

The repository states that the open-source `rfdetr` package and Apache-designated model weights are licensed under Apache 2.0. Stylezam does not ship RF-DETR Plus components.

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

Attribution embedded in the model manifest:

> RF-DETR by Roboflow; garment checkpoint by Resoa; trained on Fashionpedia (CC BY 4.0, Jia et al., ECCV 2020).

## Python runtime

The production image installs exact hashes from `backend/requirements.lock`. Direct dependencies and their project-declared licenses are:

| Package | License family | Project |
| --- | --- | --- |
| FastAPI | MIT | <https://github.com/fastapi/fastapi> |
| HTTPX | BSD-3-Clause | <https://github.com/encode/httpx> |
| Pillow | MIT-CMU | <https://github.com/python-pillow/Pillow> |
| Pydantic Settings | MIT | <https://github.com/pydantic/pydantic-settings> |
| python-multipart | Apache-2.0 | <https://github.com/Kludex/python-multipart> |
| Uvicorn | BSD-3-Clause | <https://github.com/encode/uvicorn> |

Transitive package versions are included in the lock file and should be regenerated/audited together. To reproduce the vulnerability check:

```bash
python -m venv /tmp/stylezam-audit
/tmp/stylezam-audit/bin/python -m pip install pip-audit
/tmp/stylezam-audit/bin/pip-audit \
  -r backend/requirements.lock \
  --no-deps \
  --disable-pip \
  --progress-spinner off
```

An audit result is a point-in-time signal, not a guarantee that no vulnerability exists.

The current point-in-time result and complete resolved license-expression list are recorded in [docs/DEPENDENCY_AUDIT.md](docs/DEPENDENCY_AUDIT.md).

## Apple frameworks

Stylezam links Apple platform frameworks supplied by the OS/SDK, including SwiftUI, AVFoundation, Vision, Core ML, ActivityKit, WidgetKit, App Intents, PhotosUI, and—when compiled with the iOS 27 SDK—ScreenCaptureKit. Their use is governed by Apple’s SDK and developer agreements rather than the Stylezam Apache license.

## Hosted service

Qwen3.7 Plus is a closed-weight model accessed through the user’s Fireworks account and is not redistributed in the Stylezam repository or Daytona image. Fireworks terms, acceptable-use rules, data-handling policy, and model availability apply to those API calls.
