#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build/app-validation
sources=()
for source in Sources/GallaxyTTS/*.swift; do
  [[ "$source" == */main.swift ]] || sources+=("$source")
done
xcrun swiftc -target "$(uname -m)-apple-macos13.0" "${sources[@]}" Tests/AppBehaviorTests.swift -o build/app-validation/app-tests
build/app-validation/app-tests
