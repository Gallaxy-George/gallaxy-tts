#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Gallaxy TTS"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

if [ -d "$ROOT_DIR/Resources/Models" ]; then
  mkdir -p "$RESOURCES_DIR/Models"
  cp -R "$ROOT_DIR/Resources/Models/." "$RESOURCES_DIR/Models/"
fi

if [ -d "$ROOT_DIR/Resources/PiperRuntime" ]; then
  mkdir -p "$RESOURCES_DIR/PiperRuntime"
  cp -R "$ROOT_DIR/Resources/PiperRuntime/." "$RESOURCES_DIR/PiperRuntime/"
fi

if [ -d "$ROOT_DIR/Resources/Fonts" ]; then
  mkdir -p "$RESOURCES_DIR/Fonts"
  cp -R "$ROOT_DIR/Resources/Fonts/." "$RESOURCES_DIR/Fonts/"
fi

if [ -f "$ROOT_DIR/Resources/GallaxyTTS.icns" ]; then
  cp "$ROOT_DIR/Resources/GallaxyTTS.icns" "$RESOURCES_DIR/GallaxyTTS.icns"
fi

if [ -f "$ROOT_DIR/Resources/piper_synth.py" ]; then
  cp "$ROOT_DIR/Resources/piper_synth.py" "$RESOURCES_DIR/piper_synth.py"
fi

if [ -f "$ROOT_DIR/Resources/piper_worker.py" ]; then
  cp "$ROOT_DIR/Resources/piper_worker.py" "$RESOURCES_DIR/piper_worker.py"
fi

xcrun swiftc \
  -O \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework Carbon \
  -framework CoreText \
  -framework LocalAuthentication \
  -framework Security \
  "$ROOT_DIR"/Sources/GallaxyTTS/*.swift \
  -o "$MACOS_DIR/$APP_NAME"

chmod +x "$MACOS_DIR/$APP_NAME"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
echo "Run with: open '$APP_DIR'"
