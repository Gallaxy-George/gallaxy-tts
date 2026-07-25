#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

"$ROOT_DIR/scripts/validate_source.sh"

SCAN_PATTERN='sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}'
REVISION_LIST="$(git rev-list --all)"
if [ -n "$REVISION_LIST" ] &&
  git grep --name-only -I -E "$SCAN_PATTERN" $REVISION_LIST -- \
    ':(exclude)backups/**' ':(exclude)build/**' ':(exclude)dist/**'; then
  echo "A credential-like value was found in reachable Git history." >&2
  exit 1
fi

echo
echo "Git identities that will become public:"
git log --all --format='%an <%ae>' | LC_ALL=C sort -u

if git log --all --format='%ae' |
  rg -i '(@gmail\.com$|@googlemail\.com$|@icloud\.com$|@me\.com$|@outlook\.com$|@hotmail\.com$|@yahoo\.com$|@local$)'; then
  echo
  echo "A personal-provider or local-only Git author email is present in reachable history." >&2
  echo "Choose the intended public Git identity and rewrite history before publishing." >&2
  exit 1
fi

echo
echo "Manually confirm these identities are intentionally public."
echo "Also review hosted CI logs and existing release assets before changing visibility."
echo "Public release audit passed its automated checks."
