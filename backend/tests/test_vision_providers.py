import json
from pathlib import Path

import httpx
import pytest
from PIL import Image
from pydantic import SecretStr

from stylezam_api.config import Settings
from stylezam_api.providers.vision import fireworks_analyzer


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
    Image.new("RGB", (64, 64), "navy").save(path)
    return path


@pytest.mark.asyncio
async def test_fireworks_qwen3p7_vision_request(tmp_path: Path) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        payload = json.loads(request.content)
        assert request.url.path == "/inference/v1/chat/completions"
        assert request.headers["authorization"] == "Bearer fireworks-secret"
        assert payload["model"] == "accounts/fireworks/models/qwen3p7-plus"
        image = payload["messages"][0]["content"][1]
        assert image["image_url"]["url"].startswith("data:image/jpeg;base64,")
        assert payload["response_format"]["type"] == "json_schema"
        assert payload["temperature"] == 0
        assert payload["reasoning_effort"] == "none"
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": json.dumps(ATTRIBUTES)}}]},
        )

    settings = Settings(
        _env_file=None,
        fireworks_api_key=SecretStr("fireworks-secret"),
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await fireworks_analyzer(settings, client).analyze(
            image_path(tmp_path), "under $200"
        )

    assert result.category == "outerwear"
    assert result.brand is None
