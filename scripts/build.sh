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
exec "$BIN" "$@"
