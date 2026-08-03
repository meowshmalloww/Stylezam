#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bundled="$project_root/.tools/xcodegen/xcodegen/bin/xcodegen"

if [ -x "$bundled" ]; then
    xcodegen_bin=$bundled
elif command -v xcodegen >/dev/null 2>&1; then
    xcodegen_bin=$(command -v xcodegen)
else
    tool_dir="$project_root/.tools/xcodegen"
    archive=$(mktemp /tmp/stylezam-xcodegen.XXXXXX.zip)
    mkdir -p "$tool_dir"
    curl -L --fail --silent --show-error \
        "https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip" \
        -o "$archive"
    unzip -q -o "$archive" -d "$tool_dir"
    xcodegen_bin="$bundled"
fi

cd "$project_root"
"$xcodegen_bin" generate

