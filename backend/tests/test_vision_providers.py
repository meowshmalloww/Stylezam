import json
from pathlib import Path

import httpx
import pytest
from PIL import Image
from pydantic import SecretStr

from stylezam_api.config import Settings
from stylezam_api.providers.vision import (
    OpenAIResponsesVisionAnalyzer,
    fireworks_analyzer,
    qwen_analyzer,
)


ATTRIBUTES = {
    "category": "outerwear",
    "subcategory": "jacket",
    "brand": None,
    "colors": ["navy"],
    "materials": ["wool"],
    "patterns": [],
    "details": ["cropped"],
    "visible_text": [],
    "search_query": "navy cropped wool jacket",
}


def image_path(tmp_path: Path) -> Path:
    path = tmp_path / "look.jpg"
    Image.new("RGB", (32, 32), "navy").save(path)
    return path


@pytest.mark.asyncio
async def test_openai_responses_vision_request(tmp_path: Path) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        payload = json.loads(request.content)
        assert request.url.path == "/v1/responses"
        assert request.headers["authorization"] == "Bearer openai-secret"
        assert payload["model"] == "gpt-5.6-luna"
        content = payload["input"][0]["content"]
        assert content[1]["type"] == "input_image"
        assert content[1]["image_url"].startswith("data:image/jpeg;base64,")
        assert payload["text"]["format"]["type"] == "json_schema"
        return httpx.Response(
            200,
            json={
                "output": [
                    {
                        "content": [
                            {"type": "output_text", "text": json.dumps(ATTRIBUTES)}
                        ]
                    }
                ]
            },
        )

    settings = Settings(_env_file=None, openai_api_key=SecretStr("openai-secret"))
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await OpenAIResponsesVisionAnalyzer(settings, client).analyze(
            image_path(tmp_path), None
        )

    assert result.search_query == "navy cropped wool jacket"
    assert result.detected_items == []


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("provider_name", "expected_path", "schema_type"),
    [
        ("fireworks", "/inference/v1/chat/completions", "json_schema"),
        ("qwen", "/compatible-mode/v1/chat/completions", "json_object"),
    ],
)
async def test_compatible_vision_requests(
    tmp_path: Path,
    provider_name: str,
    expected_path: str,
    schema_type: str,
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        payload = json.loads(request.content)
        assert request.url.path == expected_path
        assert payload["messages"][0]["content"][1]["image_url"]["url"].startswith(
            "data:image/jpeg;base64,"
        )
        assert payload["response_format"]["type"] == schema_type
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": json.dumps(ATTRIBUTES)}}]},
        )

    settings = Settings(
        _env_file=None,
        fireworks_api_key=SecretStr("fireworks-secret"),
        qwen_api_key=SecretStr("qwen-secret"),
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        provider = (
            fireworks_analyzer(settings, client)
            if provider_name == "fireworks"
            else qwen_analyzer(settings, client)
        )
        result = await provider.analyze(image_path(tmp_path), "under $200")

    assert result.category == "outerwear"
    assert result.brand is None
