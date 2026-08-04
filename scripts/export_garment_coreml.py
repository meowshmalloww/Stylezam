#!/usr/bin/env python3
"""Export the qualified garment checkpoint with RF-DETR's native Core ML path.

The exporter intentionally keeps RF-DETR's native MLMultiArray input. Stylezam
performs the documented ImageNet normalization in Swift, avoiding an unverified
custom graph rewrite between the qualified checkpoint and the shipped model.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from rfdetr import RFDETRSegSmall


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--resolution", type=int, default=384)
    parser.add_argument("--classes", type=int, default=46)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.checkpoint.is_file():
        raise FileNotFoundError(args.checkpoint)
    if args.resolution % 24:
        raise ValueError("Resolution must be divisible by 24 for this RF-DETR variant")

    detector = RFDETRSegSmall(
        pretrain_weights=args.checkpoint,
        num_classes=args.classes,
        device="cpu",
        resolution=args.resolution,
        trust_checkpoint=False,
    )
    exported = detector.export(
        output_dir=str(args.output_dir),
        format="coreml",
        shape=(args.resolution, args.resolution),
        coreml_precision="float16",
        verbose=True,
    )
    print(exported)


if __name__ == "__main__":
    main()
