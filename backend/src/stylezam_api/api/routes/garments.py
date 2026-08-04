from __future__ import annotations

import json
import logging
import uuid
from pathlib import Path
from typing import List
from urllib.parse import quote

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import FileResponse
from pydantic import TypeAdapter, ValidationError

from ...container import Container
from ...errors import StylezamError
from ...schemas import (
    GarmentAnalysisResponse,
    GarmentInputMetadata,
    ModelPackManifest,
)
from ..dependencies import get_container, require_api_token


router = APIRouter(tags=["garments"])
metadata_adapter = TypeAdapter(List[GarmentInputMetadata])
logger = logging.getLogger(__name__)


@router.post("/garment-analyses", response_model=GarmentAnalysisResponse)
async def analyze_garment_crops(
    metadata: str = Form(...),
    images: List[UploadFile] = File(...),
    _: None = Depends(require_api_token),
    container: Container = Depends(get_container),
) -> GarmentAnalysisResponse:
    try:
        items = metadata_adapter.validate_python(json.loads(metadata))
    except (json.JSONDecodeError, ValidationError) as exc:
        raise StylezamError(
            "invalid_garment_metadata",
            "Garment metadata must be a valid JSON array.",
            status_code=422,
        ) from exc

    if not items or len(items) > container.settings.garment_analysis_max_items:
        raise StylezamError(
            "invalid_garment_count",
            "Send between 1 and %s garment crops."
            % container.settings.garment_analysis_max_items,
            status_code=422,
        )
    if len(images) != len(items):
        raise StylezamError(
            "garment_count_mismatch",
            "Each garment metadata entry must have one image crop.",
            status_code=422,
        )
    total_upload_bytes = sum(upload.size or 0 for upload in images)
    if total_upload_bytes > container.settings.garment_analysis_total_upload_bytes:
        raise StylezamError(
            "garment_upload_too_large",
            "The garment crop batch is larger than the configured upload limit.",
            status_code=413,
        )
    if len({item.item_id for item in items}) != len(items):
        raise StylezamError(
            "duplicate_garment_id",
            "Every garment crop must have a unique itemID.",
            status_code=422,
        )
    if not container.garment_labeler.configured:
        raise StylezamError(
            "provider_configuration_required",
            "Fireworks garment labeling is not configured.",
            status_code=503,
            details={"missing": ["STYLEZAM_FIREWORKS_API_KEY"]},
        )

    stored_paths: List[Path] = []
    try:
        async with container.garment_analysis_slots:
            actual_total_bytes = 0
            for upload in images:
                stored = await container.storage.save_upload(upload, prefix="garment-label")
                stored_paths.append(stored.path)
                actual_total_bytes += stored.path.stat().st_size
                if actual_total_bytes > container.settings.garment_analysis_total_upload_bytes:
                    raise StylezamError(
                        "garment_upload_too_large",
                        "The normalized garment crop batch is larger than the configured upload limit.",
                        status_code=413,
                    )
            if not container.database.claim_provider_call(
                "fireworks-garment-labeler",
                container.settings.fireworks_monthly_cap,
            ):
                raise StylezamError(
                    "monthly_cap_reached",
                    "The configured monthly Fireworks labeling cap has been reached.",
                    status_code=429,
                    retryable=False,
                )
            labels = await container.garment_labeler.label(stored_paths, items)
            return GarmentAnalysisResponse(
                id=str(uuid.uuid4()),
                provider=container.garment_labeler.id,
                model=container.settings.fireworks_vision_model,
                items=labels,
            )
    finally:
        for path in stored_paths:
            container.storage.delete_path(str(path))


@router.get(
    "/model-packs/garment-segmentation",
    response_model=ModelPackManifest,
)
async def garment_model_pack(
    request: Request,
    _: None = Depends(require_api_token),
    container: Container = Depends(get_container),
) -> ModelPackManifest:
    catalog_path = container.settings.resolved_model_pack_dir / "garment-segmentation.json"
    if not catalog_path.is_file():
        raise StylezamError(
            "model_pack_unavailable",
            "The garment model pack has not been published to this server.",
            status_code=404,
        )
    try:
        payload = json.loads(catalog_path.read_text(encoding="utf-8"))
        storage_prefix = str(payload.pop("storagePrefix")).strip("/")
        base_url = (container.settings.public_base_url or str(request.base_url)).rstrip("/")
        actual_total = 0
        for file in payload["files"]:
            relative_path = str(file["path"]).lstrip("/")
            storage_path = "%s/%s" % (storage_prefix, relative_path)
            resolved = (container.settings.resolved_model_pack_dir / storage_path).resolve()
            if container.settings.resolved_model_pack_dir.resolve() not in resolved.parents:
                raise ValueError("model pack path escapes its root")
            if not resolved.is_file():
                raise FileNotFoundError(relative_path)
            if resolved.stat().st_size != int(file["bytes"]):
                raise ValueError("model pack file size does not match its catalog")
            actual_total += resolved.stat().st_size
            file["url"] = "%s/v1/model-pack-files/%s" % (
                base_url,
                quote(storage_path, safe="/"),
            )
        if actual_total != int(payload["totalBytes"]):
            raise ValueError("model pack total size does not match its catalog")
        return ModelPackManifest.model_validate(payload)
    except (KeyError, OSError, ValueError, ValidationError) as exc:
        logger.exception("Published garment model pack failed validation")
        raise StylezamError(
            "invalid_model_pack",
            "The published garment model pack is incomplete or invalid.",
            status_code=503,
        ) from exc


@router.get("/model-pack-files/{storage_path:path}", response_class=FileResponse)
async def garment_model_pack_file(
    storage_path: str,
    _: None = Depends(require_api_token),
    container: Container = Depends(get_container),
) -> FileResponse:
    model_root = container.settings.resolved_model_pack_dir.resolve()
    requested = Path(storage_path)
    catalog_path = model_root / "garment-segmentation.json"
    try:
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        prefix = Path(str(catalog["storagePrefix"]))
        allowed_paths = {
            (prefix / str(entry["path"])).as_posix()
            for entry in catalog["files"]
        }
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        logger.exception("Published garment model-pack allowlist is invalid")
        raise StylezamError(
            "invalid_model_pack",
            "The published garment model pack is incomplete or invalid.",
            status_code=503,
        ) from exc
    resolved = (model_root / requested).resolve()
    if (
        requested.is_absolute()
        or ".." in requested.parts
        or requested.as_posix() not in allowed_paths
        or model_root not in resolved.parents
        or not resolved.is_file()
    ):
        raise StylezamError(
            "model_pack_file_not_found",
            "The requested model-pack file does not exist.",
            status_code=404,
        )
    return FileResponse(
        path=resolved,
        media_type="application/octet-stream",
        filename=resolved.name,
    )
