#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="${KOKORO_RUNTIME_DIR:-$HOME/Library/Application Support/Gallaxy TTS/KokoroRuntime}"
VENV_DIR="$RUNTIME_DIR/venv"
MODEL_ID="mlx-community/Kokoro-82M-bf16"
SMOKE_TEXT="$ROOT_DIR/build/kokoro-smoke.txt"
SMOKE_WAV="$ROOT_DIR/build/kokoro-smoke.wav"

python_is_supported() {
  "$1" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
}

choose_python() {
  if [ -n "${PYTHON:-}" ]; then
    if python_is_supported "$PYTHON"; then
      printf '%s\n' "$PYTHON"
      return 0
    fi
    echo "PYTHON must point to Python 3.10 or newer for Kokoro MLX." >&2
    return 1
  fi

  for candidate in \
    python3.13 \
    python3.12 \
    python3.11 \
    python3.10 \
    /opt/homebrew/bin/python3.13 \
    /opt/homebrew/bin/python3.12 \
    /opt/homebrew/bin/python3.11 \
    /opt/homebrew/bin/python3.10 \
    /usr/local/bin/python3.12 \
    /usr/local/bin/python3.11
  do
    if command -v "$candidate" >/dev/null 2>&1 && python_is_supported "$candidate"; then
      command -v "$candidate"
      return 0
    fi
  done

  echo "Kokoro MLX requires Python 3.10 or newer. Install Python 3.11+ or set PYTHON=/path/to/python." >&2
  return 1
}

if [ "$(uname -m)" != "arm64" ]; then
  echo "Kokoro MLX local speech requires Apple Silicon."
  exit 1
fi

PYTHON_BIN="$(choose_python)"

mkdir -p "$RUNTIME_DIR" "$ROOT_DIR/build"

if [ -x "$VENV_DIR/bin/python" ] && ! python_is_supported "$VENV_DIR/bin/python"; then
  echo "Existing Kokoro runtime uses an unsupported Python; rebuilding it..."
  rm -rf "$VENV_DIR"
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "Creating Kokoro Python runtime..."
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

echo "Installing MLX Audio TTS runtime..."
"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV_DIR/bin/python" -m pip install --upgrade "mlx-audio[tts]" "misaki[en]" soundfile

printf "Galaxy TTS Kokoro local voice is ready.\n" > "$SMOKE_TEXT"

echo "Prefetching and testing $MODEL_ID..."
"$VENV_DIR/bin/python" "$ROOT_DIR/Resources/kokoro_synth.py" \
  --text-file "$SMOKE_TEXT" \
  --output "$SMOKE_WAV" \
  --model "$MODEL_ID" \
  --voice "af_bella" \
  --lang-code "a" \
  --speed "1.0"

echo "Kokoro assets are ready in $RUNTIME_DIR."
echo "Smoke test audio: $SMOKE_WAV"
