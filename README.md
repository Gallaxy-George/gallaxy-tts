# Gallaxy TTS

Gallaxy TTS is a native macOS app for reading selected text out loud from a small widget window, a menu-bar control, a global hotkey, or the macOS Services menu.

```text
Highlight text -> press Option+Space -> Gallaxy TTS speaks it
```

The app can also speak clipboard text, stop/pause/resume playback, pin the widget above other windows, and fall back to Apple's built-in local speech when optional neural voices are not installed.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools: `xcode-select --install`
- Optional for Kokoro local neural TTS: Apple Silicon Mac plus Python 3.10 or newer
- Optional for ElevenLabs cloud TTS: your own ElevenLabs API key

No API key is included in this repository.

## Quick Start

If you are using Codex on a fresh clone, paste this:

```bash
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

The app should open immediately and speak with Apple's built-in local voice. No cloud account, API key, or local model is required for this first run.

Or double-click:

```text
start.command
```

`start.command` builds the app if needed, installs it to `~/Applications/Gallaxy TTS.app`, registers the macOS Service, refreshes Services, and opens the app.

If `scripts/build_app.sh` says `xcrun` or `swiftc` is missing, install Apple's command line tools:

```bash
xcode-select --install
```

## Icon and Menu Bar

The app icon is stored in `Resources/GallaxyTTS.icns` and is copied into the generated `.app` bundle by `scripts/build_app.sh`.

The menu-bar item loads the same bundled icon. If the icon resource is missing, the app falls back to a `GT` text item.

## Voice Modes

Out of the box:

- Apple local speech works immediately.

Optional local neural voice:

- Kokoro 82M through MLX Audio when installed

Optional cloud voice:

- ElevenLabs through a user-provided API key
- The key is saved only on the user's Mac in Application Support

Legacy local voice:

- Piper support is still present for older setups

## Add Kokoro Local Neural TTS

```bash
scripts/download_kokoro_assets.sh
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

This installs MLX Audio into:

```text
~/Library/Application Support/Gallaxy TTS/KokoroRuntime/venv
```

It also prefetches `mlx-community/Kokoro-82M-bf16`. The generated app bundle contains the Kokoro helper scripts and uses the Application Support runtime.

After setup, choose the local/Kokoro voice option in the app. If Kokoro is unavailable for any reason, Gallaxy TTS falls back to Apple's built-in speech.

## Add ElevenLabs Cloud TTS

1. Open Gallaxy TTS.
2. Choose the ElevenLabs voice provider in the widget.
3. Paste your own ElevenLabs API key into the API key field.
4. Save it.

The key is stored only on your Mac:

```text
~/Library/Application Support/Gallaxy TTS/elevenlabs-api-key.txt
```

That local credential file is ignored by Git and should never be committed.

## Legacy Piper Local Neural TTS

```bash
scripts/download_piper_assets.sh
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

This downloads Piper runtime files and voice models into ignored `Resources/` subdirectories. Those large generated assets are not meant to be committed to Git.

## Packaging

Developers can clone or download the repository and run the build script. That is enough to tweak and run the app locally.

For non-developer users, publish a GitHub Release with a zipped `.app`:

```bash
scripts/package_release.sh
```

The package script ad hoc signs local test builds. Those builds can still trigger normal macOS Gatekeeper warnings. For a smoother public download, sign and notarize with an Apple Developer ID certificate:

```bash
CODESIGN_IDENTITY="<Developer ID Application identity>" NOTARY_PROFILE="gallaxy-tts" scripts/package_release.sh
```

See `docs/RELEASE.md` for the full release checklist.

Release packages intentionally exclude locally downloaded Piper runtimes and model weights. Users can install optional local neural voices after downloading the source or app.

## Repository Hygiene

This repo should include source, scripts, docs, helper Python files, fonts, and icon assets.

It should not include:

- API keys
- `build/`
- `dist/`
- `backups/`
- downloaded model weights
- generated Python runtimes
- built `.app` bundles

The `.gitignore` file is set up for those rules.

## License

Gallaxy TTS is released under the MIT License. See `LICENSE`.
