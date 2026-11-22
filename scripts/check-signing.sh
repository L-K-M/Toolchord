#!/usr/bin/env bash
set -euo pipefail
app=${1:?Pass the built Toolchord.app path}
provider="$app/Contents/XPCServices/AuthoringProvider.xpc"
test -x "$provider/Contents/MacOS/AuthoringProvider"
codesign --verify --deep --strict "$app"
entitlements=$(mktemp -d)
trap 'rm -rf "$entitlements"' EXIT
codesign -d --entitlements - --xml "$app" > "$entitlements/palette.plist"
codesign -d --entitlements - --xml "$provider" > "$entitlements/provider.plist"
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements/palette.plist" | grep -qx true
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$entitlements/palette.plist" 2>/dev/null | grep -qx true; then
  echo "The palette must keep its offline sandbox." >&2
  exit 1
fi
if [[ -s "$entitlements/provider.plist" ]] && /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements/provider.plist" 2>/dev/null | grep -qx true; then
  echo "The authoring service received the palette's sandbox entitlements." >&2
  exit 1
fi
