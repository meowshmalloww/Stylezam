from __future__ import annotations

import io
import secrets
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib.parse import unquote, urlsplit

from fastapi import UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError

from .config import Settings
from .errors import StylezamError


@dataclass(frozen=True)
class StoredMedia:
    path: Path
    relative_name: str
    content_type: str
    width: int
    height: int


class MediaStorage:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.root = settings.data_dir / "media"

    async def save_upload(self, upload: UploadFile, *, prefix: str) -> StoredMedia:
        raw = await upload.read(self.settings.max_upload_bytes + 1)
        if len(raw) > self.settings.max_upload_bytes:
            raise StylezamError(
                "image_too_large",
                "The image is larger than the 10 MB upload limit.",
                status_code=413,
            )
        return self.save_image_bytes(raw, prefix=prefix)

    def save_image_bytes(self, raw: bytes, *, prefix: str) -> StoredMedia:
        if not raw:
            raise StylezamError("empty_image", "The uploaded image is empty.", status_code=422)
        try:
            with Image.open(io.BytesIO(raw)) as source:
                source.load()
                image = ImageOps.exif_transpose(source)
                width, height = image.size
                if width < 64 or height < 64:
                    raise StylezamError(
                        "image_too_small",
                        "The image must be at least 64 by 64 pixels.",
                        status_code=422,
                    )
                filename = "%s-%s.jpg" % (prefix, secrets.token_hex(12))
                destination = self.root / filename
                rgb = image.convert("RGB")
                rgb.save(destination, format="JPEG", quality=92, optimize=True)
        except StylezamError:
            raise
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            raise StylezamError(
                "invalid_image",
                "The upload is not a readable JPEG, PNG, HEIC, or WebP image.",
                status_code=422,
            ) from exc
        return StoredMedia(
            path=destination,
            relative_name=filename,
            content_type="image/jpeg",
            width=width,
            height=height,
        )

    def save_pil_image(self, image: Image.Image, *, prefix: str) -> StoredMedia:
        output = io.BytesIO()
        image.convert("RGB").save(output, format="JPEG", quality=92, optimize=True)
        return self.save_image_bytes(output.getvalue(), prefix=prefix)

    def public_url(self, media: StoredMedia) -> Optional[str]:
        if not self.settings.public_base_url:
            return None
        return "%s/media/%s" % (self.settings.public_base_url, media.relative_name)

    def api_url(self, media: StoredMedia, request_base_url: str) -> str:
        if self.settings.public_base_url:
            return "%s/media/%s" % (
                self.settings.public_base_url,
                media.relative_name,
            )
        return "%smedia/%s" % (request_base_url, media.relative_name)

    def path_for_name(self, name: str) -> Path:
        candidate = (self.root / name).resolve()
        if candidate.parent != self.root.resolve():
            raise StylezamError("invalid_media_path", "Invalid media path.", status_code=404)
        return candidate

    def delete_path(self, path: Optional[str]) -> None:
        if not path:
            return
        candidate = Path(path).resolve()
        if candidate.parent == self.root.resolve():
            candidate.unlink(missing_ok=True)

    def delete_media_url(self, value: Optional[str]) -> None:
        if not value:
            return
        path = unquote(urlsplit(value).path)
        marker = "/media/"
        if marker not in path:
            return
        name = path.split(marker, 1)[1]
        if "/" not in name:
            self.delete_path(str(self.root / name))
