#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build/caption-validation
xcrun swiftc Sources/GallaxyTTS/PlaybackController.swift \
  Sources/GallaxyTTS/SpeechCaption.swift Tests/CaptionPlaybackTests.swift \
  -framework AVFoundation -o build/caption-validation/playback-tests
build/caption-validation/playback-tests
PYTHON="${GALLAXY_KOKORO_PYTHON:-python3}"
"$PYTHON" Tests/test_kokoro_captions.py
