# Building on Older macOS Versions

Gallaxy TTS targets macOS 13 and does not require the macOS 26/Tahoe SDK.

The app previously referenced Tahoe-only SwiftUI Liquid Glass symbols behind `#available(macOS 26.0, *)` checks. That was not enough for users building on Sequoia or older SDKs because Swift still has to resolve those symbols at compile time. The app now uses its bundled retro glass styling everywhere, so public SDKs can compile the source without compatibility stubs.

## Requirements

- macOS 13 or newer
- Apple Xcode Command Line Tools
- Swift toolchain from Xcode/CLT 15 or newer

Install Command Line Tools:

```bash
xcode-select --install
```

Verify the toolchain:

```bash
xcrun --find swiftc
xcrun --sdk macosx --show-sdk-version
```

## Build

From the repository root:

```bash
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

The build script compiles with a macOS 13 deployment target and creates a local `.app` bundle in `build/`.

## Optional Local Neural Voice

Kokoro local TTS is optional. Without it, the app can still speak using Apple's built-in speech.

```bash
scripts/download_kokoro_assets.sh
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

The current secure Kokoro runtime requires macOS 14 or newer, an Apple Silicon
Mac, and Python 3.10 or newer. On macOS 13, Gallaxy TTS continues to use
Apple's built-in local speech.
