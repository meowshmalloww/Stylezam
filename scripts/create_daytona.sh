#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
model_weights="$project_root/backend/.data/model-packs/garment-rfdetr-seg-small/1.0.1/StylezamGarmentSegmentation.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
sandbox_name=${STYLEZAM_DAYTONA_NAME:-stylezam-api}
monthly_cap=${STYLEZAM_FIREWORKS_MONTHLY_CAP:-100}

if ! command -v daytona >/dev/null 2>&1; then
    echo "Install and authenticate the Daytona CLI before running this script." >&2
    exit 1
fi
if [ ! -f "$model_weights" ]; then
    echo "The verified Core ML model pack is missing. See docs/VISION_BENCHMARK.md." >&2
    exit 1
fi
if [ -z "${STYLEZAM_API_TOKEN:-}" ]; then
    echo "Export STYLEZAM_API_TOKEN with a random service token first." >&2
    exit 1
fi
if [ -z "${STYLEZAM_FIREWORKS_API_KEY:-}" ]; then
    echo "Export STYLEZAM_FIREWORKS_API_KEY first." >&2
    exit 1
fi

cd "$project_root"
daytona create \
    --name "$sandbox_name" \
    --dockerfile backend/Dockerfile \
    --context . \
    --cpu 2 \
    --memory 4096 \
    --disk 10 \
    --auto-stop 0 \
    --auto-delete -1 \
    --public \
    --env STYLEZAM_ENVIRONMENT=production \
    --env STYLEZAM_DATA_DIR=/data \
    --env "STYLEZAM_API_TOKEN=$STYLEZAM_API_TOKEN" \
    --env "STYLEZAM_FIREWORKS_API_KEY=$STYLEZAM_FIREWORKS_API_KEY" \
    --env "STYLEZAM_FIREWORKS_MONTHLY_CAP=$monthly_cap" \
    --env STYLEZAM_PRODUCT_SEARCH_ENABLED=false \
    --env STYLEZAM_VIRTUAL_TRYON_ENABLED=false

echo "Sandbox created without a GPU allocation."
echo "Copy its public port 8000 preview URL from Daytona into Stylezam Developer Debug."
echo "Use the same STYLEZAM_API_TOKEN on the iPhone."
