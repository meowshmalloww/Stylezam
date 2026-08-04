FROM python:3.12.13-slim-bookworm@sha256:d50fb7611f86d04a3b0471b46d7557818d88983fc3136726336b2a4c657aa30b

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    STYLEZAM_ENVIRONMENT=production \
    STYLEZAM_DATA_DIR=/data \
    STYLEZAM_MODEL_PACK_DIR=/opt/stylezam/model-packs

WORKDIR /app

COPY backend/requirements.lock ./requirements.lock
RUN python -m pip install --require-hashes --no-deps -r requirements.lock

RUN groupadd --system stylezam \
    && useradd --system --gid stylezam --home-dir /app stylezam \
    && mkdir -p /data/media /opt/stylezam/model-packs \
    && chown -R stylezam:stylezam /data /opt/stylezam

COPY --chown=stylezam:stylezam backend/src ./src
COPY --chown=stylezam:stylezam backend/.data/model-packs /opt/stylezam/model-packs

ENV PYTHONPATH=/app/src

USER stylezam

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/v1/health' % os.getenv('PORT','8000'), timeout=3)"]

CMD ["sh", "-c", "python -m uvicorn stylezam_api.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
