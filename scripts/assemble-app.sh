#!/usr/bin/env bash
# lkm-build's custom assembly hook for Xcode's per-target ad-hoc signing.
set -euo pipefail
config=Release
if [[ "${1:-}" == --debug ]]; then config=Debug; fi
args=(-project "$BUILD_XCODE_PROJECT" -scheme "$BUILD_XCODE_SCHEME" -configuration "$config"
      -derivedDataPath "$BUILD_DERIVED_DATA" -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=-)
if [[ -n "${TOOLCHORD_APP_VERSION:-}" ]]; then args+=("MARKETING_VERSION=$TOOLCHORD_APP_VERSION"); fi
if [[ -n "${TOOLCHORD_BUILD_NUMBER:-}" ]]; then args+=("CURRENT_PROJECT_VERSION=$TOOLCHORD_BUILD_NUMBER"); fi
xcodebuild "${args[@]}" build
bash scripts/check-signing.sh "$BUILD_PRODUCT_PATH"
