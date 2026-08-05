#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
environment_file="$project_root/.env"
device_id=${STYLEZAM_DEVICE_ID:-00008130-000E25423460001C}
team_id=${STYLEZAM_DEVELOPMENT_TEAM:-BM3KAX5ARZ}
derived_data="$project_root/DerivedDataDeviceSearch"

if [ -f "$environment_file" ]; then
    set -a
    # The file is local, ignored, and expected to contain shell-compatible KEY=value pairs.
    . "$environment_file"
    set +a
fi

"$project_root/scripts/generate_project.sh"

xcodebuild \
    -project "$project_root/Stylezam.xcodeproj" \
    -scheme Stylezam \
    -configuration Debug \
    -destination "id=$device_id" \
    -derivedDataPath "$derived_data" \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates \
    build

xcrun devicectl device install app \
    --device "$device_id" \
    "$derived_data/Build/Products/Debug-iphoneos/Stylezam.app"

export DEVICECTL_CHILD_STYLEZAM_FIREWORKS_API_KEY=${STYLEZAM_FIREWORKS_API_KEY:-}
export DEVICECTL_CHILD_STYLEZAM_SERPER_API_KEY=${STYLEZAM_SERPER_API_KEY:-}
export DEVICECTL_CHILD_STYLEZAM_LYKDAT_API_KEY=${STYLEZAM_LYKDAT_API_KEY:-}
export DEVICECTL_CHILD_STYLEZAM_SEARCHAPI_API_KEY=${STYLEZAM_SEARCHAPI_API_KEY:-}
export DEVICECTL_CHILD_STYLEZAM_SERPAPI_API_KEY=${STYLEZAM_SERPAPI_API_KEY:-}
export DEVICECTL_CHILD_STYLEZAM_BRIGHTDATA_API_KEY=${STYLEZAM_BRIGHTDATA_API_KEY:-}
export DEVICECTL_CHILD_STYLEZAM_BRIGHTDATA_ZONE=${STYLEZAM_BRIGHTDATA_ZONE:-}
export DEVICECTL_CHILD_STYLEZAM_YOUCAM_API_KEY=${STYLEZAM_YOUCAM_API_KEY:-}

xcrun devicectl device process launch \
    --device "$device_id" \
    --terminate-existing \
    com.stylezam.app
