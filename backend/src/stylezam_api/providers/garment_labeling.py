from __future__ import annotations

import base64
import asyncio
import json
from pathlib import Path
from typing import Any, Dict, List, Sequence

import httpx
from pydantic import SecretStr, ValidationError

from ..config import Settings
from ..errors import ProviderConfigurationError, ProviderUpstreamError
from ..schemas import GarmentInputMetadata, GarmentLabel


GARMENT_CATEGORIES = [
    "shirt",
    "top",
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
    "shoes",
    "bag",
    "hat",
    "glasses",
    "scarf",
    "tie",
    "gloves",
    "socks",
    "watch",
    "ring",
    "bracelet",
    "necklace",
    "earrings",
    "belt",
    "other accessory",
]


LABEL_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "itemID": {"type": "string"},
                    "accepted": {"type": "boolean"},
                    "category": {
                        "anyOf": [
                            {"type": "string", "enum": GARMENT_CATEGORIES},
                            {"type": "null"},
                        ]
                    },
                    "displayName": {"anyOf": [{"type": "string"}, {"type": "null"}]},
                    "brand": {"anyOf": [{"type": "string"}, {"type": "null"}]},
                    "colors": {"type": "array", "items": {"type": "string"}},
                    "materials": {"type": "array", "items": {"type": "string"}},
                    "patterns": {"type": "array", "items": {"type": "string"}},
                    "details": {"type": "array", "items": {"type": "string"}},
                    "visibleText": {"type": "array", "items": {"type": "string"}},
                },
                "required": [
                    "itemID",
                    "accepted",
                    "category",
                    "displayName",
                    "brand",
                    "colors",
                    "materials",
                    "patterns",
                    "details",
                    "visibleText",
                ],
                "additionalProperties": False,
            },
        }
    },
    "required": ["items"],
    "additionalProperties": False,
}


def _secret_value(secret: SecretStr | None) -> str | None:
    if secret is None:
        return None
    value = secret.get_secret_value().strip()
    return value or None


def _data_url(path: Path) -> str:
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    media_type = "image/png" if path.suffix.lower() == ".png" else "image/jpeg"
    return "data:%s;base64,%s" % (media_type, encoded)


def _prompt(items: Sequence[GarmentInputMetadata]) -> str:
    item_summary = [
        {
            "itemID": item.item_id,
            "detectorLabel": item.local_label,
            "detectorConfidence": round(item.local_confidence, 3),
        }
        for item in items
    ]
    return (
        "You are the validation and labeling stage after an on-device fashion instance "
        "segmenter. The following images are transparent or rectangular crops in the exact "
        "same order as the item metadata. For every itemID, decide whether the crop contains a "
        "distinct piece of clothing, footwear, bag, hat, watch, or jewelry. Reject body parts, "
        "background, duplicate fragments, and crops too unclear to label. Use only visible facts. "
        "Never infer a brand unless readable text or an unmistakable logo is visible. displayName "
        "must be a natural two-to-six-word fashion label, not a shopping query. Return every "
        "itemID exactly once and return JSON matching this schema. Metadata: "
        + json.dumps(item_summary, separators=(",", ":"))
        + " Schema: "
        + json.dumps(LABEL_SCHEMA, separators=(",", ":"))
    )


class FireworksGarmentLabeler:
    id = "fireworks-garment-labeler"
    name = "Fireworks Qwen3.7 Plus"

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.settings = settings
        self.client = client
        self._semaphore = asyncio.Semaphore(settings.garment_analysis_concurrency)

    @property
    def configured(self) -> bool:
        return _secret_value(self.settings.fireworks_api_key) is not None

    async def label(
        self,
        image_paths: Sequence[Path],
        items: Sequence[GarmentInputMetadata],
    ) -> List[GarmentLabel]:
        api_key = _secret_value(self.settings.fireworks_api_key)
        if api_key is None:
            raise ProviderConfigurationError(
                "Fireworks garment labeling is not configured.",
                ["STYLEZAM_FIREWORKS_API_KEY"],
            )
        if len(image_paths) != len(items):
            raise ValueError("image and metadata counts must match")

        content: List[Dict[str, Any]] = [{"type": "text", "text": _prompt(items)}]
        for index, (image_path, item) in enumerate(zip(image_paths, items)):
            content.append(
                {
                    "type": "text",
                    "text": "Crop %s has itemID %s." % (index + 1, item.item_id),
                }
            )
            content.append(
                {
                    "type": "image_url",
                    "image_url": {"url": _data_url(image_path)},
                }
            )

        try:
            async with self._semaphore:
                response = await self.client.post(
                    "%s/chat/completions" % self.settings.fireworks_base_url.rstrip("/"),
                    headers={"Authorization": "Bearer %s" % api_key},
                    json={
                        "model": self.settings.fireworks_vision_model,
                        "messages": [{"role": "user", "content": content}],
                        "response_format": {
                            "type": "json_schema",
                            "json_schema": {
                                "name": "stylezam_garment_labels",
                                "schema": LABEL_SCHEMA,
                            },
                        },
                        "temperature": 0,
                        "reasoning_effort": "none",
                        "max_tokens": 1_600,
                    },
                    timeout=self.settings.job_timeout_seconds,
                )
            response.raise_for_status()
            raw_content = response.json()["choices"][0]["message"]["content"]
            if not isinstance(raw_content, str):
                raise TypeError("message content was not text")
            parsed = json.loads(raw_content.removeprefix("```json").removesuffix("```").strip())
            labels = [GarmentLabel.model_validate(item) for item in parsed["items"]]
            expected_ids = [item.item_id for item in items]
            returned = {item.item_id: item for item in labels}
            if len(returned) != len(labels) or set(returned) != set(expected_ids):
                raise ValueError("provider did not return each itemID exactly once")
            return [returned[item_id] for item_id in expected_ids]
        except (httpx.HTTPError, KeyError, TypeError, ValueError, ValidationError) as exc:
            raise ProviderUpstreamError(
                self.id,
                "Fireworks Qwen3.7 Plus could not validate the garment crops.",
            ) from exc
