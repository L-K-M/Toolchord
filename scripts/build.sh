#!/usr/bin/env bash
# Builds Toolchord.app from the command line and reveals it in Finder on success.
# Incremental Release build by default; --clean wipes build/ before building.
# Thin stub for the shared lkm-build engine, plus the XcodeGen step the Makefile
# does by hand: Toolchord.xcodeproj is generated (and gitignored), so it is
# regenerated here whenever project.yml is newer.
#
# Usage: scripts/build.sh [--clean] [--debug] [--run] [--install] [--zip] [--dmg]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f project.yml ]] && { [[ ! -d Toolchord.xcodeproj ]] || [[ project.yml -nt Toolchord.xcodeproj ]]; }; then
  echo "==> xcodegen generate"
  xcodegen generate
fi

export BUILD_APP_NAME="Toolchord"
export BUILD_KIND="xcode"
export BUILD_XCODE_PROJECT="Toolchord.xcodeproj"
export BUILD_XCODE_SCHEME="Toolchord"
export BUILD_ADHOC_ENTITLEMENTS="App/Toolchord.entitlements"
export BUILD_DERIVED_DATA="build/DerivedData"
export BUILD_INVOKED_AS="scripts/build.sh"
BIN="${LKM_BUILD_BIN:-lkm-build}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-build not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
if ! "$BIN" --capabilities 2>/dev/null | grep -qx 'BUILD_ADHOC_ENTITLEMENTS'; then
  echo "error: update lkm-build from https://github.com/L-K-M/release-tool and run ./install.sh (App Sandbox support required)" >&2
  exit 1
fi
# Xcode must sign the palette and its XPC service with their own settings.
# The shared engine's default ad-hoc path applies the palette entitlements
# recursively, preventing the provider from using the user's CLI installation.
mode=${BUILD_SIGN_MODE:-adhoc}
if [[ -n ${CODE_SIGN_IDENTITY:-} && -n ${DEVELOPMENT_TEAM:-} ]]; then mode=developer-id; fi
for arg in "$@"; do
  case "$arg" in
    --dev|--developer-id|--adhoc) mode=${arg#--} ;;
    --) break ;;
  esac
done
if [[ "$mode" != adhoc ]]; then exec "$BIN" "$@"; fi

# Use the engine's custom assembly hook, retaining its install/package/reveal
# steps. Forward version overrides to xcodebuild in the assembly script.
config=Release
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) config=Debug; args+=("$1") ;;
    --app-version) export TOOLCHORD_APP_VERSION="${2:?--app-version needs a value}"; shift ;;
    --build) export TOOLCHORD_BUILD_NUMBER="${2:?--build needs a value}"; shift ;;
    --) args+=("$@"); break ;;
    *) args+=("$1") ;;
  esac
  shift
done
export BUILD_KIND=swiftpm
export BUILD_SWIFTPM_ASSEMBLE=scripts/assemble-app.sh
export BUILD_PRODUCT_PATH="$BUILD_DERIVED_DATA/Build/Products/$config/Toolchord.app"
export BUILD_CLEAN_PATHS="$BUILD_DERIVED_DATA dist"
exec "$BIN" ${args[@]+"${args[@]}"}
