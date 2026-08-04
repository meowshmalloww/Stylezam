from __future__ import annotations

import asyncio

import httpx

from .config import Settings
from .database import Database
from .providers.ebay import EbayProvider
from .providers.garment_labeling import FireworksGarmentLabeler
from .providers.serpapi import SerpAPIProvider
from .providers.vision import fireworks_analyzer
from .providers.youcam import YouCamClothesProvider
from .schemas import CapabilitiesResponse, ProviderCapability
from .services.job_runner import JobRunner
from .services.search_pipeline import (
    DisabledLocalVision,
    DisabledVisualReranker,
    SearchPipeline,
)
from .services.tryon_service import TryOnService
from .storage import MediaStorage


class Container:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        settings.prepare_directories()
        self.database = Database(settings.data_dir / "stylezam.sqlite3")
        self.database.initialize()
        self.storage = MediaStorage(settings)
        # Bound the complete upload/normalization/provider operation so a small
        # 2-core, 4 GB container cannot accumulate many decoded images at once.
        self.garment_analysis_slots = asyncio.Semaphore(
            settings.garment_analysis_concurrency
        )
        self.http = httpx.AsyncClient(
            headers={"User-Agent": "Stylezam/0.1"},
            follow_redirects=True,
        )
        self.serpapi = SerpAPIProvider(settings, self.http)
        self.ebay = EbayProvider(settings, self.http)
        self.fireworks_vision = fireworks_analyzer(settings, self.http)
        self.garment_labeler = FireworksGarmentLabeler(settings, self.http)
        # Product retrieval is intentionally deferred. If it is enabled later,
        # Qwen3.7 Plus is the only configured image-understanding provider.
        self.vision_analyzers = [self.fireworks_vision]
        self.local_vision = DisabledLocalVision()
        self.clip = DisabledVisualReranker()
        self.youcam = YouCamClothesProvider(settings, self.http)
        self.search_pipeline = SearchPipeline(
            settings=settings,
            database=self.database,
            storage=self.storage,
            serpapi=self.serpapi,
            ebay=self.ebay,
            vision_analyzers=self.vision_analyzers,
            local_vision=self.local_vision,
            clip=self.clip,
        )
        self.tryon_service = TryOnService(
            settings=settings,
            database=self.database,
            storage=self.storage,
            provider=self.youcam,
            client=self.http,
        )
        self.runner = JobRunner(
            database=self.database,
            search_pipeline=self.search_pipeline,
            tryon_service=self.tryon_service,
        )

    async def start(self) -> None:
        await self.runner.start()

    async def close(self) -> None:
        await self.runner.stop()
        await self.http.aclose()

    def capabilities(self) -> CapabilitiesResponse:
        public_ingress = bool(self.settings.public_base_url)
        product_search = self.settings.product_search_enabled
        image_search = product_search and (
            self.ebay.configured or (self.serpapi.configured and public_ingress)
        )
        fireworks_usage = self.database.provider_usage("fireworks-garment-labeler")
        model_pack_available = (
            self.settings.resolved_model_pack_dir / "garment-segmentation.json"
        ).is_file()
        return CapabilitiesResponse(
            text_search=product_search and (self.serpapi.configured or self.ebay.configured),
            image_search=image_search,
            image_understanding=self.garment_labeler.configured,
            garment_segmentation=model_pack_available,
            visual_reranking=False,
            virtual_try_on=self.settings.virtual_tryon_enabled and self.youcam.configured,
            public_image_ingress=public_ingress,
            garment_labeling=self.garment_labeler.configured,
            model_pack_available=model_pack_available,
            providers=[
                ProviderCapability(
                    id="fireworks-qwen3p7-plus",
                    name="Qwen3.7 Plus via Fireworks",
                    capability="garment_crop_validation",
                    configured=self.garment_labeler.configured,
                    monthly_limit_note="Stylezam cap: %s/%s calls this UTC month."
                    % (fireworks_usage, self.settings.fireworks_monthly_cap),
                    detail="One bounded multimodal request validates and labels up to the configured crop limit.",
                ),
                ProviderCapability(
                    id="garment-coreml-pack",
                    name="On-device garment model",
                    capability="segmentation",
                    configured=model_pack_available,
                    monthly_limit_note="Downloaded on Wi-Fi; inference stays on the iPhone.",
                    detail="RF-DETR-Seg-Small model pack with Fashionpedia garment and accessory classes.",
                ),
            ],
        )
