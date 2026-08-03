from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from PIL import Image

from ..config import Settings
from ..database import Database, dump_json
from ..errors import ProviderConfigurationError, ProviderUpstreamError, StylezamError
from ..providers.base import ProviderProduct
from ..providers.ebay import EbayProvider
from ..providers.local_vision import CLIPReranker, LocalGarmentVision
from ..providers.ollama import OllamaVisionAnalyzer
from ..providers.serpapi import SerpAPIProvider
from ..schemas import BoundingBox, VisualAttributes
from ..storage import MediaStorage, StoredMedia
from .ranking import rank_products


class SearchPipeline:
    def __init__(
        self,
        *,
        settings: Settings,
        database: Database,
        storage: MediaStorage,
        serpapi: SerpAPIProvider,
        ebay: EbayProvider,
        ollama: OllamaVisionAnalyzer,
        local_vision: LocalGarmentVision,
        clip: CLIPReranker,
    ) -> None:
        self.settings = settings
        self.database = database
        self.storage = storage
        self.serpapi = serpapi
        self.ebay = ebay
        self.ollama = ollama
        self.local_vision = local_vision
        self.clip = clip

    async def run(self, job_id: str) -> None:
        derived_media_paths: List[Path] = []
        try:
            await self._run(job_id, derived_media_paths)
        finally:
            for path in derived_media_paths:
                self.storage.delete_path(str(path))

    async def _run(self, job_id: str, derived_media_paths: List[Path]) -> None:
        job = self.database.get_search_internal(job_id)
        if not job:
            return
        image_path = Path(job["input_media_path"]) if job.get("input_media_path") else None
        user_query = (job.get("query") or "").strip()
        warnings: List[str] = []
        analysis: Optional[VisualAttributes] = None
        retrieval_image = image_path

        self.database.update_search(
            job_id, status="processing", phase="understanding", progress=0.12
        )
        if image_path and job.get("selected_region"):
            retrieval_image = self._crop_region(image_path, job["selected_region"])
            derived_media_paths.append(retrieval_image)

        if image_path and self.local_vision.configured:
            try:
                segmentation = await self.local_vision.segment(retrieval_image or image_path)
                if segmentation.primary_crop:
                    retrieval_image = segmentation.primary_crop.path
                    if retrieval_image not in derived_media_paths:
                        derived_media_paths.append(retrieval_image)
                if segmentation.items:
                    analysis = VisualAttributes(detected_items=segmentation.items)
            except StylezamError as exc:
                warnings.append("Garment segmentation was skipped: %s" % exc.message)

        if image_path and self.ollama.configured:
            try:
                ollama_analysis = await self.ollama.analyze(
                    retrieval_image or image_path, user_query or None
                )
                if analysis and analysis.detected_items:
                    ollama_analysis.detected_items = analysis.detected_items
                analysis = ollama_analysis
            except StylezamError as exc:
                warnings.append("Image understanding was skipped: %s" % exc.message)

        if analysis:
            self.database.update_search(
                job_id,
                analysis_json=dump_json(analysis.model_dump(mode="json")),
            )

        retrieval_query = self._retrieval_query(user_query, analysis)
        self.database.update_search(job_id, phase="retrieving", progress=0.43)
        products, provider_warnings, executed_routes, successful_routes = await self._retrieve(
            image_path=retrieval_image,
            query=retrieval_query,
        )
        warnings.extend(provider_warnings)
        if not products and not self._has_any_route(retrieval_image, retrieval_query):
            missing: List[str] = []
            if retrieval_query and not (self.serpapi.configured or self.ebay.configured):
                missing.append("STYLEZAM_SERPAPI_API_KEY or eBay credentials")
            if retrieval_image and not self.ebay.configured and not (
                self.serpapi.configured and self.settings.public_base_url
            ):
                missing.append(
                    "eBay credentials or STYLEZAM_SERPAPI_API_KEY plus STYLEZAM_PUBLIC_BASE_URL"
                )
            raise ProviderConfigurationError(
                "No configured provider can execute this search input.",
                sorted(set(missing)),
            )
        if not products and executed_routes == 0:
            raise StylezamError(
                "monthly_cap_reached",
                "Every configured product-search route has reached its Stylezam monthly cap.",
                status_code=429,
            )
        if executed_routes > 0 and successful_routes == 0:
            raise ProviderUpstreamError(
                "product_search",
                "Every product-search provider failed. Check Provider notes or retry later.",
            )

        self.database.update_search(job_id, phase="reranking", progress=0.78)
        visual_scores: Optional[List[Optional[float]]] = None
        if retrieval_image and products and self.clip.configured:
            try:
                visual_scores = await self.clip.scores(retrieval_image, products)
            except StylezamError as exc:
                warnings.append("Visual reranking was skipped: %s" % exc.message)

        ranked = rank_products(
            search_id=job_id,
            products=products,
            query=retrieval_query,
            analysis=analysis,
            visual_scores=visual_scores,
            limit=self.settings.search_result_limit,
        )
        self.database.replace_results(job_id, ranked)
        self.database.update_search(
            job_id,
            status="completed",
            phase="completed",
            progress=1.0,
            provider_warnings_json=dump_json(warnings),
            error_code=None,
            error_message=None,
        )

    def _has_any_route(self, image_path: Optional[Path], query: str) -> bool:
        text_route = bool(query and (self.serpapi.configured or self.ebay.configured))
        image_route = bool(
            image_path
            and (
                self.ebay.configured
                or (self.serpapi.configured and self.settings.public_base_url)
            )
        )
        return text_route or image_route

    async def _retrieve(
        self, *, image_path: Optional[Path], query: str
    ) -> Tuple[List[ProviderProduct], List[str], int, int]:
        requests: List[Tuple[str, Any]] = []
        warnings: List[str] = []
        if query and self.serpapi.configured:
            if self._claim("serpapi", self.settings.serpapi_monthly_cap):
                requests.append(("SerpApi Shopping", self.serpapi.search_text(query)))
            else:
                warnings.append("SerpApi Shopping monthly cap reached.")
        if query and self.ebay.configured:
            if self._claim("ebay", self.settings.ebay_monthly_cap):
                requests.append(("eBay keyword search", self.ebay.search_text(query)))
            else:
                warnings.append("eBay keyword-search monthly cap reached.")
        if image_path and self.serpapi.configured:
            media_url = self._public_url_for_path(image_path)
            if media_url and self._claim("serpapi", self.settings.serpapi_monthly_cap):
                requests.append(
                    (
                        "SerpApi Lens",
                        self.serpapi.search_image(media_url, refinement=query or None),
                    )
                )
            elif media_url:
                warnings.append("SerpApi Lens monthly cap reached.")
            else:
                warnings.append(
                    "Google Lens was skipped because STYLEZAM_PUBLIC_BASE_URL is not configured."
                )
        if image_path and self.ebay.configured:
            if self._claim("ebay", self.settings.ebay_monthly_cap):
                requests.append(
                    ("eBay image search", self.ebay.search_image(image_path.read_bytes()))
                )
            else:
                warnings.append("eBay image-search monthly cap reached.")
        if not requests:
            return [], warnings, 0, 0
        values = await asyncio.gather(*(request for _, request in requests), return_exceptions=True)
        products: List[ProviderProduct] = []
        successful_routes = 0
        for (name, _), value in zip(requests, values):
            if isinstance(value, Exception):
                message = getattr(value, "message", str(value))
                warnings.append("%s failed: %s" % (name, message))
            elif isinstance(value, list):
                successful_routes += 1
                products.extend(value)
        return products, warnings, len(requests), successful_routes

    def _claim(self, provider: str, cap: int) -> bool:
        return self.database.claim_provider_call(provider, cap)

    def _public_url_for_path(self, path: Path) -> Optional[str]:
        if not self.settings.public_base_url:
            return None
        return "%s/media/%s" % (self.settings.public_base_url, path.name)

    def _crop_region(self, path: Path, region_data: Dict[str, Any]) -> Path:
        region = BoundingBox.model_validate(region_data)
        with Image.open(path) as image:
            width, height = image.size
            box = (
                int(region.x * width),
                int(region.y * height),
                int((region.x + region.width) * width),
                int((region.y + region.height) * height),
            )
            stored = self.storage.save_pil_image(image.crop(box), prefix="selection")
        return stored.path

    @staticmethod
    def _retrieval_query(
        user_query: str, analysis: Optional[VisualAttributes]
    ) -> str:
        parts: List[str] = []
        if user_query:
            parts.append(user_query)
        if analysis:
            if analysis.search_query:
                parts.append(analysis.search_query)
            elif not user_query:
                attributes = [
                    analysis.brand,
                    *analysis.colors[:2],
                    analysis.subcategory,
                    analysis.category,
                    *analysis.visible_text[:2],
                ]
                parts.extend(str(value) for value in attributes if value)
        unique: List[str] = []
        seen = set()
        for part in parts:
            normalized = part.strip().lower()
            if normalized and normalized not in seen:
                unique.append(part.strip())
                seen.add(normalized)
        return " ".join(unique)[:240]
