from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Optional

import httpx

from ..config import Settings
from ..errors import ProviderUpstreamError
from .base import ProviderPrice, ProviderProduct


_CURRENCY_SYMBOLS = {
    "$": "USD",
    "US$": "USD",
    "£": "GBP",
    "€": "EUR",
    "CA$": "CAD",
    "A$": "AUD",
    "¥": "JPY",
}


def parse_price(item: Dict[str, Any], default_currency: str = "USD") -> Optional[ProviderPrice]:
    extracted = item.get("extracted_price")
    display = item.get("price")
    if isinstance(display, dict):
        extracted = display.get("extracted_value", display.get("value", extracted))
        display = display.get("value") or display.get("text")
    if extracted is None and isinstance(display, str):
        match = re.search(r"([0-9][0-9,]*(?:\.[0-9]{1,2})?)", display)
        if match:
            try:
                extracted = float(match.group(1).replace(",", ""))
            except ValueError:
                extracted = None
    if extracted is None:
        return None
    try:
        amount = float(extracted)
    except (TypeError, ValueError):
        return None
    currency = item.get("currency") or default_currency
    if isinstance(display, str):
        for symbol, code in _CURRENCY_SYMBOLS.items():
            if display.strip().startswith(symbol):
                currency = code
                break
    return ProviderPrice(amount=amount, currency=str(currency), display=display if isinstance(display, str) else None)


class SerpAPIProvider:
    id = "serpapi"
    name = "SerpApi"

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.settings = settings
        self.client = client

    @property
    def configured(self) -> bool:
        return bool(self.settings.serpapi_api_key)

    async def search_text(
        self,
        query: str,
        *,
        country: str = "us",
        language: str = "en",
    ) -> List[ProviderProduct]:
        payload = await self._request(
            {
                "engine": "google_shopping",
                "q": query,
                "gl": country.lower(),
                "hl": language.lower(),
            }
        )
        rows: List[Dict[str, Any]] = []
        for key in ("shopping_results", "inline_shopping_results"):
            value = payload.get(key)
            if isinstance(value, list):
                rows.extend(row for row in value if isinstance(row, dict))
        return [product for product in (self._shopping_product(row) for row in rows) if product]

    async def search_image(
        self,
        image_url: str,
        *,
        refinement: Optional[str] = None,
        country: str = "US",
    ) -> List[ProviderProduct]:
        parameters: Dict[str, Any] = {
            "engine": "google_lens",
            "url": image_url,
            "type": "products",
            "country": country.upper(),
        }
        if refinement:
            parameters["q"] = refinement
        payload = await self._request(parameters)
        rows: List[Dict[str, Any]] = []
        for key in ("products", "visual_matches", "exact_matches"):
            value = payload.get(key)
            if isinstance(value, list):
                for row in value:
                    if isinstance(row, dict):
                        copied = dict(row)
                        copied["_result_group"] = key
                        rows.append(copied)
        return [product for product in (self._lens_product(row) for row in rows) if product]

    async def _request(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        parameters["api_key"] = self.settings.serpapi_api_key
        try:
            response = await self.client.get(
                "https://serpapi.com/search.json",
                params=parameters,
                timeout=self.settings.request_timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise ProviderUpstreamError("serpapi", "SerpApi could not complete the product search.") from exc
        if payload.get("error"):
            raise ProviderUpstreamError("serpapi", str(payload["error"]), retryable=False)
        return payload

    def _shopping_product(self, item: Dict[str, Any]) -> Optional[ProviderProduct]:
        title = item.get("title")
        url = item.get("product_link") or item.get("link")
        merchant = item.get("source") or item.get("merchant") or "Google Shopping"
        if not isinstance(title, str) or not isinstance(url, str):
            return None
        return ProviderProduct(
            provider=self.id,
            provider_result_id=str(item.get("product_id")) if item.get("product_id") else None,
            title=title,
            product_url=url,
            merchant=str(merchant),
            image_url=self._image(item),
            brand=item.get("brand") if isinstance(item.get("brand"), str) else None,
            price=parse_price(item),
            rating=self._float(item.get("rating")),
            review_count=self._int(item.get("reviews")),
            source_score=0.61,
            attributes={
                key: item[key]
                for key in ("delivery", "tag", "extensions")
                if key in item
            },
        )

    def _lens_product(self, item: Dict[str, Any]) -> Optional[ProviderProduct]:
        title = item.get("title")
        url = item.get("link") or item.get("product_link")
        merchant = item.get("source") or item.get("merchant") or "Google Lens"
        if not isinstance(title, str) or not isinstance(url, str):
            return None
        result_group = item.get("_result_group")
        exact = result_group == "exact_matches" or bool(item.get("exact_matches"))
        return ProviderProduct(
            provider=self.id,
            provider_result_id=str(item.get("product_id")) if item.get("product_id") else None,
            title=title,
            product_url=url,
            merchant=str(merchant),
            image_url=self._image(item),
            brand=item.get("brand") if isinstance(item.get("brand"), str) else None,
            price=parse_price(item),
            rating=self._float(item.get("rating")),
            review_count=self._int(item.get("reviews")),
            source_score=0.82 if exact else 0.68,
            source_exact=exact,
            attributes={"lensResultGroup": result_group} if result_group else {},
        )

    @staticmethod
    def _image(item: Dict[str, Any]) -> Optional[str]:
        for key in ("image", "thumbnail", "serpapi_thumbnail"):
            value = item.get(key)
            if isinstance(value, str):
                return value
            if isinstance(value, dict):
                nested = value.get("url") or value.get("imageUrl")
                if isinstance(nested, str):
                    return nested
        return None

    @staticmethod
    def _float(value: Any) -> Optional[float]:
        try:
            return float(value) if value is not None else None
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _int(value: Any) -> Optional[int]:
        try:
            return int(value) if value is not None else None
        except (TypeError, ValueError):
            return None

