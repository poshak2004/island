#!/usr/bin/env bash
# Assembles Island.app from a built binary. Usage: scripts/bundle.sh <binary> <out-dir> [version] [build]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$1"; OUT="$2"; VERSION="${3:-0.0.0-dev}"; BUILD="${4:-1}"
APP="$OUT/Island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Island"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Ad-hoc signature: no paid Apple Developer account required. Gives the app a stable identity
# for privacy permissions on this machine; Gatekeeper still treats downloads as unidentified.
codesign --force --deep --sign - --entitlements "$ROOT/Resources/Island.entitlements" "$APP" >/dev/null
echo "$APP"
