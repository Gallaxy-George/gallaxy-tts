#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v rg >/dev/null 2>&1 || {
  echo "Source validation requires ripgrep (rg)." >&2
  exit 1
}

plutil -lint Info.plist >/dev/null

for shell_script in scripts/*.sh script/*.sh; do
  [ -e "$shell_script" ] || continue
  bash -n "$shell_script"
done
zsh -n start.command

python3 - <<'PY'
import ast
from pathlib import Path

for source in sorted(Path("Resources").glob("*.py")):
    ast.parse(source.read_text(encoding="utf-8"), filename=str(source))
PY

SCAN_PATTERN='sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}'
if rg -n -I --hidden -S "$SCAN_PATTERN" \
  -g '!.git/**' -g '!build/**' -g '!dist/**' -g '!backups/**'; then
  echo "A credential-like value was found in publishable source." >&2
  exit 1
fi

if rg -n -I --hidden -S '(/Users/[^/[:space:]"'\'']+|[A-Za-z]:\\Users\\[^\\[:space:]"'\'']+)' \
  -g '!scripts/validate_source.sh' \
  -g '!.git/**' -g '!build/**' -g '!dist/**' -g '!backups/**'; then
  echo "A machine-specific user path was found in publishable source." >&2
  exit 1
fi

git diff --check
echo "Source validation passed."
