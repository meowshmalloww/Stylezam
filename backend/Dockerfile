FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    STYLEZAM_ENVIRONMENT=production \
    STYLEZAM_DATA_DIR=/data

WORKDIR /app

COPY backend/pyproject.toml ./pyproject.toml
COPY backend/src ./src

RUN pip install --upgrade pip && pip install . && mkdir -p /data/media

EXPOSE 8000

CMD ["sh", "-c", "python -m uvicorn stylezam_api.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
