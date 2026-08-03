from __future__ import annotations

import uuid
from typing import Optional
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status

from ...container import Container
from ...errors import ProviderConfigurationError, StylezamError
from ...schemas import TryOnJob
from ..dependencies import get_container, require_api_token


router = APIRouter(
    prefix="/try-ons",
    tags=["try-ons"],
    dependencies=[Depends(require_api_token)],
)
VALID_CATEGORIES = {"auto", "full_body", "upper_body", "lower_body", "shoes"}


@router.post("", response_model=TryOnJob, status_code=status.HTTP_202_ACCEPTED)
async def create_tryon(
    request: Request,
    product_image_url: str = Form(...),
    garment_category: str = Form(default="auto"),
    person_image: UploadFile = File(...),
    container: Container = Depends(get_container),
) -> TryOnJob:
    if not container.youcam.configured:
        raise ProviderConfigurationError(
            "YouCam is required for virtual try-on.", ["STYLEZAM_YOUCAM_API_KEY"]
        )
    parsed = urlsplit(product_image_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise StylezamError(
            "invalid_product_image_url",
            "The product image must be an accessible HTTP or HTTPS URL.",
            status_code=422,
        )
    if garment_category not in VALID_CATEGORIES:
        raise StylezamError(
            "invalid_garment_category",
            "Garment category must be auto, full_body, upper_body, lower_body, or shoes.",
            status_code=422,
        )
    stored = await container.storage.save_upload(person_image, prefix="person")
    if stored.width < 512 or stored.height < 384:
        stored.path.unlink(missing_ok=True)
        raise StylezamError(
            "tryon_image_too_small",
            "YouCam requires a person photo of at least 512 by 384 pixels.",
            status_code=422,
        )
    person_url = container.storage.api_url(stored, str(request.base_url))
    job_id = str(uuid.uuid4())
    container.database.create_tryon(
        job_id=job_id,
        person_media_path=str(stored.path),
        person_image_url=person_url,
        product_image_url=product_image_url,
        garment_category=garment_category,
    )
    container.runner.enqueue_tryon(job_id)
    row = container.database.get_tryon(job_id)
    if not row:
        raise HTTPException(status_code=500, detail="Try-on was not persisted.")
    return TryOnJob.model_validate(row)


@router.get("/{tryon_id}", response_model=TryOnJob)
async def get_tryon(
    tryon_id: str,
    container: Container = Depends(get_container),
) -> TryOnJob:
    row = container.database.get_tryon(tryon_id)
    if not row:
        raise StylezamError("tryon_not_found", "Try-on not found.", status_code=404)
    return TryOnJob.model_validate(row)


@router.delete("/{tryon_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_tryon(
    tryon_id: str,
    container: Container = Depends(get_container),
) -> None:
    if not container.database.get_tryon(tryon_id):
        raise StylezamError("tryon_not_found", "Try-on not found.", status_code=404)
    await container.runner.cancel_tryon(tryon_id)
    row = container.database.delete_tryon(tryon_id)
    if row:
        container.storage.delete_path(row.get("person_media_path"))
        container.storage.delete_media_url(row.get("result_image_url"))
