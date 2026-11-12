#!/usr/bin/env bash
# Ensure the build stub requires sandbox-aware signing support from the engine.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/scripts" "$TMP/repo/App" "$TMP/bin"
cp "$ROOT/scripts/build.sh" "$TMP/repo/scripts/"
cp "$ROOT/project.yml" "$TMP/repo/"
cp "$ROOT/App/Toolchord.entitlements" "$TMP/repo/App/"
cat > "$TMP/bin/xcodegen" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p Toolchord.xcodeproj
STUB
cat > "$TMP/bin/lkm-build" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == --capabilities ]]; then
  [[ "${TEST_OLD_ENGINE:-0}" == 0 ]] || exit 1
  echo BUILD_ADHOC_ENTITLEMENTS
  exit 0
fi
[[ "$*" == --check ]]
[[ "$BUILD_ADHOC_ENTITLEMENTS" == App/Toolchord.entitlements ]]
test -s "$BUILD_ADHOC_ENTITLEMENTS"
echo 'Build stub checks passed'
STUB
chmod +x "$TMP/bin/xcodegen" "$TMP/bin/lkm-build"
export PATH="$TMP/bin:$PATH"
export LKM_BUILD_BIN="$TMP/bin/lkm-build"
cd "$TMP"
bash "$TMP/repo/scripts/build.sh" --check

if TEST_OLD_ENGINE=1 bash "$TMP/repo/scripts/build.sh" --check > "$TMP/old.log" 2>&1; then
  echo 'An old engine must not silently drop App Sandbox restrictions' >&2
  exit 1
fi
grep -q 'App Sandbox support required' "$TMP/old.log"
