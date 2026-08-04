#!/usr/bin/env python3
"""Run Stylezam's Core ML garment pipeline and render auditable artifacts.

The Swift helper performs the same image normalization, class filtering,
confidence threshold, IoU suppression, and mask decoding as the iOS app. This
driver generates source overlays, transparent PNG crops, alpha diagnostics, and
optional Fashionpedia box/mask metrics without requiring PyTorch or coremltools.
"""

from __future__ import annotations

import argparse
import base64
import json
import statistics
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True, help="Source .mlpackage")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fashionpedia-annotations", type=Path)
    parser.add_argument("--threshold", type=float, default=0.35)
    parser.add_argument("--max-items", type=int, default=5)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument(
        "--metrics-only",
        action="store_true",
        help="Skip PNG crops and JPEG overlays for large benchmark runs",
    )
    return parser.parse_args()


def intersection_over_union(left: list[float], right: list[float]) -> float:
    intersection_width = max(0.0, min(left[2], right[2]) - max(left[0], right[0]))
    intersection_height = max(0.0, min(left[3], right[3]) - max(left[1], right[1]))
    intersection = intersection_width * intersection_height
    if intersection == 0:
        return 0.0
    left_area = max(0.0, left[2] - left[0]) * max(0.0, left[3] - left[1])
    right_area = max(0.0, right[2] - right[0]) * max(0.0, right[3] - right[1])
    return intersection / (left_area + right_area - intersection)


def foreground_pixels(mask: Image.Image) -> int:
    return mask.convert("L").histogram()[255]


def mask_iou(left: Image.Image, right: Image.Image) -> float:
    left_binary = left.convert("L").point(lambda value: 255 if value >= 128 else 0).convert("1")
    right_binary = right.convert("1")
    intersection = ImageChops.logical_and(left_binary, right_binary)
    union = ImageChops.logical_or(left_binary, right_binary)
    union_pixels = foreground_pixels(union)
    return foreground_pixels(intersection) / union_pixels if union_pixels else 0.0


def normalized_image(path: Path) -> Image.Image:
    image = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    if max(image.size) > 1600:
        image.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
    return image


def prediction_box(prediction: dict[str, Any], size: tuple[int, int]) -> list[float]:
    box = prediction["box"]
    return [
        box["x"] * size[0],
        box["y"] * size[1],
        (box["x"] + box["width"]) * size[0],
        (box["y"] + box["height"]) * size[1],
    ]


def prediction_mask(prediction: dict[str, Any], size: tuple[int, int]) -> Image.Image:
    mask_bytes = base64.b64decode(prediction["maskBase64"])
    mask = Image.frombytes(
        "L",
        (prediction["maskWidth"], prediction["maskHeight"]),
        mask_bytes,
    )
    return mask.resize(size, Image.Resampling.BILINEAR)


def ground_truth_mask(annotation: dict[str, Any], size: tuple[int, int]) -> Image.Image:
    segmentation = annotation.get("segmentation", [])
    if isinstance(segmentation, list):
        mask = Image.new("1", size, 0)
        drawing = ImageDraw.Draw(mask)
        for polygon in segmentation:
            if len(polygon) % 2:
                raise ValueError("Fashionpedia polygon contains an unmatched coordinate")
            points = list(zip(polygon[0::2], polygon[1::2]))
            if len(points) >= 3:
                drawing.polygon(points, fill=1)
        return mask
    if not isinstance(segmentation, dict):
        raise ValueError("Fashionpedia segmentation is neither polygons nor COCO RLE")

    encoded_counts = segmentation.get("counts")
    if isinstance(encoded_counts, list):
        counts = [int(value) for value in encoded_counts]
    elif isinstance(encoded_counts, (str, bytes)):
        text = encoded_counts.decode("ascii") if isinstance(encoded_counts, bytes) else encoded_counts
        counts = []
        position = 0
        while position < len(text):
            value = 0
            shift = 0
            more = True
            while more:
                code = ord(text[position]) - 48
                position += 1
                value |= (code & 0x1F) << (5 * shift)
                more = bool(code & 0x20)
                if not more and code & 0x10:
                    value |= -1 << (5 * (shift + 1))
                shift += 1
            if len(counts) > 2:
                value += counts[-2]
            counts.append(value)
    else:
        raise ValueError("Fashionpedia COCO RLE counts are missing")

    encoded_size = segmentation.get("size", [size[1], size[0]])
    height, width = int(encoded_size[0]), int(encoded_size[1])
    pixels = bytearray(width * height)
    offset = 0
    foreground = False
    for count in counts:
        next_offset = offset + count
        if foreground and count > 0:
            pixels[offset:next_offset] = b"\xff" * count
        offset = next_offset
        foreground = not foreground
    if offset != len(pixels):
        raise ValueError("Fashionpedia COCO RLE length does not match its image size")
    mask = Image.frombytes("L", (height, width), bytes(pixels)).transpose(
        Image.Transpose.TRANSPOSE
    )
    if mask.size != size:
        mask = mask.resize(size, Image.Resampling.NEAREST)
    return mask.convert("1")


def render_crop(
    image: Image.Image,
    mask: Image.Image,
    box: list[float],
    output: Path,
) -> dict[str, Any]:
    padding = max(box[2] - box[0], box[3] - box[1]) * 0.025
    bounds = (
        max(0, int(box[0] - padding)),
        max(0, int(box[1] - padding)),
        min(image.width, int(box[2] + padding + 0.999)),
        min(image.height, int(box[3] + padding + 0.999)),
    )
    crop = image.crop(bounds)
    alpha = mask.crop(bounds)
    scale = min(1.0, 1024 / max(crop.size))
    target = (
        max(1, round(crop.width * scale)),
        max(1, round(crop.height * scale)),
    )
    if target != crop.size:
        crop = crop.resize(target, Image.Resampling.LANCZOS)
        alpha = alpha.resize(target, Image.Resampling.BILINEAR)
    rgba = crop.convert("RGBA")
    rgba.putalpha(alpha)
    rgba.save(output)
    histogram = alpha.histogram()
    total = alpha.width * alpha.height
    opaque = histogram[255]
    transparent = histogram[0]
    partial = total - opaque - transparent
    return {
        "path": str(output),
        "width": alpha.width,
        "height": alpha.height,
        "bytes": output.stat().st_size,
        "opaque_pixels": opaque,
        "transparent_pixels": transparent,
        "partial_alpha_pixels": partial,
        "foreground_fraction": round((opaque + partial) / total, 4),
        "has_transparency": transparent > 0,
        "has_foreground": opaque + partial > 0,
    }


def load_fashionpedia(path: Path | None) -> dict[int, list[dict[str, Any]]]:
    if path is None:
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    selected: dict[int, list[dict[str, Any]]] = {}
    for annotation in payload["annotations"]:
        if int(annotation["category_id"]) < 27:
            selected.setdefault(int(annotation["image_id"]), []).append(annotation)
    return selected


def image_id_from_path(path: Path) -> int | None:
    marker = "-image-"
    if marker not in path.stem:
        return None
    try:
        return int(path.stem.split(marker, 1)[1])
    except ValueError:
        return None


def main() -> None:
    args = parse_args()
    if not 0 <= args.threshold <= 1:
        raise ValueError("--threshold must be between 0 and 1")
    if not 1 <= args.max_items <= 12 or not 1 <= args.runs <= 20:
        raise ValueError("--max-items or --runs is outside the supported range")
    input_paths = [path.resolve() for value in args.input for path in sorted(value.glob("*"))]
    input_paths = [
        path for path in input_paths if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic"}
    ]
    if not input_paths:
        raise ValueError("No test images were found")
    args.output.mkdir(parents=True, exist_ok=True)
    helper = Path(__file__).with_name("coreml_garment_inference.swift")
    annotations = load_fashionpedia(args.fashionpedia_annotations)
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    class_names = manifest["classNames"]

    with tempfile.TemporaryDirectory(prefix="stylezam-coreml-verifier-") as temporary:
        temporary_path = Path(temporary)
        compiled_model_root = temporary_path / "model"
        compiled_model_root.mkdir()
        subprocess.run(
            ["xcrun", "coremlc", "compile", str(args.model), str(compiled_model_root)],
            check=True,
        )
        compiled_models = list(compiled_model_root.glob("*.mlmodelc"))
        if len(compiled_models) != 1:
            raise RuntimeError("Core ML compilation did not produce exactly one model")
        runner = temporary_path / "coreml-garment-inference"
        subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(helper),
                "-framework",
                "CoreML",
                "-framework",
                "ImageIO",
                "-o",
                str(runner),
            ],
            check=True,
        )
        raw_report = temporary_path / "raw.json"
        command = [
            str(runner),
            "--model",
            str(compiled_models[0]),
            "--manifest",
            str(args.manifest),
            "--output",
            str(raw_report),
            "--threshold",
            str(args.threshold),
            "--max-items",
            str(args.max_items),
            "--runs",
            str(args.runs),
        ]
        for path in input_paths:
            command.extend(["--image", str(path)])
        subprocess.run(command, check=True)
        raw = json.loads(raw_report.read_text(encoding="utf-8"))

    total_true_positive = total_false_positive = total_false_negative = 0
    matched_mask_ious: list[float] = []
    all_inference_timings: list[float] = []
    crop_checks: list[dict[str, Any]] = []
    image_reports: list[dict[str, Any]] = []
    all_confidences: list[float] = []
    category_stats: dict[int, dict[str, Any]] = {
        category_id: {
            "category_id": category_id,
            "label": class_names[category_id],
            "ground_truth": 0,
            "predictions": 0,
            "matches": 0,
            "confidences": [],
            "mask_ious": [],
        }
        for category_id in range(min(27, len(class_names)))
    }

    for raw_image in raw["images"]:
        path = Path(raw_image["path"])
        image = normalized_image(path)
        output_directory = args.output / path.stem
        if not args.metrics_only:
            output_directory.mkdir(exist_ok=True)
        overlay = image.convert("RGBA") if not args.metrics_only else None
        tint = Image.new("RGBA", image.size, (48, 101, 255, 0)) if overlay else None
        tint_alpha = Image.new("L", image.size, 0) if overlay else None
        predictions: list[dict[str, Any]] = []

        for index, prediction in enumerate(raw_image["detections"], start=1):
            box = prediction_box(prediction, image.size)
            mask = prediction_mask(prediction, image.size)
            if tint_alpha is not None:
                tint_alpha = ImageChops.lighter(
                    tint_alpha,
                    mask.point(lambda value: round(value * 0.30)),
                )
            crop = None
            if not args.metrics_only:
                crop_path = (
                    output_directory
                    / f"crop-{index:02d}-{prediction['categoryID']:02d}.png"
                )
                crop = render_crop(image, mask, box, crop_path)
                crop_checks.append(crop)
            category_id = int(prediction["categoryID"])
            confidence = float(prediction["confidence"])
            all_confidences.append(confidence)
            if category_id in category_stats:
                category_stats[category_id]["predictions"] += 1
                category_stats[category_id]["confidences"].append(confidence)
            predictions.append(
                {
                    "category_id": category_id,
                    "label": prediction["label"],
                    "confidence": round(confidence, 4),
                    "box_xyxy": [round(value, 2) for value in box],
                    "mask_pixels": foreground_pixels(mask),
                    "crop": crop,
                    "_mask": mask,
                }
            )

        overlay_path = None
        if overlay is not None and tint is not None and tint_alpha is not None:
            tint.putalpha(tint_alpha)
            overlay = Image.alpha_composite(overlay, tint)
            overlay_drawing = ImageDraw.Draw(overlay)
            font = ImageFont.load_default()
            for prediction in predictions:
                box = prediction["box_xyxy"]
                label = f"{prediction['label']} {prediction['confidence']:.2f}"
                overlay_drawing.rectangle(box, outline=(245, 247, 255, 255), width=3)
                text_box = overlay_drawing.textbbox((box[0], box[1]), label, font=font)
                overlay_drawing.rectangle(text_box, fill=(20, 35, 78, 230))
                overlay_drawing.text((box[0], box[1]), label, fill="white", font=font)
            overlay_path = output_directory / "overlay.jpg"
            overlay.convert("RGB").save(overlay_path, quality=94)

        image_id = image_id_from_path(path)
        truth = annotations.get(image_id, []) if image_id is not None else []
        for annotation in truth:
            category_id = int(annotation["category_id"])
            if category_id in category_stats:
                category_stats[category_id]["ground_truth"] += 1
        candidates: list[tuple[float, int, int]] = []
        for prediction_index, prediction in enumerate(predictions):
            for truth_index, annotation in enumerate(truth):
                if prediction["category_id"] != int(annotation["category_id"]):
                    continue
                x, y, width, height = annotation["bbox"]
                truth_box = [x, y, x + width, y + height]
                candidates.append(
                    (
                        intersection_over_union(prediction["box_xyxy"], truth_box),
                        prediction_index,
                        truth_index,
                    )
                )
        used_predictions: set[int] = set()
        used_truth: set[int] = set()
        matches: list[dict[str, Any]] = []
        for box_score, prediction_index, truth_index in sorted(candidates, reverse=True):
            if box_score < 0.5:
                break
            if prediction_index in used_predictions or truth_index in used_truth:
                continue
            used_predictions.add(prediction_index)
            used_truth.add(truth_index)
            truth_mask = ground_truth_mask(truth[truth_index], image.size)
            score = mask_iou(predictions[prediction_index]["_mask"], truth_mask)
            matched_mask_ious.append(score)
            category_id = predictions[prediction_index]["category_id"]
            if category_id in category_stats:
                category_stats[category_id]["matches"] += 1
                category_stats[category_id]["mask_ious"].append(score)
            matches.append(
                {
                    "label": predictions[prediction_index]["label"],
                    "box_iou": round(box_score, 4),
                    "mask_iou": round(score, 4),
                }
            )
        true_positive = len(matches)
        false_positive = len(predictions) - true_positive
        false_negative = len(truth) - true_positive
        total_true_positive += true_positive
        total_false_positive += false_positive
        total_false_negative += false_negative
        timings = [float(value) for value in raw_image["inferenceMilliseconds"]]
        all_inference_timings.extend(timings)
        for prediction in predictions:
            prediction.pop("_mask")
        image_reports.append(
            {
                "input": str(path),
                "image_id": image_id,
                "width": image.width,
                "height": image.height,
                "preprocessing_ms": round(raw_image["preprocessingMilliseconds"], 2),
                "inference_ms": [round(value, 2) for value in timings],
                "predictions": predictions,
                "ground_truth_count": len(truth) if annotations else None,
                "true_positive_at_box_iou_50": true_positive if annotations else None,
                "false_positive_at_box_iou_50": false_positive if annotations else None,
                "false_negative_at_box_iou_50": false_negative if annotations else None,
                "matches": matches,
                "overlay": str(overlay_path) if overlay_path else None,
            }
        )

    precision_denominator = total_true_positive + total_false_positive
    recall_denominator = total_true_positive + total_false_negative
    per_category = []
    for category in category_stats.values():
        confidences = category.pop("confidences")
        mask_ious = category.pop("mask_ious")
        category["precision_at_box_iou_50"] = (
            round(category["matches"] / category["predictions"], 4)
            if category["predictions"]
            else None
        )
        category["recall_at_box_iou_50"] = (
            round(category["matches"] / category["ground_truth"], 4)
            if category["ground_truth"]
            else None
        )
        category["median_confidence"] = (
            round(statistics.median(confidences), 4) if confidences else None
        )
        category["mean_mask_iou_for_box_matches"] = (
            round(statistics.mean(mask_ious), 4) if mask_ious else None
        )
        if category["ground_truth"] or category["predictions"]:
            per_category.append(category)
    report = {
        "model_id": raw["modelID"],
        "model_version": raw["modelVersion"],
        "input_resolution": raw["inputResolution"],
        "threshold": raw["threshold"],
        "max_items": raw["maxItems"],
        "image_count": len(image_reports),
        "detection_count": sum(len(image["predictions"]) for image in image_reports),
        "median_inference_ms": round(statistics.median(all_inference_timings), 2),
        "p95_inference_ms": round(
            sorted(all_inference_timings)[max(0, round(0.95 * len(all_inference_timings)) - 1)],
            2,
        ),
        "precision_at_box_iou_50": round(total_true_positive / precision_denominator, 4)
        if annotations and precision_denominator
        else None,
        "recall_at_box_iou_50": round(total_true_positive / recall_denominator, 4)
        if annotations and recall_denominator
        else None,
        "mean_mask_iou_for_box_matches": round(statistics.mean(matched_mask_ious), 4)
        if matched_mask_ious
        else None,
        "confidence": {
            "minimum": round(min(all_confidences), 4) if all_confidences else None,
            "median": round(statistics.median(all_confidences), 4)
            if all_confidences
            else None,
            "maximum": round(max(all_confidences), 4) if all_confidences else None,
        },
        "transparent_crop_checks": {
            "all_have_foreground": all(item["has_foreground"] for item in crop_checks),
            "all_have_transparency": all(item["has_transparency"] for item in crop_checks),
            "total": len(crop_checks),
        },
        "per_category": per_category,
        "images": image_reports,
    }
    report_path = args.output / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                key: value
                for key, value in report.items()
                if key not in {"images", "per_category"}
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
