#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$ROOT_DIR/Resources/Models"
PIPER_DIR="$ROOT_DIR/Resources/PiperRuntime"
TMP_DIR="$ROOT_DIR/build/piper-download"

mkdir -p "$MODELS_DIR" "$PIPER_DIR" "$TMP_DIR"

ALAN_BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium"
LESSAC_BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium"

echo "Installing Piper Python runtime..."
rm -rf "$PIPER_DIR"
mkdir -p "$PIPER_DIR"
python3 -m venv "$PIPER_DIR/venv"
"$PIPER_DIR/venv/bin/python" -m pip install --upgrade pip wheel setuptools
"$PIPER_DIR/venv/bin/python" -m pip install piper-tts

echo "Downloading en_GB-alan-medium British male voice..."
curl -L "$ALAN_BASE_URL/en_GB-alan-medium.onnx" -o "$MODELS_DIR/en_GB-alan-medium.onnx"
curl -L "$ALAN_BASE_URL/en_GB-alan-medium.onnx.json" -o "$MODELS_DIR/en_GB-alan-medium.onnx.json"

echo "Downloading en_US-lessac-medium fallback voice..."
curl -L "$LESSAC_BASE_URL/en_US-lessac-medium.onnx" -o "$MODELS_DIR/en_US-lessac-medium.onnx"
curl -L "$LESSAC_BASE_URL/en_US-lessac-medium.onnx.json" -o "$MODELS_DIR/en_US-lessac-medium.onnx.json"

echo "Piper assets are ready in Resources/."
echo "Run scripts/build_app.sh again so the app bundle includes them."
