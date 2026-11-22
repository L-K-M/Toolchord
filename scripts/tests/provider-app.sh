#!/usr/bin/env bash
# Exercise the packaged provider through a signed sandboxed client and localhost.
# The client uses the same connection code as the palette. No CLI turn is sent.
set -euo pipefail
cd "$(dirname "$0")/../.."
app=${1:?Pass a signed Toolchord.app}
tmp=$(mktemp -d)
server=
cleanup() {
  if [[ -n "$server" ]]; then
    kill "$server" 2>/dev/null || true
    wait "$server" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
probe="$tmp/ProviderProbe.app"
mkdir -p "$probe/Contents/MacOS" "$probe/Contents/XPCServices" "$tmp/module"
ditto "$app/Contents/XPCServices/AuthoringProvider.xpc" "$probe/Contents/XPCServices/AuthoringProvider.xpc"
cat > "$probe/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>ch.lkmc.Toolchord.IntegrationProbe</string>
<key>CFBundleExecutable</key><string>Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
swiftc -swift-version 6 -emit-library -static -emit-module -module-name ToolchordProviderIPC \
  Sources/ToolchordProviderIPC/*.swift -emit-module-path "$tmp/module/ToolchordProviderIPC.swiftmodule" \
  -o "$tmp/module/libToolchordProviderIPC.a"
swiftc -swift-version 6 -parse-as-library -I "$tmp/module" -L "$tmp/module" -lToolchordProviderIPC \
  Sources/ToolchordMac/CustomTools/ProviderHostClient.swift scripts/tests/ProviderProbe.swift \
  -o "$probe/Contents/MacOS/Probe"
codesign --force --sign - --entitlements App/Toolchord.entitlements "$probe"
python3 scripts/tests/provider-fixture.py > "$tmp/port" &
server=$!
for ((i=0; i<100; i++)); do
  [[ -s "$tmp/port" ]] && break
  sleep 0.05
done
test -s "$tmp/port"
args=("http://127.0.0.1:$(cat "$tmp/port")/v1")
if [[ "${TOOLCHORD_TEST_HARNESS_DISCOVERY:-}" == 1 ]]; then args+=(--list-installed-models); fi
"$probe/Contents/MacOS/Probe" "${args[@]}"
