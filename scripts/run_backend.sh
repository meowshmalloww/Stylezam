#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ ! -x "$project_root/.venv/bin/python" ]; then
    echo "Run ./scripts/bootstrap_backend.sh first." >&2
    exit 1
fi

cd "$project_root/backend"
exec "$project_root/.venv/bin/python" -m uvicorn stylezam_api.main:app \
    --host "${STYLEZAM_HOST:-127.0.0.1}" \
    --port "${STYLEZAM_PORT:-8000}"

