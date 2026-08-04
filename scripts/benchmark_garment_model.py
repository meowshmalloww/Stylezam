#!/usr/bin/env python3
"""Benchmark Stylezam's garment segmenter without involving product search.

This script is intentionally separate from the iOS runtime. The application does
not ship PyTorch; the benchmark exists to qualify bundled on-device model packs
before they are included in the app.
"""

from __future__ import annotations

import argparse
import io
import json
import statistics
import time
from pathlib import Path
from typing import Any

import numpy as np
import psutil
import pyarrow.parquet as parquet
import torch
from PIL import Image, ImageDraw
from rfdetr import RFDETRSegSmall


FASHIONPEDIA_CLASSES = [
    "shirt, blouse",
    "top, t-shirt, sweatshirt",
    "sweater",
    "cardigan",
    "jacket",
    "vest",
    "pants",
    "shorts",
    "skirt",
    "coat",
    "dress",
    "jumpsuit",
    "cape",
    "glasses",
    "hat",
    "head covering or hair accessory",
    "tie",
    "glove",
    "watch",
    "belt",
    "leg warmer",
    "tights or stockings",
    "sock",
    "shoe",
    "bag or wallet",
    "scarf",
    "umbrella",
    "hood",
    "collar",
    "lapel",
    "epaulette",
    "sleeve",
    "pocket",
    "neckline",
    "buckle",
    "zipper",
    "applique",
    "bead",
    "bow",
    "flower",
    "fringe",
    "ribbon",
    "rivet",
    "ruffle",
    "sequin",
    "tassel",
]

# Only these Fashionpedia classes become separate Stylezam items. Garment-part
# predictions remain useful for future quality checks, but are not search crops.
SEARCHABLE_CLASS_IDS = set(range(27))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--parquet", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device", choices=("cpu", "mps"), default="cpu")
    parser.add_argument("--resolution", type=int, default=384)
    parser.add_argument("--threshold", type=float, default=0.35)
    parser.add_argument("--samples", type=int, default=8)
    parser.add_argument("--max-items", type=int, default=5)
    return parser.parse_args()


def iou(left: list[float], right: list[float]) -> float:
    x1 = max(left[0], right[0])
    y1 = max(left[1], right[1])
    x2 = min(left[2], right[2])
    y2 = min(left[3], right[3])
    intersection = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    if intersection == 0:
        return 0.0
    left_area = max(0.0, left[2] - left[0]) * max(0.0, left[3] - left[1])
    right_area = max(0.0, right[2] - right[0]) * max(0.0, right[3] - right[1])
    return intersection / (left_area + right_area - intersection)


def match_counts(
    predicted_boxes: list[list[float]],
    predicted_classes: list[int],
    truth_boxes: list[list[float]],
    truth_classes: list[int],
) -> tuple[int, int, int]:
    candidates: list[tuple[float, int, int]] = []
    for predicted_index, (box, class_id) in enumerate(
        zip(predicted_boxes, predicted_classes, strict=True)
    ):
        for truth_index, (truth_box, truth_class) in enumerate(
            zip(truth_boxes, truth_classes, strict=True)
        ):
            if class_id == truth_class:
                candidates.append((iou(box, truth_box), predicted_index, truth_index))

    matched_predictions: set[int] = set()
    matched_truth: set[int] = set()
    for score, predicted_index, truth_index in sorted(candidates, reverse=True):
        if score < 0.5:
            break
        if predicted_index in matched_predictions or truth_index in matched_truth:
            continue
        matched_predictions.add(predicted_index)
        matched_truth.add(truth_index)

    true_positives = len(matched_predictions)
    return (
        true_positives,
        len(predicted_boxes) - true_positives,
        len(truth_boxes) - true_positives,
    )


def draw_overlay(image: Image.Image, detections: Any) -> Image.Image:
    canvas = image.convert("RGBA")
    masks = getattr(detections, "mask", None)
    if masks is not None:
        tint = np.zeros((image.height, image.width, 4), dtype=np.uint8)
        for mask, class_id in zip(masks, detections.class_id, strict=True):
            if int(class_id) not in SEARCHABLE_CLASS_IDS:
                continue
            tint[np.asarray(mask, dtype=bool)] = (48, 101, 255, 74)
        canvas = Image.alpha_composite(canvas, Image.fromarray(tint, mode="RGBA"))

    drawing = ImageDraw.Draw(canvas)
    for box, class_id, confidence in zip(
        detections.xyxy,
        detections.class_id,
        detections.confidence,
        strict=True,
    ):
        class_id = int(class_id)
        if class_id not in SEARCHABLE_CLASS_IDS:
            continue
        coordinates = [float(value) for value in box]
        drawing.rectangle(coordinates, outline=(242, 244, 255, 255), width=3)
        label = f"{FASHIONPEDIA_CLASSES[class_id]} {float(confidence):.2f}"
        label_box = drawing.textbbox((coordinates[0], coordinates[1]), label)
        drawing.rectangle(label_box, fill=(20, 35, 78, 225))
        drawing.text((coordinates[0], coordinates[1]), label, fill="white")
    return canvas.convert("RGB")


def main() -> None:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    table = parquet.read_table(args.parquet, columns=["image", "objects"])
    if args.samples < 1:
        raise ValueError("--samples must be at least 1")
    sample_indices = np.linspace(0, table.num_rows - 1, args.samples, dtype=int)

    model = RFDETRSegSmall(
        pretrain_weights=args.checkpoint,
        num_classes=len(FASHIONPEDIA_CLASSES),
        device=args.device,
        resolution=args.resolution,
        trust_checkpoint=False,
    )
    dtype = torch.float16 if args.device == "mps" else torch.float32
    model.optimize_for_inference(compile=False, dtype=dtype, inplace=True)

    measurements: list[dict[str, Any]] = []
    total_true_positive = total_false_positive = total_false_negative = 0
    process = psutil.Process()

    for position, row_index in enumerate(sample_indices):
        row = table.slice(int(row_index), 1)
        image_value = row.column("image")[0].as_py()
        image = Image.open(io.BytesIO(image_value["bytes"])).convert("RGB")
        truth = row.column("objects")[0].as_py()

        started = time.perf_counter()
        detections = model.predict(image, threshold=args.threshold)
        elapsed = time.perf_counter() - started

        keep = [
            index
            for index, class_id in enumerate(detections.class_id)
            if int(class_id) in SEARCHABLE_CLASS_IDS
        ][: args.max_items]
        predicted_boxes = [
            [float(value) for value in detections.xyxy[index]] for index in keep
        ]
        predicted_classes = [int(detections.class_id[index]) for index in keep]
        truth_pairs = [
            (box, int(class_id))
            for box, class_id in zip(truth["bbox"], truth["category"], strict=True)
            if int(class_id) in SEARCHABLE_CLASS_IDS
        ]
        truth_boxes = [[float(value) for value in box] for box, _ in truth_pairs]
        truth_classes = [class_id for _, class_id in truth_pairs]
        true_positive, false_positive, false_negative = match_counts(
            predicted_boxes,
            predicted_classes,
            truth_boxes,
            truth_classes,
        )
        total_true_positive += true_positive
        total_false_positive += false_positive
        total_false_negative += false_negative

        overlay_path = args.output / f"sample-{position:02d}-row-{row_index}.jpg"
        draw_overlay(image, detections).save(overlay_path, quality=90)
        measurements.append(
            {
                "row": int(row_index),
                "seconds": round(elapsed, 4),
                "predicted_item_count": len(predicted_boxes),
                "truth_item_count": len(truth_boxes),
                "true_positive_at_iou_50": true_positive,
                "false_positive_at_iou_50": false_positive,
                "false_negative_at_iou_50": false_negative,
                "labels": [FASHIONPEDIA_CLASSES[value] for value in predicted_classes],
                "resident_memory_mb": round(process.memory_info().rss / 1_048_576, 1),
                "overlay": str(overlay_path),
            }
        )

    precision_denominator = total_true_positive + total_false_positive
    recall_denominator = total_true_positive + total_false_negative
    report = {
        "candidate": "resoa/garment-detector-seg",
        "architecture": "RF-DETR-Seg-Small",
        "checkpoint_sha256_required_for_shipping": True,
        "device": args.device,
        "resolution": args.resolution,
        "threshold": args.threshold,
        "max_items": args.max_items,
        "sample_count": len(measurements),
        "median_seconds": round(
            statistics.median(item["seconds"] for item in measurements), 4
        ),
        "p95_seconds": round(
            float(np.percentile([item["seconds"] for item in measurements], 95)), 4
        ),
        "precision_at_iou_50": round(
            total_true_positive / precision_denominator, 4
        )
        if precision_denominator
        else None,
        "recall_at_iou_50": round(total_true_positive / recall_denominator, 4)
        if recall_denominator
        else None,
        "samples": measurements,
    }
    report_path = args.output / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
