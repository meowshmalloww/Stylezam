#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ ! -x "$project_root/.venv/bin/pytest" ]; then
    echo "Run ./scripts/bootstrap_backend.sh first." >&2
    exit 1
fi

cd "$project_root/backend"
"$project_root/.venv/bin/pytest" -q

cd "$project_root"
"$project_root/.venv/bin/python" scripts/verify_model_pack_catalog.py
"$project_root/scripts/generate_project.sh"
xcodebuild \
    -project Stylezam.xcodeproj \
    -scheme Stylezam \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build
