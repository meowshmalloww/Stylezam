#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data="$project_root/DerivedData"

cd "$project_root"
python3 scripts/verify_model_pack_catalog.py
./scripts/generate_project.sh
xcodebuild \
    -project Stylezam.xcodeproj \
    -scheme Stylezam \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

app_bundle="$derived_data/Build/Products/Debug-iphonesimulator/Stylezam.app"
if [ ! -d "$app_bundle/StylezamGarmentSegmentation.mlmodelc" ]; then
    echo "Bundled compiled Core ML model is missing from Stylezam.app." >&2
    exit 1
fi
if [ ! -f "$app_bundle/garment-segmentation.json" ] \
    && [ ! -f "$app_bundle/Models/garment-segmentation.json" ]; then
    echo "Bundled garment manifest is missing from Stylezam.app." >&2
    exit 1
fi

echo "Verified local-only iOS build and bundled Core ML resources."
