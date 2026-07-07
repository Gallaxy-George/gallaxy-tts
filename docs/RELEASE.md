# Release Guide

## What goes on GitHub

Commit the source, scripts, icon assets, app plist, docs, and lightweight helper files.

Do not commit:

- `build/`
- `dist/`
- `backups/`
- `Resources/PiperRuntime/`
- `Resources/KokoroRuntime/`
- `Resources/Models/`
- API keys or local credentials

## Developer install

Developers can clone or download the repository, then run:

```bash
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

Or double-click `start.command` to build, install to `~/Applications`, register the macOS Service, and launch the app.

## Optional local neural voice

Kokoro MLX local speech is installed outside the repository:

```bash
scripts/download_kokoro_assets.sh
scripts/build_app.sh
```

The runtime lives in:

```text
~/Library/Application Support/Gallaxy TTS/KokoroRuntime
```

Piper remains available as a legacy local voice path:

```bash
scripts/download_piper_assets.sh
scripts/build_app.sh
```

Piper downloads into ignored `Resources/` subdirectories so model weights and Python runtimes do not enter Git.

## Release zip

For a local test package:

```bash
scripts/package_release.sh
```

The package script ad hoc signs by default. This seals the bundle for local testing, but it does not make the app trusted by Gatekeeper for public downloads.

Release packages disable bundled Piper models and Piper Python runtimes by default so local downloaded assets do not accidentally ship in a public zip.

For a public GitHub Release that opens cleanly for most users, use a Developer ID Application certificate and notarization:

```bash
xcrun notarytool store-credentials gallaxy-tts --apple-id "<Apple ID email>" --team-id "<TEAM_ID>" --password "<app-specific-password>"
CODESIGN_IDENTITY="<Developer ID Application identity>" NOTARY_PROFILE="gallaxy-tts" scripts/package_release.sh
```

The package is written to `dist/`.

## Validation

```bash
scripts/build_app.sh
scripts/package_release.sh
codesign -dvvv --entitlements :- "build/Gallaxy TTS.app" || true
spctl -a -vv "build/Gallaxy TTS.app" || true
```

Unsigned builds are fine for local development, but public binary downloads should be signed and notarized.
