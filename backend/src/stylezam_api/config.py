from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Annotated, List, Optional

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="STYLEZAM_",
        case_sensitive=False,
        extra="ignore",
    )

    environment: str = "development"
    host: str = "127.0.0.1"
    port: int = 8000
    data_dir: Path = Path(".data")
    public_base_url: Optional[str] = None
    allowed_origins: Annotated[List[str], NoDecode] = Field(default_factory=list)
    max_upload_bytes: int = 10 * 1024 * 1024
    search_result_limit: int = 40
    request_timeout_seconds: float = 30.0
    job_timeout_seconds: float = 600.0
    api_token: Optional[SecretStr] = None

    serpapi_api_key: Optional[str] = None
    serpapi_monthly_cap: int = 250

    ebay_client_id: Optional[str] = None
    ebay_client_secret: Optional[str] = None
    ebay_marketplace_id: str = "EBAY_US"
    ebay_monthly_cap: int = 5000

    ollama_enabled: bool = False
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_vision_model: str = "gemma3:4b"

    local_vision_enabled: bool = False
    grounding_dino_model: str = "IDEA-Research/grounding-dino-tiny"
    sam2_model: str = "facebook/sam2.1-hiera-tiny"
    clip_model: str = "openai/clip-vit-base-patch32"

    youcam_api_key: Optional[str] = None
    youcam_base_url: str = "https://yce-api-01.makeupar.com"
    youcam_monthly_cap: int = 20

    @field_validator(
        "serpapi_monthly_cap",
        "ebay_monthly_cap",
        "youcam_monthly_cap",
    )
    @classmethod
    def validate_monthly_cap(cls, value: int) -> int:
        if value < 0:
            raise ValueError("monthly provider caps must be zero or greater")
        return value

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

    def prepare_directories(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        (self.data_dir / "media").mkdir(parents=True, exist_ok=True)


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.prepare_directories()
    return settings
