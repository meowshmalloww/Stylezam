#!/bin/sh

# Source this file, then call stylezam_require_xcode27 with the project root.
# It prevents a device install from silently rebuilding without the iOS 27
# ScreenCaptureKit adapter when an older Xcode is still globally selected.
stylezam_require_xcode27() {
    stylezam_project_root=$1

    if [ -z "${DEVELOPER_DIR:-}" ]; then
        stylezam_project_parent=$(dirname "$stylezam_project_root")
        for stylezam_candidate in \
            "/Applications/Xcode-beta.app/Contents/Developer" \
            "$stylezam_project_parent/Xcode-beta.app/Contents/Developer" \
            "/Applications/Xcode.app/Contents/Developer"
        do
            if [ ! -x "$stylezam_candidate/usr/bin/xcodebuild" ]; then
                continue
            fi
            stylezam_candidate_sdk=$(
                DEVELOPER_DIR="$stylezam_candidate" \
                    /usr/bin/xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || true
            )
            stylezam_candidate_major=${stylezam_candidate_sdk%%.*}
            case "$stylezam_candidate_major" in
                ''|*[!0-9]*) continue ;;
            esac
            if [ "$stylezam_candidate_major" -ge 27 ]; then
                DEVELOPER_DIR=$stylezam_candidate
                export DEVELOPER_DIR
                break
            fi
        done
    fi

    stylezam_sdk_version=$(
        /usr/bin/xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || true
    )
    stylezam_sdk_major=${stylezam_sdk_version%%.*}
    case "$stylezam_sdk_major" in
        ''|*[!0-9]*) stylezam_sdk_major=0 ;;
    esac
    if [ "$stylezam_sdk_major" -lt 27 ]; then
        echo "Stylezam requires Xcode 27 and the iOS 27 SDK for Live Screen." >&2
        echo "Set DEVELOPER_DIR to Xcode 27 or install Xcode-beta.app beside the project or in /Applications." >&2
        exit 1
    fi

    stylezam_xcode_version=$(xcodebuild -version | sed -n '1p')
    echo "Using $stylezam_xcode_version with iOS SDK $stylezam_sdk_version."
}
