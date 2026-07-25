#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Gallaxy TTS"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LOCAL_REQUIREMENTS="$ROOT_DIR/config/GallaxyTTS.local.requirements"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Gallaxy TTS needs Apple's command line tools to build." >&2
  echo "Install them with: xcode-select --install" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

if [ -d "$ROOT_DIR/Resources/Fonts" ]; then
  mkdir -p "$RESOURCES_DIR/Fonts"
  cp -R "$ROOT_DIR/Resources/Fonts/." "$RESOURCES_DIR/Fonts/"
fi

mkdir -p "$RESOURCES_DIR/Legal"
for legal_file in LICENSE PRIVACY.md SECURITY.md THIRD_PARTY_NOTICES.md; do
  cp "$ROOT_DIR/$legal_file" "$RESOURCES_DIR/Legal/$legal_file"
done

if [ -f "$ROOT_DIR/Resources/GallaxyTTS.icns" ]; then
  cp "$ROOT_DIR/Resources/GallaxyTTS.icns" "$RESOURCES_DIR/GallaxyTTS.icns"
fi

if [ -f "$ROOT_DIR/Resources/kokoro_synth.py" ]; then
  cp "$ROOT_DIR/Resources/kokoro_synth.py" "$RESOURCES_DIR/kokoro_synth.py"
fi

if [ -f "$ROOT_DIR/Resources/kokoro_worker.py" ]; then
  cp "$ROOT_DIR/Resources/kokoro_worker.py" "$RESOURCES_DIR/kokoro_worker.py"
fi

xcrun swiftc \
  -O \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework Carbon \
  -framework CoreText \
  -framework Security \
  "$ROOT_DIR"/Sources/GallaxyTTS/*.swift \
  -o "$MACOS_DIR/$APP_NAME"

chmod +x "$MACOS_DIR/$APP_NAME"

if [ "$CODESIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - --requirements "$LOCAL_REQUIREMENTS" "$APP_DIR"
else
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
echo "Run with: open '$APP_DIR'"
