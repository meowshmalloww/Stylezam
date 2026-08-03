from __future__ import annotations

import asyncio
import base64
import time
from typing import Any, Dict, List, Optional

import httpx

from ..config import Settings
from ..errors import ProviderUpstreamError
from .base import ProviderPrice, ProviderProduct


class EbayProvider:
    id = "ebay"
    name = "eBay Browse"

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.settings = settings
        self.client = client
        self._token: Optional[str] = None
        self._token_expires_at = 0.0
        self._token_lock = asyncio.Lock()

    @property
    def configured(self) -> bool:
        return bool(self.settings.ebay_client_id and self.settings.ebay_client_secret)

    async def search_text(self, query: str) -> List[ProviderProduct]:
        payload = await self._browse_request(
            "GET",
            "/buy/browse/v1/item_summary/search",
            params={"q": query, "limit": min(self.settings.search_result_limit, 50)},
        )
        return self._products(payload)

    async def search_image(self, image_bytes: bytes) -> List[ProviderProduct]:
        payload = await self._browse_request(
            "POST",
            "/buy/browse/v1/item_summary/search_by_image",
            params={"limit": min(self.settings.search_result_limit, 50)},
            json_body={"image": base64.b64encode(image_bytes).decode("ascii")},
        )
        return self._products(payload)

    async def _browse_request(
        self,
        method: str,
        path: str,
        *,
        params: Optional[Dict[str, Any]] = None,
        json_body: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        token = await self._access_token()
        headers = {
            "Authorization": "Bearer %s" % token,
            "X-EBAY-C-MARKETPLACE-ID": self.settings.ebay_marketplace_id,
            "Content-Type": "application/json",
        }
        try:
            response = await self.client.request(
                method,
                "https://api.ebay.com%s" % path,
                params=params,
                json=json_body,
                headers=headers,
                timeout=self.settings.request_timeout_seconds,
            )
            response.raise_for_status()
            return response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise ProviderUpstreamError("ebay", "eBay Browse could not complete the product search.") from exc

    async def _access_token(self) -> str:
        if self._token and time.monotonic() < self._token_expires_at:
            return self._token
        async with self._token_lock:
            if self._token and time.monotonic() < self._token_expires_at:
                return self._token
            credentials = "%s:%s" % (
                self.settings.ebay_client_id,
                self.settings.ebay_client_secret,
            )
            encoded = base64.b64encode(credentials.encode("utf-8")).decode("ascii")
            try:
                response = await self.client.post(
                    "https://api.ebay.com/identity/v1/oauth2/token",
                    headers={
                        "Authorization": "Basic %s" % encoded,
                        "Content-Type": "application/x-www-form-urlencoded",
                    },
                    data={
                        "grant_type": "client_credentials",
                        "scope": "https://api.ebay.com/oauth/api_scope",
                    },
                    timeout=self.settings.request_timeout_seconds,
                )
                response.raise_for_status()
                payload = response.json()
                self._token = str(payload["access_token"])
                expires_in = int(payload.get("expires_in", 7200))
                self._token_expires_at = time.monotonic() + max(expires_in - 120, 60)
                return self._token
            except (httpx.HTTPError, ValueError, KeyError) as exc:
                raise ProviderUpstreamError("ebay", "eBay authentication failed.", retryable=False) from exc

    def _products(self, payload: Dict[str, Any]) -> List[ProviderProduct]:
        rows = payload.get("itemSummaries")
        if not isinstance(rows, list):
            return []
        products: List[ProviderProduct] = []
        for item in rows:
            if not isinstance(item, dict):
                continue
            title = item.get("title")
            url = item.get("itemWebUrl")
            if not isinstance(title, str) or not isinstance(url, str):
                continue
            seller = item.get("seller") if isinstance(item.get("seller"), dict) else {}
            price_data = item.get("price") if isinstance(item.get("price"), dict) else {}
            price = None
            try:
                if price_data.get("value") is not None and price_data.get("currency"):
                    price = ProviderPrice(
                        amount=float(price_data["value"]),
                        currency=str(price_data["currency"]),
                        display="%s %s" % (price_data["currency"], price_data["value"]),
                    )
            except (TypeError, ValueError):
                price = None
            image = item.get("image") if isinstance(item.get("image"), dict) else {}
            categories = item.get("categories") if isinstance(item.get("categories"), list) else []
            category = None
            if categories and isinstance(categories[0], dict):
                category = categories[0].get("categoryName")
            product = ProviderProduct(
                provider=self.id,
                provider_result_id=str(item.get("itemId")) if item.get("itemId") else None,
                title=title,
                product_url=url,
                merchant=str(seller.get("username") or "eBay"),
                image_url=image.get("imageUrl") if isinstance(image.get("imageUrl"), str) else None,
                category=category if isinstance(category, str) else None,
                price=price,
                source_score=0.58,
                attributes={
                    "condition": item.get("condition"),
                    "buyingOptions": item.get("buyingOptions", []),
                },
            )
            if price:
                product.offers.append(
                    {
                        "merchant": product.merchant,
                        "url": url,
                        "price": price.as_dict(),
                        "condition": item.get("condition"),
                    }
                )
            products.append(product)
        return products

