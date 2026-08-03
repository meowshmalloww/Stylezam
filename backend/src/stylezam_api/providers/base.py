from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class ProviderPrice:
    amount: float
    currency: str
    display: Optional[str] = None

    def as_dict(self) -> Dict[str, Any]:
        return {
            "amount": self.amount,
            "currency": self.currency,
            "display": self.display,
        }


@dataclass
class ProviderProduct:
    provider: str
    title: str
    product_url: str
    merchant: str
    image_url: Optional[str] = None
    provider_result_id: Optional[str] = None
    brand: Optional[str] = None
    category: Optional[str] = None
    color: Optional[str] = None
    price: Optional[ProviderPrice] = None
    rating: Optional[float] = None
    review_count: Optional[int] = None
    source_score: float = 0.5
    source_exact: bool = False
    attributes: Dict[str, Any] = field(default_factory=dict)
    offers: List[Dict[str, Any]] = field(default_factory=list)

