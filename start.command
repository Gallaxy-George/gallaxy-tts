#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILT_APP_PATH="$ROOT_DIR/build/Gallaxy TTS.app"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/Gallaxy TTS.app"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_app.sh"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"
SERVICE_KEY="app.gallaxy.tts.local - Speak Selection with Gallaxy TTS - speakSelection"

echo "Starting Gallaxy TTS..."
echo

if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "Gallaxy TTS.app was not found, so I am building it now."
  "$BUILD_SCRIPT"
  echo
fi

if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "Could not find or build Gallaxy TTS.app."
  echo "Expected it here:"
  echo "$BUILT_APP_PATH"
  echo
  read "unused?Press Return to close this window."
  exit 1
fi

echo "Installing Gallaxy TTS into ~/Applications..."
mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
ditto "$BUILT_APP_PATH" "$APP_PATH"

echo "Registering the macOS right-click Service..."
"$LSREGISTER" -f "$APP_PATH" >/dev/null 2>&1 || true

echo "Enabling Gallaxy TTS in the Services and right-click menus..."
defaults write pbs NSServicesStatus -dict-add "$SERVICE_KEY" '{enabled_context_menu = 1; enabled_services_menu = 1;}' || true
"$PBS" -flush >/dev/null 2>&1 || true

echo "Opening Gallaxy TTS..."
open "$APP_PATH"

echo
echo "Gallaxy TTS is now running."
echo "A small Gallaxy TTS window should open. You can minimize it, zoom it,"
echo "or use the Pin button to keep it above other windows."
echo
echo "How to use it:"
echo "1. Highlight text in an app like Notes, Safari, TextEdit, Mail, etc."
echo "2. Click Play, or press Option+Space."
echo "3. Gallaxy TTS tries selected text first. If none is selected, it reads clipboard."
echo
echo "Use Stop to halt speech. Use Slower/Faster or the slider to adjust speed."
echo
echo "You should also see a small 'GT' item in the macOS menu bar as a backup."
echo "Click GT for Speak Selection, Speak Clipboard, Stop Speaking, Show Widget, or Quit."
echo
echo "Fallback:"
echo "Right-click highlighted text > Services > Speak Selection with Gallaxy TTS."
echo
echo "If the Service does not appear immediately, quit and reopen the app"
echo "you are selecting text from. macOS refreshes Services per app."
echo
read "unused?Press Return to close this window."
