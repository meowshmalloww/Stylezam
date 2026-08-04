#!/usr/bin/env python3
"""Verify a converted garment model using the same post-processing as iOS."""

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import coremltools as coreml
import numpy as np
from PIL import Image, ImageDraw

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--classes", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--threshold", type=float, default=0.35)
    parser.add_argument("--max-items", type=int, default=5)
    parser.add_argument("--runs", type=int, default=6)
    return parser.parse_args()


def sigmoid(values: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-values))


def intersection_over_union(left: list[float], right: list[float]) -> float:
    intersection_width = max(0.0, min(left[2], right[2]) - max(left[0], right[0]))
    intersection_height = max(0.0, min(left[3], right[3]) - max(left[1], right[1]))
    intersection = intersection_width * intersection_height
    if intersection == 0:
        return 0.0
    left_area = (left[2] - left[0]) * (left[3] - left[1])
    right_area = (right[2] - right[0]) * (right[3] - right[1])
    return intersection / (left_area + right_area - intersection)


def main() -> None:
    args = parse_args()
    class_names = json.loads(args.classes.read_text(encoding="utf-8"))
    if not isinstance(class_names, list) or len(class_names) != 46:
        raise ValueError("Fashionpedia class file must contain exactly 46 labels")
    searchable_class_ids = range(27)
    model = coreml.models.MLModel(str(args.model), compute_units=coreml.ComputeUnit.ALL)
    specification = model.get_spec().description
    input_description = specification.input[0]
    input_name = input_description.name
    input_shape = tuple(input_description.type.multiArrayType.shape)
    if len(input_shape) != 4 or input_shape[0] != 1 or input_shape[1] != 3:
        raise ValueError(f"Unexpected model input shape: {input_shape}")
    resolution = int(input_shape[2])

    image = Image.open(args.image).convert("RGB")
    resized = image.resize((resolution, resolution), Image.Resampling.BILINEAR)
    tensor = np.asarray(resized, dtype=np.float32) / 255.0
    tensor = (tensor - np.asarray([0.485, 0.456, 0.406], dtype=np.float32)) / np.asarray(
        [0.229, 0.224, 0.225], dtype=np.float32
    )
    tensor = np.transpose(tensor, (2, 0, 1))[None, ...]

    timings: list[float] = []
    result: dict[str, np.ndarray] = {}
    for _ in range(args.runs):
        started = time.perf_counter()
        result = model.predict({input_name: tensor})
        timings.append(time.perf_counter() - started)

    boxes = next(value for value in result.values() if value.shape[-1] == 4)
    logits = next(value for value in result.values() if value.ndim == 3 and value.shape[-1] > 4)
    masks = next(value for value in result.values() if value.ndim == 4 and value.shape[1] == boxes.shape[1])
    probabilities = sigmoid(logits[0])
    candidates: list[dict[str, object]] = []
    for query_index in range(probabilities.shape[0]):
        searchable = probabilities[query_index, searchable_class_ids]
        class_id = int(np.argmax(searchable))
        confidence = float(searchable[class_id])
        if confidence < args.threshold:
            continue
        center_x, center_y, width, height = [
            float(value) for value in boxes[0, query_index]
        ]
        normalized_box = [
            max(0.0, center_x - width / 2.0),
            max(0.0, center_y - height / 2.0),
            min(1.0, center_x + width / 2.0),
            min(1.0, center_y + height / 2.0),
        ]
        if (
            normalized_box[2] - normalized_box[0] < 0.025
            or normalized_box[3] - normalized_box[1] < 0.025
        ):
            continue
        candidates.append(
            {
                "confidence": confidence,
                "query": query_index,
                "class_id": class_id,
                "normalized_box": normalized_box,
            }
        )
    candidates.sort(key=lambda candidate: float(candidate["confidence"]), reverse=True)

    selected: list[dict[str, object]] = []
    for candidate in candidates:
        duplicate = any(
            previous["class_id"] == candidate["class_id"]
            and intersection_over_union(
                previous["normalized_box"], candidate["normalized_box"]
            )
            > 0.74
            for previous in selected
        )
        if not duplicate:
            selected.append(candidate)
        if len(selected) == args.max_items:
            break

    overlay = image.convert("RGBA")
    tint = np.zeros((image.height, image.width, 4), dtype=np.uint8)
    detections: list[dict[str, object]] = []
    for candidate in selected:
        confidence = float(candidate["confidence"])
        query_index = int(candidate["query"])
        class_id = int(candidate["class_id"])
        normalized_box = candidate["normalized_box"]
        coordinates = [
            normalized_box[0] * image.width,
            normalized_box[1] * image.height,
            normalized_box[2] * image.width,
            normalized_box[3] * image.height,
        ]
        mask_logits = masks[0, query_index].astype(np.float32)
        mask_image = Image.fromarray(mask_logits, mode="F").resize(
            image.size, Image.Resampling.BILINEAR
        )
        mask = np.asarray(mask_image) > 0.0
        tint[mask] = (48, 101, 255, 74)
        detections.append(
            {
                "label": class_names[class_id],
                "confidence": round(confidence, 4),
                "box": [round(value, 2) for value in coordinates],
                "query": query_index,
            }
        )

    overlay = Image.alpha_composite(overlay, Image.fromarray(tint, mode="RGBA"))
    drawing = ImageDraw.Draw(overlay)
    for detection in detections:
        coordinates = detection["box"]
        label = f"{detection['label']} {detection['confidence']:.2f}"
        drawing.rectangle(coordinates, outline=(242, 244, 255, 255), width=3)
        label_box = drawing.textbbox((coordinates[0], coordinates[1]), label)
        drawing.rectangle(label_box, fill=(20, 35, 78, 225))
        drawing.text((coordinates[0], coordinates[1]), label, fill="white")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    overlay.convert("RGB").save(args.output, quality=92)
    report = {
        "model": str(args.model),
        "input": str(args.image),
        "resolution": resolution,
        "cold_seconds": round(timings[0], 4),
        "warm_median_seconds": round(statistics.median(timings[1:]), 4),
        "warm_p95_seconds": round(float(np.percentile(timings[1:], 95)), 4),
        "detections": detections,
        "overlay": str(args.output),
    }
    rendered_report = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered_report, encoding="utf-8")
    print(rendered_report, end="")


if __name__ == "__main__":
    main()
