# Gallaxy TTS

Gallaxy TTS is a native macOS app for reading selected text out loud from a small widget window, a menu-bar control, a global hotkey, or the macOS Services menu.

Gallaxy TTS is a Gallaxy Enterprises project.

```text
Highlight text -> press Option+Space -> Gallaxy TTS speaks it
```

The app can also speak clipboard text, stop/pause/resume playback, and pin the widget above other windows. Kokoro is the only active speech engine.

Startup never requests Accessibility permission. Reading selected text through the global shortcut checks permission silently first and requests it only if needed, at most once per session. Clipboard playback and the macOS Services pasteboard do not require Accessibility permission.

## Requirements

- macOS 14 or newer on Apple Silicon for Kokoro playback
- Xcode Command Line Tools: `xcode-select --install`
- Python 3.10 or newer for the local Kokoro runtime

No API key is included in this repository.

Gallaxy TTS does not require the macOS 26/Tahoe SDK. The app uses its bundled retro glass styling so it can build on current public SDKs, including macOS Sequoia developer machines with Xcode Command Line Tools installed.

## Quick Start

If you are using Codex on a fresh clone, paste this:

```bash
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

The widget opens immediately. Install the Kokoro runtime below before playing text. No cloud account or API key is required.

Or double-click:

```text
start.command
```

`start.command` builds the app if needed, installs it to `~/Applications/Gallaxy TTS.app`, registers the macOS Service, refreshes Services, and opens the app.

If `scripts/build_app.sh` says `xcrun` or `swiftc` is missing, install Apple's command line tools:

```bash
xcode-select --install
```

Local builds retain the existing Gallaxy TTS development identity. macOS manages Accessibility approval for the running app; different installed copies or signing changes can affect that approval. The app never asks at launch. Selection reading requires approval in **System Settings > Privacy & Security > Accessibility**.

## Icon and Menu Bar

The app icon is stored in `Resources/GallaxyTTS.icns` and is copied into the generated `.app` bundle by `scripts/build_app.sh`.

The menu-bar item loads the same bundled icon. If the icon resource is missing, the app falls back to a `GT` text item.

## Voice

Kokoro 82M through MLX Audio is the sole active provider. Older cloud-provider
preferences are ignored. The app does not access saved cloud credentials and
does not silently switch to another voice when Kokoro fails; the existing widget
console reports the failure. Legacy engine source remains for reference, outside
the active request path.

See [PRIVACY.md](PRIVACY.md) for the data-handling summary.

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

It also prefetches a pinned revision of `mlx-community/Kokoro-82M-bf16`.
Python packages are installed from the fully pinned, hash-verified
`config/kokoro-requirements.lock`. The direct requirements used to regenerate
that lock are in `config/kokoro-requirements.txt`. The generated app bundle
contains the Kokoro helper scripts and uses the Application Support runtime.

After setup, Kokoro is selected automatically. If an older runtime is installed,
run the setup script again to bring it into agreement with the checked-in lock.
For isolated development, set `KOKORO_RUNTIME_DIR` when running setup and
`GALLAXY_KOKORO_PYTHON` to that runtime's `venv/bin/python` when launching the app.
The override applies to both persistent and one-shot synthesis.

The pinned MLX Audio 0.4.4 runtime needs a process-local harmonic-length guard
for [upstream issue #803](https://github.com/Blaizzy/mlx-audio/issues/803).
`kokoro_runtime.py` applies that guard after validating dependency versions;
it does not modify the installed package, model, or voice.

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

To produce a history-free source archive containing only publishable,
non-ignored files:

```bash
scripts/package_source.sh
```

Release packages do not bundle the Kokoro runtime or model. Users
install it locally with the setup script.

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
Bundled fonts retain their SIL Open Font License terms; see
`THIRD_PARTY_NOTICES.md` and `Resources/Fonts/OFL-1.1.txt`.

Project support: [support@gallaxyenterprises.com](mailto:support@gallaxyenterprises.com)

### Spoken captions

During narration, the widget display shows large, centered phrases with the
spoken text's punctuation. Pause holds the current phrase; resume continues from
that position. Stop, completion, and a new request clear the previous caption.
The existing widget resize control also scales the captions.

Local Kokoro remains free and uses the same pinned model and voice. Caption
boundaries come from the pinned MLX pipeline's predicted token durations and
are advanced using the audio player's position (including playback speed
changes). These are model-derived timings, not independently measured word
alignment. Segment offsets use the actual generated sample counts. The temporary
caption sidecar is removed when loaded or discarded, and captions are not saved
in preferences.

The legacy Kokoro CLI fallback, which provides no alignment metadata, uses
approximate phrase timing proportional to the audio file's duration. No
microphone or system audio capture is involved.

Caption checks:

```sh
./scripts/test_captions.sh
# Optional: use the Kokoro runtime's Python for its numpy/soundfile dependencies.
GALLAXY_KOKORO_PYTHON=/path/to/runtime/bin/python ./scripts/test_captions.sh
```

### Structure and regression checks

The widget window, state, layout, drawers, speakers, transport controls, theme,
and resize bridge live in separate Swift files. The router owns request state
and cancellation; Kokoro owns synthesis/playback. Run `scripts/test_app.sh` for
permission and routing regressions and `scripts/test_captions.sh` for playback
and caption checks.
