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


class OpenAIResponsesVisionAnalyzer:
    id = "openai"
    name = "OpenAI vision"

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.settings = settings
        self.client = client

    @property
    def configured(self) -> bool:
        return _secret_value(self.settings.openai_api_key) is not None

    async def analyze(self, image_path: Path, user_query: Optional[str]) -> VisualAttributes:
        try:
            response = await self.client.post(
                "%s/responses" % self.settings.openai_base_url.rstrip("/"),
                headers={"Authorization": "Bearer %s" % _secret_value(self.settings.openai_api_key)},
                json={
                    "model": self.settings.openai_vision_model,
                    "input": [
                        {
                            "role": "user",
                            "content": [
                                {"type": "input_text", "text": _prompt(user_query)},
                                {
                                    "type": "input_image",
                                    "image_url": _data_url(image_path),
                                    "detail": "low",
                                },
                            ],
                        }
                    ],
                    "text": {
                        "format": {
                            "type": "json_schema",
                            "name": "stylezam_visual_attributes",
                            "strict": True,
                            "schema": ATTRIBUTE_SCHEMA,
                        }
                    },
                },
                timeout=self.settings.job_timeout_seconds,
            )
            response.raise_for_status()
            return VisualAttributes.model_validate_json(self._output_text(response.json()))
        except (httpx.HTTPError, ValueError, KeyError, TypeError, ValidationError) as exc:
            raise ProviderUpstreamError(
                self.id,
                "OpenAI could not return structured fashion attributes.",
            ) from exc

    @staticmethod
    def _output_text(payload: Dict[str, Any]) -> str:
        direct = payload.get("output_text")
        if isinstance(direct, str) and direct:
            return direct
        for item in payload.get("output", []):
            for content in item.get("content", []):
                if content.get("type") == "output_text" and isinstance(content.get("text"), str):
                    return content["text"]
        raise KeyError("output_text")


class CompatibleChatVisionAnalyzer:
    def __init__(
        self,
        *,
        identifier: str,
        name: str,
        api_key: Optional[SecretStr],
        base_url: str,
        model: str,
        client: httpx.AsyncClient,
        strict_schema: bool,
        timeout: float,
    ) -> None:
        self.id = identifier
        self.name = name
        self._api_key = api_key
        self._base_url = base_url
        self._model = model
        self._client = client
        self._strict_schema = strict_schema
        self._timeout = timeout

    @property
    def configured(self) -> bool:
        return _secret_value(self._api_key) is not None

    async def analyze(self, image_path: Path, user_query: Optional[str]) -> VisualAttributes:
        response_format: Dict[str, Any]
        if self._strict_schema:
            response_format = {
                "type": "json_schema",
                "json_schema": {
                    "name": "stylezam_visual_attributes",
                    "schema": ATTRIBUTE_SCHEMA,
                },
            }
        else:
            response_format = {"type": "json_object"}
        try:
            response = await self._client.post(
                "%s/chat/completions" % self._base_url.rstrip("/"),
                headers={"Authorization": "Bearer %s" % _secret_value(self._api_key)},
                json={
                    "model": self._model,
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
                    "response_format": response_format,
                    "temperature": 0,
                },
                timeout=self._timeout,
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            if not isinstance(content, str):
                raise TypeError("message content was not text")
            return VisualAttributes.model_validate_json(content)
        except (httpx.HTTPError, ValueError, KeyError, TypeError, ValidationError) as exc:
            raise ProviderUpstreamError(
                self.id,
                "%s could not return structured fashion attributes." % self.name,
            ) from exc


def fireworks_analyzer(settings: Settings, client: httpx.AsyncClient) -> CompatibleChatVisionAnalyzer:
    return CompatibleChatVisionAnalyzer(
        identifier="fireworks",
        name="Fireworks AI",
        api_key=settings.fireworks_api_key,
        base_url=settings.fireworks_base_url,
        model=settings.fireworks_vision_model,
        client=client,
        strict_schema=True,
        timeout=settings.job_timeout_seconds,
    )


def qwen_analyzer(settings: Settings, client: httpx.AsyncClient) -> CompatibleChatVisionAnalyzer:
    return CompatibleChatVisionAnalyzer(
        identifier="qwen",
        name="Qwen",
        api_key=settings.qwen_api_key,
        base_url=settings.qwen_base_url,
        model=settings.qwen_vision_model,
        client=client,
        strict_schema=False,
        timeout=settings.job_timeout_seconds,
    )
