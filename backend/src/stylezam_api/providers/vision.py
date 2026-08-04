from __future__ import annotations

import base64
import json
from pathlib import Path
from typing import Any, Dict, Optional

import httpx
from pydantic import SecretStr, ValidationError

from ..config import Settings
from ..errors import ProviderUpstreamError
from ..schemas import VisualAttributes


ATTRIBUTE_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "category": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "subcategory": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "brand": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "colors": {"type": "array", "items": {"type": "string"}},
        "materials": {"type": "array", "items": {"type": "string"}},
        "patterns": {"type": "array", "items": {"type": "string"}},
        "details": {"type": "array", "items": {"type": "string"}},
        "visible_text": {"type": "array", "items": {"type": "string"}},
        "search_query": {"anyOf": [{"type": "string"}, {"type": "null"}]},
    },
    "required": [
        "category",
        "subcategory",
        "brand",
        "colors",
        "materials",
        "patterns",
        "details",
        "visible_text",
        "search_query",
    ],
    "additionalProperties": False,
}


def _prompt(user_query: Optional[str]) -> str:
    prompt = (
        "Inspect the main fashion item for product retrieval. Report only visible, factual "
        "attributes. Never infer a brand without readable text or a visible logo. Keep "
        "search_query concise and shopping-oriented. Return JSON matching this schema: "
        + json.dumps(ATTRIBUTE_SCHEMA, separators=(",", ":"))
    )
    if user_query:
        prompt += " The shopper's refinement is: " + user_query
    return prompt


def _data_url(image_path: Path) -> str:
    suffix = image_path.suffix.lower()
    media_type = "image/png" if suffix == ".png" else "image/jpeg"
    encoded = base64.b64encode(image_path.read_bytes()).decode("ascii")
    return "data:%s;base64,%s" % (media_type, encoded)


def _secret_value(secret: Optional[SecretStr]) -> Optional[str]:
    if secret is None:
        return None
    value = secret.get_secret_value().strip()
    return value or None


class FireworksVisionAnalyzer:
    id = "fireworks"
    name = "Fireworks Qwen3.7 Plus"

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.settings = settings
        self.client = client

    @property
    def configured(self) -> bool:
        return _secret_value(self.settings.fireworks_api_key) is not None

    async def analyze(self, image_path: Path, user_query: Optional[str]) -> VisualAttributes:
        try:
            response = await self.client.post(
                "%s/chat/completions" % self.settings.fireworks_base_url.rstrip("/"),
                headers={
                    "Authorization": "Bearer %s"
                    % _secret_value(self.settings.fireworks_api_key)
                },
                json={
                    "model": self.settings.fireworks_vision_model,
                    "messages": [
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": _prompt(user_query)},
                                {
                                    "type": "image_url",
                                    "image_url": {"url": _data_url(image_path)},
                                },
                            ],
                        }
                    ],
                    "response_format": {
                        "type": "json_schema",
                        "json_schema": {
                            "name": "stylezam_visual_attributes",
                            "schema": ATTRIBUTE_SCHEMA,
                        },
                    },
                    "temperature": 0,
                    "reasoning_effort": "none",
                    "max_tokens": 1_000,
                },
                timeout=self.settings.job_timeout_seconds,
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            if not isinstance(content, str):
                raise TypeError("message content was not text")
            return VisualAttributes.model_validate_json(content)
        except (httpx.HTTPError, ValueError, KeyError, TypeError, ValidationError) as exc:
            raise ProviderUpstreamError(
                self.id,
                "Qwen3.7 Plus could not return structured fashion attributes.",
            ) from exc


def fireworks_analyzer(settings: Settings, client: httpx.AsyncClient) -> FireworksVisionAnalyzer:
    return FireworksVisionAnalyzer(settings, client)
