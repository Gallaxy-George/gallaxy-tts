#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v uvx >/dev/null 2>&1 || {
  echo "Dependency auditing requires uvx: https://docs.astral.sh/uv/" >&2
  exit 1
}

uvx pip-audit \
  --disable-pip \
  --require-hashes \
  --requirement config/kokoro-requirements.lock \
  --progress-spinner off \
  --format columns
