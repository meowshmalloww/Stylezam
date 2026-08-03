from __future__ import annotations

import base64
import json
from pathlib import Path
from typing import Any, Dict

import httpx
from pydantic import ValidationError

from ..config import Settings
from ..errors import ProviderUpstreamError
from ..schemas import VisualAttributes


class OllamaVisionAnalyzer:
    id = "ollama"
    name = "Ollama Vision"

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.settings = settings
        self.client = client

    @property
    def configured(self) -> bool:
        return self.settings.ollama_enabled

    async def analyze(self, image_path: Path, user_query: str | None) -> VisualAttributes:
        image_data = base64.b64encode(image_path.read_bytes()).decode("ascii")
        prompt = (
            "Analyze only the main fashion item in this image for product retrieval. "
            "Do not guess a brand unless a logo or text makes it visible. Return strict JSON with: "
            "category, subcategory, brand (nullable), colors, materials, patterns, details, "
            "visible_text, and search_query. Keep search_query factual and shopping-oriented."
        )
        if user_query:
            prompt += " The user's refinement is: %s" % user_query
        schema: Dict[str, Any] = {
            "type": "object",
            "properties": {
                "category": {"type": ["string", "null"]},
                "subcategory": {"type": ["string", "null"]},
                "brand": {"type": ["string", "null"]},
                "colors": {"type": "array", "items": {"type": "string"}},
                "materials": {"type": "array", "items": {"type": "string"}},
                "patterns": {"type": "array", "items": {"type": "string"}},
                "details": {"type": "array", "items": {"type": "string"}},
                "visible_text": {"type": "array", "items": {"type": "string"}},
                "search_query": {"type": ["string", "null"]},
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
        }
        try:
            response = await self.client.post(
                "%s/api/chat" % self.settings.ollama_base_url.rstrip("/"),
                json={
                    "model": self.settings.ollama_vision_model,
                    "messages": [
                        {
                            "role": "user",
                            "content": prompt,
                            "images": [image_data],
                        }
                    ],
                    "format": schema,
                    "stream": False,
                    "options": {"temperature": 0},
                },
                timeout=self.settings.job_timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
            content = payload["message"]["content"]
            parsed = json.loads(content) if isinstance(content, str) else content
            return VisualAttributes.model_validate(parsed)
        except (httpx.HTTPError, ValueError, KeyError, TypeError, ValidationError) as exc:
            raise ProviderUpstreamError(
                "ollama",
                "The local vision model could not return structured fashion attributes.",
            ) from exc

