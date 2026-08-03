from __future__ import annotations

import json
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status

from ...container import Container
from ...errors import StylezamError
from ...schemas import BoundingBox, SearchJob, SearchResultsPage
from ..dependencies import get_container, require_api_token


router = APIRouter(
    prefix="/searches",
    tags=["searches"],
    dependencies=[Depends(require_api_token)],
)


@router.post("", response_model=SearchJob, status_code=status.HTTP_202_ACCEPTED)
async def create_search(
    request: Request,
    query: Optional[str] = Form(default=None),
    selected_region: Optional[str] = Form(default=None),
    image: Optional[UploadFile] = File(default=None),
    container: Container = Depends(get_container),
) -> SearchJob:
    normalized_query = query.strip() if query and query.strip() else None
    if image is None and normalized_query is None:
        raise StylezamError(
            "search_input_required",
            "Add an image, a text description, or both.",
            status_code=422,
        )
    region = None
    if selected_region:
        try:
            region = BoundingBox.model_validate_json(selected_region)
        except ValueError as exc:
            raise StylezamError(
                "invalid_selected_region",
                "The selected image region is invalid.",
                status_code=422,
            ) from exc
    stored = None
    image_url = None
    if image is not None:
        stored = await container.storage.save_upload(image, prefix="search")
        image_url = container.storage.api_url(stored, str(request.base_url))
    job_id = str(uuid.uuid4())
    container.database.create_search(
        job_id=job_id,
        query=normalized_query,
        input_media_path=str(stored.path) if stored else None,
        input_image_url=image_url,
        selected_region=region.model_dump(mode="json") if region else None,
    )
    container.runner.enqueue_search(job_id)
    row = container.database.get_search(job_id)
    if not row:
        raise HTTPException(status_code=500, detail="Search was not persisted.")
    return SearchJob.model_validate(row)


@router.get("/{search_id}", response_model=SearchJob)
async def get_search(
    search_id: str,
    container: Container = Depends(get_container),
) -> SearchJob:
    row = container.database.get_search(search_id)
    if not row:
        raise StylezamError("search_not_found", "Search not found.", status_code=404)
    return SearchJob.model_validate(row)


@router.get("/{search_id}/results", response_model=SearchResultsPage)
async def get_results(
    search_id: str,
    container: Container = Depends(get_container),
) -> SearchResultsPage:
    job = container.database.get_search(search_id)
    if not job:
        raise StylezamError("search_not_found", "Search not found.", status_code=404)
    rows = container.database.get_results(search_id)
    return SearchResultsPage(search_id=search_id, results=rows, total=len(rows))


@router.delete("/{search_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_search(
    search_id: str,
    container: Container = Depends(get_container),
) -> None:
    if not container.database.get_search_internal(search_id):
        raise StylezamError("search_not_found", "Search not found.", status_code=404)
    await container.runner.cancel_search(search_id)
    media_path = container.database.delete_search(search_id)
    container.storage.delete_path(media_path)
