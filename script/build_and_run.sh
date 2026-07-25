#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Gallaxy TTS"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
MODE="${1:---run}"

build_app() {
  "$ROOT_DIR/scripts/build_app.sh"
}

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

open_app() {
  open "$APP_DIR"
}

verify_launch() {
  open_app
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      echo "$APP_NAME launched successfully."
      return 0
    fi
    sleep 0.5
  done
  echo "$APP_NAME did not remain running after launch." >&2
  return 1
}

case "$MODE" in
  --run)
    stop_running_app
    build_app
    open_app
    ;;
  --verify)
    stop_running_app
    build_app
    verify_launch
    ;;
  --debug)
    stop_running_app
    build_app
    lldb -- "$APP_BINARY"
    ;;
  --logs)
    log stream --level info \
      --predicate 'subsystem == "app.gallaxy.tts.local"'
    ;;
  *)
    echo "Usage: $0 [--run|--verify|--debug|--logs]" >&2
    exit 2
    ;;
esac
