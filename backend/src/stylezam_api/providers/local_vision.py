from __future__ import annotations

import asyncio
import io
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List, Optional, Sequence, Tuple

import httpx
from PIL import Image

from ..config import Settings
from ..errors import ProviderConfigurationError, ProviderUpstreamError
from ..schemas import BoundingBox, DetectedItem
from ..storage import MediaStorage, StoredMedia
from .base import ProviderProduct


GARMENT_LABELS = [
    "dress",
    "jacket",
    "coat",
    "shirt",
    "blouse",
    "sweater",
    "hoodie",
    "top",
    "pants",
    "jeans",
    "skirt",
    "shorts",
    "shoes",
    "handbag",
    "hat",
    "scarf",
    "necklace",
]


@dataclass
class SegmentationResult:
    items: List[DetectedItem]
    primary_crop: Optional[StoredMedia]


class LocalGarmentVision:
    id = "grounded-sam2"
    name = "Grounding DINO + SAM2"

    def __init__(self, settings: Settings, storage: MediaStorage) -> None:
        self.settings = settings
        self.storage = storage
        self._detector_processor: Any = None
        self._detector: Any = None
        self._sam_processor: Any = None
        self._sam: Any = None
        self._device: Optional[str] = None

    @property
    def configured(self) -> bool:
        return self.settings.local_vision_enabled

    async def segment(self, image_path: Path) -> SegmentationResult:
        return await asyncio.to_thread(self._segment_sync, image_path)

    def _load(self) -> None:
        if self._detector is not None:
            return
        try:
            import torch
            from transformers import (
                AutoModelForZeroShotObjectDetection,
                AutoProcessor,
                Sam2Model,
                Sam2Processor,
            )
        except ImportError as exc:
            raise ProviderConfigurationError(
                "Local garment vision is enabled, but its optional dependencies are not installed.",
                ["pip install -e '.[vision]'"],
            ) from exc
        if torch.cuda.is_available():
            device = "cuda"
        elif getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
            device = "mps"
        else:
            device = "cpu"
        self._device = device
        self._detector_processor = AutoProcessor.from_pretrained(self.settings.grounding_dino_model)
        self._detector = AutoModelForZeroShotObjectDetection.from_pretrained(
            self.settings.grounding_dino_model
        ).to(device)
        self._sam_processor = Sam2Processor.from_pretrained(self.settings.sam2_model)
        self._sam = Sam2Model.from_pretrained(self.settings.sam2_model).to(device)

    def _segment_sync(self, image_path: Path) -> SegmentationResult:
        self._load()
        try:
            import torch

            image = Image.open(image_path).convert("RGB")
            labels = [GARMENT_LABELS]
            inputs = self._detector_processor(
                images=image,
                text=labels,
                return_tensors="pt",
            ).to(self._device)
            with torch.no_grad():
                outputs = self._detector(**inputs)
            processed = self._detector_processor.post_process_grounded_object_detection(
                outputs,
                inputs.input_ids,
                threshold=0.28,
                text_threshold=0.24,
                target_sizes=[(image.height, image.width)],
            )[0]
            boxes = processed.get("boxes", [])
            scores = processed.get("scores", [])
            text_labels = processed.get("text_labels") or processed.get("labels") or []
            detections: List[Tuple[List[float], float, str]] = []
            for box_value, score_value, label_value in zip(boxes, scores, text_labels):
                box = [float(value) for value in box_value.tolist()]
                score = float(score_value.item())
                detections.append((box, score, str(label_value)))
            detections.sort(
                key=lambda entry: entry[1]
                * max(entry[0][2] - entry[0][0], 1)
                * max(entry[0][3] - entry[0][1], 1),
                reverse=True,
            )
            detections = detections[:8]
            items = [self._detected_item(entry, image.size) for entry in detections]
            primary = self._masked_crop(image, detections[0][0]) if detections else None
            return SegmentationResult(items=items, primary_crop=primary)
        except ProviderConfigurationError:
            raise
        except Exception as exc:
            raise ProviderUpstreamError(
                "grounded-sam2", "Local garment segmentation failed."
            ) from exc

    def _masked_crop(self, image: Image.Image, box: Sequence[float]) -> StoredMedia:
        try:
            import torch

            inputs = self._sam_processor(
                images=image,
                input_boxes=[[list(box)]],
                return_tensors="pt",
            ).to(self._device)
            with torch.no_grad():
                outputs = self._sam(**inputs, multimask_output=True)
            masks = self._sam_processor.post_process_masks(
                outputs.pred_masks.cpu(), inputs["original_sizes"]
            )[0]
            object_masks = masks[0]
            best_index = int(outputs.iou_scores[0, 0].argmax().item())
            mask = object_masks[best_index].numpy()
            mask_image = Image.fromarray((mask * 255).astype("uint8"), mode="L")
            white = Image.new("RGB", image.size, "white")
            composed = Image.composite(image, white, mask_image)
            x0, y0, x1, y1 = self._padded_box(box, image.size)
            return self.storage.save_pil_image(composed.crop((x0, y0, x1, y1)), prefix="garment")
        except Exception:
            x0, y0, x1, y1 = self._padded_box(box, image.size)
            return self.storage.save_pil_image(image.crop((x0, y0, x1, y1)), prefix="garment")

    @staticmethod
    def _padded_box(box: Sequence[float], size: Tuple[int, int]) -> Tuple[int, int, int, int]:
        width, height = size
        x0, y0, x1, y1 = box
        pad_x = (x1 - x0) * 0.08
        pad_y = (y1 - y0) * 0.08
        return (
            max(0, int(x0 - pad_x)),
            max(0, int(y0 - pad_y)),
            min(width, int(x1 + pad_x)),
            min(height, int(y1 + pad_y)),
        )

    @staticmethod
    def _detected_item(
        detection: Tuple[List[float], float, str], size: Tuple[int, int]
    ) -> DetectedItem:
        box, score, label = detection
        width, height = size
        x0, y0, x1, y1 = box
        return DetectedItem(
            label=label,
            confidence=max(0.0, min(score, 1.0)),
            box=BoundingBox(
                x=max(0.0, x0 / width),
                y=max(0.0, y0 / height),
                width=min(1.0, max(0.0001, (x1 - x0) / width)),
                height=min(1.0, max(0.0001, (y1 - y0) / height)),
            ),
        )


class CLIPReranker:
    id = "clip"
    name = "CLIP visual reranking"

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.settings = settings
        self.client = client
        self._processor: Any = None
        self._model: Any = None
        self._device: Optional[str] = None

    @property
    def configured(self) -> bool:
        return self.settings.local_vision_enabled

    async def scores(
        self, query_image: Path, products: Sequence[ProviderProduct]
    ) -> List[Optional[float]]:
        candidates = list(products[:24])
        downloaded = await asyncio.gather(
            *(self._download(product.image_url) for product in candidates),
            return_exceptions=True,
        )
        return await asyncio.to_thread(self._score_sync, query_image, candidates, downloaded)

    async def _download(self, url: Optional[str]) -> Optional[bytes]:
        if not url:
            return None
        try:
            response = await self.client.get(url, timeout=12, follow_redirects=True)
            response.raise_for_status()
            if len(response.content) > 8 * 1024 * 1024:
                return None
            return response.content
        except httpx.HTTPError:
            return None

    def _load(self) -> None:
        if self._model is not None:
            return
        try:
            import torch
            from transformers import AutoProcessor, CLIPModel
        except ImportError as exc:
            raise ProviderConfigurationError(
                "CLIP reranking is enabled, but its optional dependencies are not installed.",
                ["pip install -e '.[vision]'"],
            ) from exc
        if torch.cuda.is_available():
            device = "cuda"
        elif getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
            device = "mps"
        else:
            device = "cpu"
        self._device = device
        self._processor = AutoProcessor.from_pretrained(self.settings.clip_model)
        self._model = CLIPModel.from_pretrained(self.settings.clip_model).to(device)

    def _score_sync(
        self,
        query_image: Path,
        products: Sequence[ProviderProduct],
        downloaded: Sequence[Any],
    ) -> List[Optional[float]]:
        self._load()
        try:
            import torch
            import torch.nn.functional as functional

            query = Image.open(query_image).convert("RGB")
            valid_images: List[Image.Image] = [query]
            valid_indexes: List[int] = []
            for index, raw in enumerate(downloaded):
                if not isinstance(raw, bytes):
                    continue
                try:
                    valid_images.append(Image.open(io.BytesIO(raw)).convert("RGB"))
                    valid_indexes.append(index)
                except Exception:
                    continue
            result: List[Optional[float]] = [None] * len(products)
            if not valid_indexes:
                return result
            inputs = self._processor(images=valid_images, return_tensors="pt").to(self._device)
            with torch.no_grad():
                features = self._model.get_image_features(**inputs)
            features = functional.normalize(features, dim=-1)
            similarities = features[1:] @ features[0]
            for index, similarity in zip(valid_indexes, similarities.tolist()):
                result[index] = max(0.0, min(1.0, (float(similarity) + 1.0) / 2.0))
            return result
        except ProviderConfigurationError:
            raise
        except Exception as exc:
            raise ProviderUpstreamError("clip", "Local visual reranking failed.") from exc

