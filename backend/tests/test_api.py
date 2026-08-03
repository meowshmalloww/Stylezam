import time
from pathlib import Path

from fastapi.testclient import TestClient
from pydantic import SecretStr

from stylezam_api.config import Settings
from stylezam_api.main import create_app
from stylezam_api.providers.base import ProviderPrice, ProviderProduct


def settings_for(tmp_path: Path) -> Settings:
    return Settings(
        _env_file=None,
        environment="test",
        data_dir=tmp_path,
        serpapi_api_key=None,
        ebay_client_id=None,
        ebay_client_secret=None,
        openai_api_key=None,
        fireworks_api_key=None,
        qwen_api_key=None,
        local_vision_enabled=False,
        youcam_api_key=None,
    )


def test_comma_separated_allowed_origins_from_environment(monkeypatch) -> None:
    monkeypatch.setenv(
        "STYLEZAM_ALLOWED_ORIGINS",
        "http://localhost:3000, https://stylezam.example",
    )
    settings = Settings(_env_file=None)
    assert settings.allowed_origins == [
        "http://localhost:3000",
        "https://stylezam.example",
    ]


def wait_for_terminal(client: TestClient, search_id: str) -> dict:
    for _ in range(100):
        payload = client.get("/v1/searches/%s" % search_id).json()
        if payload["status"] in {"completed", "failed"}:
            return payload
        time.sleep(0.01)
    raise AssertionError("search did not finish")


def test_health_and_capabilities(tmp_path: Path) -> None:
    with TestClient(create_app(settings_for(tmp_path))) as client:
        health = client.get("/v1/health")
        capabilities = client.get("/v1/capabilities")

    assert health.status_code == 200
    assert health.json()["status"] == "ok"
    assert capabilities.status_code == 200
    assert capabilities.json()["textSearch"] is False


def test_optional_bearer_token_protects_jobs_and_capabilities(tmp_path: Path) -> None:
    settings = settings_for(tmp_path)
    settings.api_token = SecretStr("correct-horse-battery-staple")
    with TestClient(create_app(settings)) as client:
        assert client.get("/v1/health").status_code == 200
        missing = client.get("/v1/capabilities")
        wrong = client.get(
            "/v1/capabilities",
            headers={"Authorization": "Bearer wrong"},
        )
        allowed = client.get(
            "/v1/capabilities",
            headers={"Authorization": "Bearer correct-horse-battery-staple"},
        )
        blocked_search = client.post("/v1/searches", data={"query": "coat"})

    assert missing.status_code == 401
    assert missing.json()["error"]["code"] == "unauthorized"
    assert wrong.status_code == 401
    assert allowed.status_code == 200
    assert blocked_search.status_code == 401


def test_public_base_url_is_used_for_uploaded_media(tmp_path: Path) -> None:
    from io import BytesIO

    from PIL import Image

    settings = settings_for(tmp_path)
    settings.public_base_url = "https://api.stylezam.example"
    image = Image.new("RGB", (128, 128), "navy")
    data = BytesIO()
    image.save(data, format="JPEG")

    with TestClient(create_app(settings)) as client:
        submitted = client.post(
            "/v1/searches",
            files={"image": ("coat.jpg", data.getvalue(), "image/jpeg")},
        )

    assert submitted.status_code == 202
    assert submitted.json()["inputImageURL"].startswith(
        "https://api.stylezam.example/media/search-"
    )


def test_unconfigured_search_fails_honestly(tmp_path: Path) -> None:
    with TestClient(create_app(settings_for(tmp_path))) as client:
        submitted = client.post("/v1/searches", data={"query": "red wool coat"})
        assert submitted.status_code == 202
        terminal = wait_for_terminal(client, submitted.json()["id"])

    assert terminal["status"] == "failed"
    assert terminal["errorCode"] == "provider_configuration_required"
    assert terminal["progress"] == 0.43


def test_text_search_persists_real_provider_output(tmp_path: Path) -> None:
    class Provider:
        configured = True

        async def search_text(self, query: str):
            assert query == "navy wool coat"
            return [
                ProviderProduct(
                    provider="test-provider",
                    title="Navy wool coat",
                    product_url="https://merchant.example/navy-coat",
                    merchant="Merchant",
                    image_url="https://merchant.example/navy-coat.jpg",
                    price=ProviderPrice(250, "USD", "$250"),
                    source_score=0.8,
                )
            ]

        async def search_image(self, *args, **kwargs):
            return []

    with TestClient(create_app(settings_for(tmp_path))) as client:
        client.app.state.container.search_pipeline.serpapi = Provider()
        submitted = client.post("/v1/searches", data={"query": "navy wool coat"})
        terminal = wait_for_terminal(client, submitted.json()["id"])
        results = client.get(
            "/v1/searches/%s/results" % submitted.json()["id"]
        ).json()

    assert terminal["status"] == "completed"
    assert results["total"] == 1
    result = results["results"][0]
    assert result["title"] == "Navy wool coat"
    assert result["price"]["amount"] == 250
    assert result["searchID"] == submitted.json()["id"]
    assert result["productURL"] == "https://merchant.example/navy-coat"
    assert result["imageURL"] == "https://merchant.example/navy-coat.jpg"
    assert "providerResultID" in result


def test_delete_search_removes_job_and_input_media(tmp_path: Path) -> None:
    from io import BytesIO

    from PIL import Image

    image = Image.new("RGB", (128, 128), "navy")
    data = BytesIO()
    image.save(data, format="JPEG")

    with TestClient(create_app(settings_for(tmp_path))) as client:
        submitted = client.post(
            "/v1/searches",
            files={"image": ("coat.jpg", data.getvalue(), "image/jpeg")},
        )
        search_id = submitted.json()["id"]
        media_files = list((tmp_path / "media").glob("search-*.jpg"))
        assert len(media_files) == 1

        deleted = client.delete("/v1/searches/%s" % search_id)
        missing = client.get("/v1/searches/%s" % search_id)

    assert deleted.status_code == 204
    assert missing.status_code == 404
    assert not media_files[0].exists()


def test_selected_region_is_validated_persisted_and_crop_is_temporary(
    tmp_path: Path,
) -> None:
    from io import BytesIO

    from PIL import Image

    class ImageProvider:
        configured = True

        async def search_text(self, query: str):
            return []

        async def search_image(self, image_bytes: bytes):
            assert image_bytes
            return []

    image = Image.new("RGB", (256, 192), "navy")
    data = BytesIO()
    image.save(data, format="JPEG")
    region = '{"x":0.1,"y":0.2,"width":0.5,"height":0.6}'

    with TestClient(create_app(settings_for(tmp_path))) as client:
        client.app.state.container.search_pipeline.ebay = ImageProvider()
        invalid = client.post(
            "/v1/searches",
            data={"selected_region": '{"x":0.8,"y":0.2,"width":0.5,"height":0.6}'},
            files={"image": ("look.jpg", data.getvalue(), "image/jpeg")},
        )
        assert invalid.status_code == 422

        submitted = client.post(
            "/v1/searches",
            data={"selected_region": region},
            files={"image": ("look.jpg", data.getvalue(), "image/jpeg")},
        )
        assert submitted.status_code == 202
        terminal = wait_for_terminal(client, submitted.json()["id"])
        selection_files = list((tmp_path / "media").glob("selection-*.jpg"))

    assert terminal["status"] == "completed"
    assert terminal["selectedRegion"] == {
        "x": 0.1,
        "y": 0.2,
        "width": 0.5,
        "height": 0.6,
    }
    assert selection_files == []


def test_monthly_provider_cap_is_a_hard_stop(tmp_path: Path) -> None:
    class Provider:
        configured = True

        async def search_text(self, query: str):
            return []

        async def search_image(self, *args, **kwargs):
            return []

    settings = settings_for(tmp_path)
    settings.serpapi_monthly_cap = 1
    with TestClient(create_app(settings)) as client:
        client.app.state.container.search_pipeline.serpapi = Provider()
        first = client.post("/v1/searches", data={"query": "navy coat"})
        first_terminal = wait_for_terminal(client, first.json()["id"])
        second = client.post("/v1/searches", data={"query": "red coat"})
        second_terminal = wait_for_terminal(client, second.json()["id"])

    assert first_terminal["status"] == "completed"
    assert second_terminal["status"] == "failed"
    assert second_terminal["errorCode"] == "monthly_cap_reached"
