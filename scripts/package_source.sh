#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Info.plist")"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/Gallaxy-TTS-$VERSION-source.zip"
STAGE_ROOT="$(mktemp -d -t gallaxy-tts-source)"
SOURCE_ROOT="$STAGE_ROOT/Gallaxy-TTS-$VERSION-source"

cleanup() {
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/validate_source.sh"

mkdir -p "$SOURCE_ROOT" "$DIST_DIR"
while IFS= read -r -d '' source_file; do
  [ -f "$source_file" ] || [ -L "$source_file" ] || continue
  destination="$SOURCE_ROOT/$source_file"
  mkdir -p "$(dirname "$destination")"
  ditto "$source_file" "$destination"
done < <(git ls-files --cached --others --exclude-standard -z)

rm -f "$ARCHIVE_PATH"
ditto -c -k --norsrc --keepParent "$SOURCE_ROOT" "$ARCHIVE_PATH"

if zipinfo -1 "$ARCHIVE_PATH" |
  rg -i '(^|/)(\.git|build|dist|backups|__MACOSX)(/|$)|/\._'; then
  echo "The source archive contains a private or generated path." >&2
  exit 1
fi

echo "Packaged history-free source at $ARCHIVE_PATH"
