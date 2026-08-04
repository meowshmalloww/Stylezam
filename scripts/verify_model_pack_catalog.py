#!/usr/bin/env python3
"""Verify the Core ML package bundled into the Stylezam iOS application."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MODEL_ROOT = ROOT / "App/Resources/Models"
CATALOG_PATH = MODEL_ROOT / "garment-segmentation.json"
PACKAGE_ROOT = MODEL_ROOT / "StylezamGarmentSegmentation.mlpackage"
CLASS_PATH = ROOT / "Config/FashionpediaClasses.json"
REQUIRED_FILES = {
    "Manifest.json",
    "Data/com.apple.CoreML/model.mlmodel",
    "Data/com.apple.CoreML/weights/weight.bin",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    classes = json.loads(CLASS_PATH.read_text(encoding="utf-8"))
    if catalog.get("classNames") != classes or len(classes) != 46:
        raise ValueError("Bundled class order does not match FashionpediaClasses.json")
    if catalog.get("modelID") != "garment-rfdetr-seg-small":
        raise ValueError("Unexpected bundled model ID")
    if catalog.get("inputResolution") != 384:
        raise ValueError("Unexpected model input resolution")
    if not re.fullmatch(r"[0-9a-f]{64}", catalog.get("checkpointSHA256", "")):
        raise ValueError("Missing or invalid source-checkpoint SHA-256")
    if catalog.get("licenseName") != "Apache-2.0":
        raise ValueError("Unexpected model license declaration")
    if catalog.get("datasetLicenseName") != "CC BY 4.0":
        raise ValueError("Unexpected dataset license declaration")

    file_entries = catalog.get("files", [])
    if {entry.get("path") for entry in file_entries} != REQUIRED_FILES:
        raise ValueError("Bundled file list is incomplete or contains extras")

    actual_total = 0
    package_resolved = PACKAGE_ROOT.resolve()
    for entry in file_entries:
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Unsafe model file path: {relative}")
        path = (PACKAGE_ROOT / relative).resolve()
        if package_resolved not in path.parents or not path.is_file():
            raise FileNotFoundError(path)
        size = path.stat().st_size
        if size != entry["bytes"]:
            raise ValueError(f"Byte count mismatch: {relative}")
        if sha256(path) != entry["sha256"]:
            raise ValueError(f"SHA-256 mismatch: {relative}")
        actual_total += size
    if actual_total != catalog["totalBytes"]:
        raise ValueError("Model-pack total byte count mismatch")
    print(
        "Verified bundled %s %s: %s files, %s bytes"
        % (catalog["modelID"], catalog["version"], len(file_entries), actual_total)
    )


if __name__ == "__main__":
    main()
