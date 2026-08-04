from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Annotated, List, Optional

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="STYLEZAM_",
        case_sensitive=False,
        extra="ignore",
    )

    environment: str = "development"
    # Bind the container publicly. iPhones always use the deployed HTTPS URL;
    # localhost is never surfaced as an app default.
    host: str = "0.0.0.0"
    port: int = 8000
    data_dir: Path = Path(".data")
    public_base_url: Optional[str] = None
    allowed_origins: Annotated[List[str], NoDecode] = Field(default_factory=list)
    max_upload_bytes: int = 10 * 1024 * 1024
    max_image_pixels: int = 20_000_000
    search_result_limit: int = 40
    request_timeout_seconds: float = 30.0
    job_timeout_seconds: float = 600.0
    api_token: Optional[SecretStr] = None
    product_search_enabled: bool = False
    virtual_tryon_enabled: bool = False
    garment_analysis_max_items: int = 12
    garment_analysis_total_upload_bytes: int = 20 * 1024 * 1024
    garment_analysis_concurrency: int = 2
    request_body_max_bytes: int = 24 * 1024 * 1024
    model_pack_dir: Optional[Path] = None

    serpapi_api_key: Optional[str] = None
    serpapi_monthly_cap: int = 250

    ebay_client_id: Optional[str] = None
    ebay_client_secret: Optional[str] = None
    ebay_marketplace_id: str = "EBAY_US"
    ebay_monthly_cap: int = 5000

    fireworks_api_key: Optional[SecretStr] = None
    fireworks_base_url: str = "https://api.fireworks.ai/inference/v1"
    fireworks_vision_model: str = "accounts/fireworks/models/qwen3p7-plus"
    fireworks_monthly_cap: int = 100

    youcam_api_key: Optional[str] = None
    youcam_base_url: str = "https://yce-api-01.makeupar.com"
    youcam_monthly_cap: int = 20

    @field_validator(
        "serpapi_monthly_cap",
        "ebay_monthly_cap",
        "fireworks_monthly_cap",
        "youcam_monthly_cap",
    )
    @classmethod
    def validate_monthly_cap(cls, value: int) -> int:
        if value < 0:
            raise ValueError("monthly provider caps must be zero or greater")
        return value

    @field_validator("garment_analysis_max_items")
    @classmethod
    def validate_analysis_item_cap(cls, value: int) -> int:
        if not 1 <= value <= 20:
            raise ValueError("garment_analysis_max_items must be between 1 and 20")
        return value

    @field_validator("garment_analysis_total_upload_bytes")
    @classmethod
    def validate_analysis_upload_cap(cls, value: int) -> int:
        if not 1_048_576 <= value <= 100 * 1_048_576:
            raise ValueError(
                "garment_analysis_total_upload_bytes must be between 1 MB and 100 MB"
            )
        return value

    @field_validator("max_image_pixels")
    @classmethod
    def validate_image_pixel_cap(cls, value: int) -> int:
        if not 1_000_000 <= value <= 100_000_000:
            raise ValueError("max_image_pixels must be between 1 and 100 million")
        return value

    @field_validator("garment_analysis_concurrency")
    @classmethod
    def validate_analysis_concurrency(cls, value: int) -> int:
        if not 1 <= value <= 4:
            raise ValueError("garment_analysis_concurrency must be between 1 and 4")
        return value

    @field_validator("request_body_max_bytes")
    @classmethod
    def validate_request_body_cap(cls, value: int) -> int:
        if not 2 * 1_048_576 <= value <= 110 * 1_048_576:
            raise ValueError("request_body_max_bytes must be between 2 MB and 110 MB")
        return value

    @model_validator(mode="after")
    def request_body_cap_covers_garment_payload(self) -> "Settings":
        if self.request_body_max_bytes <= self.garment_analysis_total_upload_bytes:
            raise ValueError(
                "request_body_max_bytes must exceed garment_analysis_total_upload_bytes "
                "to leave room for multipart metadata"
            )
        return self

    @field_validator("public_base_url")
    @classmethod
    def normalize_public_url(cls, value: Optional[str]) -> Optional[str]:
        if not value:
            return None
        return value.rstrip("/")

    @field_validator("api_token", mode="before")
    @classmethod
    def empty_token_is_disabled(cls, value: object) -> object:
        if value is None:
            return None
        if isinstance(value, SecretStr):
            return value if value.get_secret_value().strip() else None
        return value if str(value).strip() else None

    @field_validator("allowed_origins", mode="before")
    @classmethod
    def parse_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @model_validator(mode="after")
    def production_is_fail_closed(self) -> "Settings":
        if self.environment.lower() not in {"production", "prod"}:
            return self
        token = self.api_token.get_secret_value().strip() if self.api_token else ""
        if not token:
            raise ValueError("STYLEZAM_API_TOKEN is required in production")
        if self.product_search_enabled and (
            not self.public_base_url or not self.public_base_url.startswith("https://")
        ):
            raise ValueError(
                "STYLEZAM_PUBLIC_BASE_URL must be a deployed HTTPS URL when "
                "product search is enabled in production"
            )
        return self

    def prepare_directories(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        (self.data_dir / "media").mkdir(parents=True, exist_ok=True)
        self.resolved_model_pack_dir.mkdir(parents=True, exist_ok=True)

    @property
    def resolved_model_pack_dir(self) -> Path:
        return self.model_pack_dir or (self.data_dir / "model-packs")


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.prepare_directories()
    return settings
