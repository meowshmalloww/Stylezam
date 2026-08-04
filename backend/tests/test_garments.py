import json
from io import BytesIO
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from pydantic import SecretStr

from stylezam_api.config import Settings
from stylezam_api.errors import ProviderUpstreamError, StylezamError
from stylezam_api.main import create_app
from stylezam_api.providers.garment_labeling import FireworksGarmentLabeler
from stylezam_api.schemas import BoundingBox, GarmentInputMetadata, GarmentLabel
from stylezam_api.storage import MediaStorage


def image_bytes(color: str = "navy") -> bytes:
    output = BytesIO()
    Image.new("RGB", (128, 128), color).save(output, format="JPEG")
    return output.getvalue()


def transparent_image_bytes() -> bytes:
    output = BytesIO()
    image = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    for x in range(24, 104):
        for y in range(20, 112):
            image.putpixel((x, y), (20, 60, 160, 255))
    image.save(output, format="PNG")
    return output.getvalue()


def metadata(item_id: str = "item-1") -> dict:
    return {
        "itemID": item_id,
        "localLabel": "jacket",
        "localConfidence": 0.91,
        "box": {"x": 0.1, "y": 0.1, "width": 0.7, "height": 0.8},
    }


@pytest.mark.asyncio
async def test_fireworks_labeler_uses_one_bounded_multimodal_request(
    tmp_path: Path,
) -> None:
    first = tmp_path / "first.jpg"
    second = tmp_path / "second.jpg"
    first.write_bytes(image_bytes("navy"))
    second.write_bytes(image_bytes("white"))

    def handler(request: httpx.Request) -> httpx.Response:
        payload = json.loads(request.content)
        assert payload["model"] == "accounts/fireworks/models/minimax-m3"
        assert payload["max_tokens"] == 1600
        assert payload["response_format"]["type"] == "json_schema"
        images = [
            part
            for part in payload["messages"][0]["content"]
            if part["type"] == "image_url"
        ]
        assert len(images) == 2
        assert all(
            part["image_url"]["url"].startswith("data:image/jpeg;base64,")
            for part in images
        )
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "items": [
                                        {
                                            "itemID": "item-1",
                                            "accepted": True,
                                            "category": "jacket",
                                            "displayName": "Navy cropped jacket",
                                            "brand": None,
                                            "colors": ["navy"],
                                            "materials": [],
                                            "patterns": [],
                                            "details": ["cropped"],
                                            "visibleText": [],
                                        },
                                        {
                                            "itemID": "item-2",
                                            "accepted": False,
                                            "category": None,
                                            "displayName": None,
                                            "brand": None,
                                            "colors": [],
                                            "materials": [],
                                            "patterns": [],
                                            "details": [],
                                            "visibleText": [],
                                        },
                                    ]
                                }
                            )
                        }
                    }
                ]
            },
        )

    settings = Settings(
        _env_file=None,
        fireworks_api_key=SecretStr("fireworks-secret"),
    )
    items = [
        GarmentInputMetadata(
            item_id="item-1",
            local_label="jacket",
            local_confidence=0.91,
            box=BoundingBox(x=0.1, y=0.1, width=0.7, height=0.8),
        ),
        GarmentInputMetadata(
            item_id="item-2",
            local_label="shoe",
            local_confidence=0.84,
            box=BoundingBox(x=0.1, y=0.1, width=0.4, height=0.3),
        ),
    ]
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await FireworksGarmentLabeler(settings, client).label(
            [first, second], items
        )

    assert [item.item_id for item in result] == ["item-1", "item-2"]
    assert result[0].display_name == "Navy cropped jacket"
    assert result[1].accepted is False


@pytest.mark.asyncio
async def test_fireworks_labeler_rejects_missing_ids(tmp_path: Path) -> None:
    path = tmp_path / "crop.jpg"
    path.write_bytes(image_bytes())

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"choices": [{"message": {"content": '{"items":[]}'}}]})

    settings = Settings(
        _env_file=None,
        fireworks_api_key=SecretStr("fireworks-secret"),
    )
    item = GarmentInputMetadata(
        item_id="item-1",
        local_label="jacket",
        local_confidence=0.91,
        box=BoundingBox(x=0.1, y=0.1, width=0.7, height=0.8),
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(ProviderUpstreamError):
            await FireworksGarmentLabeler(settings, client).label([path], [item])


def test_storage_preserves_segment_alpha_and_rejects_excess_pixels(
    tmp_path: Path,
) -> None:
    settings = Settings(
        _env_file=None,
        environment="test",
        data_dir=tmp_path,
        max_image_pixels=1_000_000,
    )
    settings.prepare_directories()
    storage = MediaStorage(settings)

    stored = storage.save_image_bytes(
        transparent_image_bytes(),
        prefix="garment-label",
    )
    assert stored.content_type == "image/png"
    assert stored.path.suffix == ".png"
    with Image.open(stored.path) as preserved:
        assert preserved.mode == "RGBA"
        assert preserved.getpixel((0, 0))[3] == 0

    oversized = BytesIO()
    Image.new("RGB", (1_100, 1_000), "navy").save(oversized, format="PNG")
    with pytest.raises(StylezamError) as error:
        storage.save_image_bytes(oversized.getvalue(), prefix="oversized")
    assert getattr(error.value, "code", None) == "image_dimensions_too_large"


def test_garment_analysis_validates_count_caps_and_deletes_temporary_media(
    tmp_path: Path,
) -> None:
    class Labeler:
        id = "test-labeler"
        configured = True

        async def label(self, paths, items):
            assert len(paths) == 1
            assert all(path.is_file() for path in paths)
            return [
                GarmentLabel(
                    item_id=items[0].item_id,
                    accepted=True,
                    category="jacket",
                    display_name="Navy jacket",
                )
            ]

    settings = Settings(
        _env_file=None,
        environment="test",
        data_dir=tmp_path,
        fireworks_api_key=SecretStr("configured"),
        fireworks_monthly_cap=1,
    )
    with TestClient(create_app(settings)) as client:
        client.app.state.container.garment_labeler = Labeler()
        mismatch = client.post(
            "/v1/garment-analyses",
            data={"metadata": json.dumps([metadata(), metadata("item-2")])},
            files={"images": ("crop.jpg", image_bytes(), "image/jpeg")},
        )
        response = client.post(
            "/v1/garment-analyses",
            data={"metadata": json.dumps([metadata()])},
            files={"images": ("crop.jpg", image_bytes(), "image/jpeg")},
        )
        capped = client.post(
            "/v1/garment-analyses",
            data={"metadata": json.dumps([metadata()])},
            files={"images": ("crop.jpg", image_bytes(), "image/jpeg")},
        )

    assert mismatch.status_code == 422
    assert response.status_code == 200
    assert response.json()["items"][0]["displayName"] == "Navy jacket"
    assert capped.status_code == 429
    assert not list((tmp_path / "media").glob("garment-label-*.jpg"))


def test_request_body_limit_rejects_before_multipart_parsing(tmp_path: Path) -> None:
    settings = Settings(
        _env_file=None,
        environment="test",
        data_dir=tmp_path,
        garment_analysis_total_upload_bytes=1_048_576,
        request_body_max_bytes=2_097_152,
    )
    with TestClient(create_app(settings)) as client:
        response = client.post(
            "/v1/garment-analyses",
            content=b"x" * (settings.request_body_max_bytes + 1),
            headers={"content-type": "application/octet-stream"},
        )

    assert response.status_code == 413
    assert response.json()["error"]["code"] == "request_body_too_large"


def test_model_pack_manifest_only_publishes_existing_files(tmp_path: Path) -> None:
    settings = Settings(
        _env_file=None,
        environment="test",
        data_dir=tmp_path,
        api_token=SecretStr("model-pack-token"),
    )
    root = settings.resolved_model_pack_dir
    package = root / "garment-rfdetr-seg-small/1.0.0/model.mlpackage"
    package.mkdir(parents=True)
    payload_file = package / "Manifest.json"
    payload_file.write_text("{}", encoding="utf-8")
    catalog = {
        "modelID": "garment-rfdetr-seg-small",
        "version": "1.0.0",
        "displayName": "Stylezam Garment Segmentation",
        "storagePrefix": "garment-rfdetr-seg-small/1.0.0/model.mlpackage",
        "totalBytes": 2,
        "minimumIos": "26.0",
        "inputName": "tensors",
        "inputResolution": 384,
        "boxOutputName": "boxes",
        "logitOutputName": "logits",
        "maskOutputName": "masks",
        "classNames": ["jacket"],
        "licenseName": "Apache-2.0",
        "licenseURL": "https://www.apache.org/licenses/LICENSE-2.0",
        "sourceURL": "https://huggingface.co/resoa/garment-detector-seg",
        "sourceRevision": "f1b64c11fa42d2f7455708b7a05f81c015461427",
        "checkpointSHA256": "1" * 64,
        "datasetName": "Fashionpedia",
        "datasetLicenseName": "CC BY 4.0",
        "datasetLicenseURL": "https://creativecommons.org/licenses/by/4.0/",
        "attribution": "RF-DETR and Fashionpedia",
        "files": [
            {
                "path": "Manifest.json",
                "url": "",
                "sha256": "0" * 64,
                "bytes": 2,
            }
        ],
    }
    root.mkdir(parents=True, exist_ok=True)
    (root / "garment-segmentation.json").write_text(
        json.dumps(catalog), encoding="utf-8"
    )

    with TestClient(create_app(settings)) as client:
        headers = {"Authorization": "Bearer model-pack-token"}
        unauthorized = client.get("/v1/model-packs/garment-segmentation")
        response = client.get(
            "/v1/model-packs/garment-segmentation",
            headers=headers,
        )
        file_response = client.get(response.json()["files"][0]["url"], headers=headers)
        blocked_unlisted_file = client.get(
            "/v1/model-pack-files/garment-segmentation.json",
            headers=headers,
        )

    assert unauthorized.status_code == 401
    assert response.status_code == 200
    assert response.json()["files"][0]["url"].endswith(
        "/v1/model-pack-files/garment-rfdetr-seg-small/1.0.0/model.mlpackage/Manifest.json"
    )
    assert file_response.status_code == 200
    assert file_response.content == b"{}"
    assert blocked_unlisted_file.status_code == 404
