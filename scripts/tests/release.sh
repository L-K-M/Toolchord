#!/usr/bin/env bash
# Check the release stub's XcodeGen setup without Xcode, tags, or network access.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/scripts" "$TMP/bin"
cp "$ROOT/scripts/release.sh" "$TMP/repo/scripts/"
cp "$ROOT/project.yml" "$TMP/repo/"

# Model the generated project so the engine can check it before doing any work.
# Copying the spec also lets the test detect a stale generated project.
cat > "$TMP/bin/xcodegen" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == generate ]]
mkdir -p Toolchord.xcodeproj
cp project.yml Toolchord.xcodeproj/project.pbxproj
STUB
cat > "$TMP/bin/lkm-release" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$RELEASE_KIND" == xcode ]]
[[ "$RELEASE_XCODEGEN_YML" == project.yml ]]
[[ "$RELEASE_XCODE_PROJECT" == Toolchord.xcodeproj ]]
[[ "$RELEASE_XCODE_SCHEME" == Toolchord ]]
[[ "$*" == --check ]]
cmp project.yml "$RELEASE_XCODE_PROJECT/project.pbxproj"
echo "Release stub checks passed"
STUB
chmod +x "$TMP/bin/xcodegen" "$TMP/bin/lkm-release"

# Invoke from outside the repo, as an absolute script path may be used anywhere.
cd "$TMP"
export PATH="$TMP/bin:$PATH"
export LKM_RELEASE_BIN="$TMP/bin/lkm-release"
bash "$TMP/repo/scripts/release.sh" --check

# An existing generated project must not override the committed version source.
printf '\n# Changed release spec\n' >> "$TMP/repo/project.yml"
bash "$TMP/repo/scripts/release.sh" --check
