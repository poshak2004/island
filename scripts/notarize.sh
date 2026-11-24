#!/usr/bin/env bash
# Signs dist/Island.app with a Developer ID, notarizes it with Apple, staples the ticket, and
# rebuilds Island.zip / Island.dmg so downloads open without the "Open Anyway" step.
#
# Needs (once): an Apple Developer Program membership, a "Developer ID Application" certificate in
# your login keychain, and notary credentials saved with:
#   xcrun notarytool store-credentials island-notary --apple-id <you@example.com> --team-id <TEAMID>
#
# Usage:
#   scripts/build-release.sh 0.3.0
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=island-notary scripts/notarize.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Island.app"
ENTITLEMENTS="$ROOT/Resources/Island.entitlements"

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application: Name (TEAMID)' identity (see: security find-identity -v -p codesigning)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a profile saved with 'xcrun notarytool store-credentials'}"
[[ -d "$APP" ]] || { echo "No $APP — run scripts/build-release.sh first" >&2; exit 1; }
security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID" \
  || { echo "Signing identity not found in keychain: $DEVELOPER_ID" >&2; exit 1; }

notarize() { # <file> — submit, wait, and fail loudly with Apple's log if rejected
  local file="$1" out id
  echo "→ notarizing $(basename "$file") (this usually takes a few minutes)…"
  out="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  id="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$out")"
  if ! /usr/bin/python3 -c 'import json,sys; sys.exit(json.load(sys.stdin)["status"] != "Accepted")' <<<"$out"; then
    echo "✗ notarization rejected — Apple's log:" >&2
    xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
    exit 1
  fi
  echo "✓ accepted ($id)"
}

# 1. Developer ID signature with the hardened runtime (required for notarization) and a secure timestamp.
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# 2. Notarize the app (Apple needs an archive), then staple the ticket so it verifies offline.
SUBMIT="$(mktemp -d)/Island.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMIT"
notarize "$SUBMIT"
xcrun stapler staple "$APP"

# 3. Rebuild the downloads from the stapled app; sign, notarize and staple the disk image too.
"$ROOT/scripts/package-release.sh"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DIST/Island.dmg"
notarize "$DIST/Island.dmg"
xcrun stapler staple "$DIST/Island.dmg"
(cd "$DIST" && shasum -a 256 Island.zip Island.dmg > SHA256SUMS.txt)

# 4. Ask Gatekeeper what a downloader will see.
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DIST/Island.dmg"
echo "✓ notarized: $DIST/Island.zip, $DIST/Island.dmg (opens without Open Anyway)"
