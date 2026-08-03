from __future__ import annotations

import httpx

from .config import Settings
from .database import Database
from .providers.ebay import EbayProvider
from .providers.local_vision import CLIPReranker, LocalGarmentVision
from .providers.ollama import OllamaVisionAnalyzer
from .providers.serpapi import SerpAPIProvider
from .providers.youcam import YouCamClothesProvider
from .schemas import CapabilitiesResponse, ProviderCapability
from .services.job_runner import JobRunner
from .services.search_pipeline import SearchPipeline
from .services.tryon_service import TryOnService
from .storage import MediaStorage


class Container:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        settings.prepare_directories()
        self.database = Database(settings.data_dir / "stylezam.sqlite3")
        self.database.initialize()
        self.storage = MediaStorage(settings)
        self.http = httpx.AsyncClient(
            headers={"User-Agent": "Stylezam/0.1"},
            follow_redirects=True,
        )
        self.serpapi = SerpAPIProvider(settings, self.http)
        self.ebay = EbayProvider(settings, self.http)
        self.ollama = OllamaVisionAnalyzer(settings, self.http)
        self.local_vision = LocalGarmentVision(settings, self.storage)
        self.clip = CLIPReranker(settings, self.http)
        self.youcam = YouCamClothesProvider(settings, self.http)
        self.search_pipeline = SearchPipeline(
            settings=settings,
            database=self.database,
            storage=self.storage,
            serpapi=self.serpapi,
            ebay=self.ebay,
            ollama=self.ollama,
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
        image_search = self.ebay.configured or (self.serpapi.configured and public_ingress)
        serpapi_usage = self.database.provider_usage("serpapi")
        ebay_usage = self.database.provider_usage("ebay")
        youcam_usage = self.database.provider_usage("youcam")
        return CapabilitiesResponse(
            text_search=self.serpapi.configured or self.ebay.configured,
            image_search=image_search,
            image_understanding=self.ollama.configured,
            garment_segmentation=self.local_vision.configured,
            visual_reranking=self.clip.configured,
            virtual_try_on=self.youcam.configured,
            public_image_ingress=public_ingress,
            providers=[
                ProviderCapability(
                    id="serpapi-shopping",
                    name="SerpApi Shopping",
                    capability="text_search",
                    configured=self.serpapi.configured,
                    monthly_limit_note="Stylezam cap: %s/%s calls this UTC month. SerpApi has its own account quota."
                    % (serpapi_usage, self.settings.serpapi_monthly_cap),
                    detail="Structured shopping results for text queries.",
                ),
                ProviderCapability(
                    id="serpapi-lens",
                    name="SerpApi Google Lens",
                    capability="image_search",
                    configured=self.serpapi.configured and public_ingress,
                    monthly_limit_note="Shares Stylezam’s %s-call SerpApi cap; each Lens request is one call."
                    % self.settings.serpapi_monthly_cap,
                    detail="Requires STYLEZAM_PUBLIC_BASE_URL so Lens can fetch the image.",
                ),
                ProviderCapability(
                    id="ebay-browse",
                    name="eBay Browse",
                    capability="text_and_image_search",
                    configured=self.ebay.configured,
                    monthly_limit_note="Stylezam cap: %s/%s calls this UTC month; eBay also applies its app quota."
                    % (ebay_usage, self.settings.ebay_monthly_cap),
                    detail="Keyword and Base64 image search; image support varies by marketplace.",
                ),
                ProviderCapability(
                    id="ollama",
                    name="Ollama Vision",
                    capability="image_understanding",
                    configured=self.ollama.configured,
                    monthly_limit_note="Local inference; no per-call bill.",
                    detail="Extracts factual garment attributes and visible text.",
                ),
                ProviderCapability(
                    id="grounded-sam2",
                    name="Grounding DINO + SAM2 + CLIP",
                    capability="segmentation_and_reranking",
                    configured=self.local_vision.configured,
                    monthly_limit_note="Local inference; no per-call bill.",
                    detail="Optional heavyweight local vision extra.",
                ),
                ProviderCapability(
                    id="youcam-clothes-v3",
                    name="YouCam AI Clothes v3",
                    capability="virtual_try_on",
                    configured=self.youcam.configured,
                    monthly_limit_note="Stylezam cap: %s/%s try-on jobs this UTC month; each job also consumes YouCam units."
                    % (youcam_usage, self.settings.youcam_monthly_cap),
                    detail="Server-side upload, asynchronous generation, and persisted result.",
                ),
            ],
        )
