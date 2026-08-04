#!/usr/bin/env python3
"""Publish a verified Core ML package into the backend's model-pack catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


MODEL_ID = "garment-rfdetr-seg-small"
PACKAGE_NAME = "StylezamGarmentSegmentation.mlpackage"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--classes", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--input-name", default="tensors")
    parser.add_argument("--box-output-name", default="concat_3")
    parser.add_argument("--logit-output-name", default="linear_122")
    parser.add_argument("--mask-output-name", default="add_62")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    args = parse_args()
    if args.model.suffix != ".mlpackage" or not args.model.is_dir():
        raise ValueError("--model must point to an existing .mlpackage directory")
    if not args.checkpoint.is_file():
        raise FileNotFoundError(args.checkpoint)
    class_names = json.loads(args.classes.read_text(encoding="utf-8"))
    if not isinstance(class_names, list) or len(class_names) != 46:
        raise ValueError("Fashionpedia class file must contain exactly 46 labels")

    required_paths = [
        Path("Manifest.json"),
        Path("Data/com.apple.CoreML/model.mlmodel"),
        Path("Data/com.apple.CoreML/weights/weight.bin"),
    ]
    for relative in required_paths:
        if not (args.model / relative).is_file():
            raise FileNotFoundError(relative)

    storage_prefix = Path(MODEL_ID) / args.version / PACKAGE_NAME
    destination = args.output_dir / storage_prefix
    catalog_path = args.output_dir / "garment-segmentation.json"
    if destination.exists():
        raise FileExistsError(
            f"{destination} already exists; publish a new immutable version instead"
        )
    destination.mkdir(parents=True)

    files = []
    for relative in required_paths:
        source = args.model / relative
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        files.append(
            {
                "path": relative.as_posix(),
                "url": "",
                "sha256": sha256(target),
                "bytes": target.stat().st_size,
            }
        )

    payload = {
        "modelID": MODEL_ID,
        "version": args.version,
        "displayName": "Stylezam Garment Segmentation",
        "storagePrefix": storage_prefix.as_posix(),
        "totalBytes": sum(item["bytes"] for item in files),
        "minimumIos": "26.0",
        "inputName": args.input_name,
        "inputResolution": 384,
        "boxOutputName": args.box_output_name,
        "logitOutputName": args.logit_output_name,
        "maskOutputName": args.mask_output_name,
        "classNames": class_names,
        "licenseName": "Apache-2.0",
        "licenseURL": "https://www.apache.org/licenses/LICENSE-2.0",
        "sourceURL": "https://huggingface.co/resoa/garment-detector-seg",
        "sourceRevision": "f1b64c11fa42d2f7455708b7a05f81c015461427",
        "checkpointSHA256": sha256(args.checkpoint),
        "datasetName": "Fashionpedia",
        "datasetLicenseName": "CC BY 4.0",
        "datasetLicenseURL": "https://creativecommons.org/licenses/by/4.0/",
        "attribution": (
            "RF-DETR by Roboflow; garment checkpoint by Resoa; trained on "
            "Fashionpedia (CC BY 4.0, Jia et al., ECCV 2020)."
        ),
        "files": files,
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    temporary_catalog = catalog_path.with_suffix(".json.tmp")
    temporary_catalog.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary_catalog.replace(catalog_path)
    print(catalog_path)


if __name__ == "__main__":
    main()
