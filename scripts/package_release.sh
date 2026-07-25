#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Gallaxy TTS"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Info.plist")"
ZIP_PATH="$DIST_DIR/Gallaxy-TTS-$VERSION-macOS.zip"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [ -n "$NOTARY_PROFILE" ] && [ "$CODESIGN_IDENTITY" = "-" ]; then
  echo "NOTARY_PROFILE requires a Developer ID CODESIGN_IDENTITY, not ad hoc signing." >&2
  exit 1
fi

"$ROOT_DIR/scripts/validate_source.sh"
"$ROOT_DIR/scripts/build_app.sh"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if [ -n "$NOTARY_PROFILE" ]; then
  echo "Submitting $ZIP_PATH for notarization with keychain profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  rm -f "$ZIP_PATH"
  ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"
fi

if spctl -a -vv "$APP_DIR"; then
  echo "Gatekeeper assessment passed."
else
  echo "Gatekeeper assessment did not pass. This is expected for ad hoc signed local packages."
fi

echo "Packaged $ZIP_PATH"
