from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator


def to_camel(value: str) -> str:
    first, *rest = value.split("_")
    acronyms = {"id": "ID", "url": "URL"}
    return first + "".join(acronyms.get(part, part.capitalize()) for part in rest)


class APIModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        from_attributes=True,
    )


class JobStatus(str, Enum):
    queued = "queued"
    processing = "processing"
    completed = "completed"
    failed = "failed"
    cancelled = "cancelled"


class SearchPhase(str, Enum):
    queued = "queued"
    understanding = "understanding"
    retrieving = "retrieving"
    reranking = "reranking"
    completed = "completed"
    failed = "failed"


class TryOnPhase(str, Enum):
    queued = "queued"
    uploading = "uploading"
    generating = "generating"
    saving = "saving"
    completed = "completed"
    failed = "failed"


class MatchTier(str, Enum):
    exact = "exact"
    likely = "likely"
    similar = "similar"
    inspired = "inspired"


class BoundingBox(APIModel):
    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)
    width: float = Field(gt=0, le=1)
    height: float = Field(gt=0, le=1)

    @field_validator("width")
    @classmethod
    def width_in_bounds(cls, value: float, info: Any) -> float:
        x = info.data.get("x", 0)
        if x + value > 1.001:
            raise ValueError("x + width must be at most 1")
        return value

    @field_validator("height")
    @classmethod
    def height_in_bounds(cls, value: float, info: Any) -> float:
        y = info.data.get("y", 0)
        if y + value > 1.001:
            raise ValueError("y + height must be at most 1")
        return value


class DetectedItem(APIModel):
    label: str
    confidence: float = Field(ge=0, le=1)
    box: BoundingBox
    crop_url: Optional[str] = None


class VisualAttributes(APIModel):
    category: Optional[str] = None
    subcategory: Optional[str] = None
    brand: Optional[str] = None
    colors: List[str] = Field(default_factory=list)
    materials: List[str] = Field(default_factory=list)
    patterns: List[str] = Field(default_factory=list)
    details: List[str] = Field(default_factory=list)
    visible_text: List[str] = Field(default_factory=list)
    search_query: Optional[str] = None
    detected_items: List[DetectedItem] = Field(default_factory=list)


class Money(APIModel):
    amount: float
    currency: str
    display: Optional[str] = None


class MerchantOffer(APIModel):
    merchant: str
    url: str
    price: Optional[Money] = None
    shipping: Optional[str] = None
    condition: Optional[str] = None


class ProductResult(APIModel):
    id: str
    search_id: str
    provider: str
    provider_result_id: Optional[str] = None
    title: str
    brand: Optional[str] = None
    category: Optional[str] = None
    color: Optional[str] = None
    image_url: Optional[str] = None
    product_url: str
    merchant: str
    price: Optional[Money] = None
    match_tier: MatchTier
    score: float = Field(ge=0, le=1)
    rating: Optional[float] = None
    review_count: Optional[int] = None
    attributes: Dict[str, Any] = Field(default_factory=dict)
    offers: List[MerchantOffer] = Field(default_factory=list)


class SearchJob(APIModel):
    id: str
    status: JobStatus
    phase: SearchPhase
    progress: float = Field(ge=0, le=1)
    query: Optional[str] = None
    input_image_url: Optional[str] = None
    selected_region: Optional[BoundingBox] = None
    analysis: Optional[VisualAttributes] = None
    result_count: int = 0
    provider_warnings: List[str] = Field(default_factory=list)
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class SearchResultsPage(APIModel):
    search_id: str
    results: List[ProductResult]
    total: int


class TryOnJob(APIModel):
    id: str
    status: JobStatus
    phase: TryOnPhase
    progress: float = Field(ge=0, le=1)
    person_image_url: str
    product_image_url: str
    garment_category: str
    result_image_url: Optional[str] = None
    provider_task_id: Optional[str] = None
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class ProviderCapability(APIModel):
    id: str
    name: str
    capability: str
    configured: bool
    monthly_limit_note: Optional[str] = None
    detail: Optional[str] = None


class CapabilitiesResponse(APIModel):
    text_search: bool
    image_search: bool
    image_understanding: bool
    garment_segmentation: bool
    visual_reranking: bool
    virtual_try_on: bool
    public_image_ingress: bool
    providers: List[ProviderCapability]


class HealthResponse(APIModel):
    status: str
    version: str
    environment: str
    now: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ErrorDetail(APIModel):
    code: str
    message: str
    retryable: bool = False
    details: Dict[str, Any] = Field(default_factory=dict)


class ErrorResponse(APIModel):
    error: ErrorDetail
