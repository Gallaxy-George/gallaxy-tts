# Gallaxy TTS

Gallaxy TTS is a native macOS widget-style app for fast selected-text speech.

It opens a small window that can be minimized, zoomed, or pinned above other windows.

Primary flow:

```text
Highlight text -> press Option+Space -> Gallaxy TTS copies and speaks the selection
```

You can also use the small Gallaxy TTS window:

```text
Highlight text -> click Play
Copied text -> click Play
```

The macOS Service remains available as a fallback:

```text
Highlight text -> right-click -> Services -> Speak Selection with Gallaxy TTS
```

The app prefers a bundled local Piper voice model when available and falls back to Apple's local `AVSpeechSynthesizer` when Piper assets are not installed.

## Build

```bash
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

After launching once, macOS should register the Service. If the Service does not appear immediately, log out/in or run the app again.

## Normal Start

Double-click:

```text
start.command
```

The launcher builds the app if needed, installs it to `~/Applications/Gallaxy TTS.app`, enables the Service for contextual menus, refreshes macOS Services, and opens Gallaxy TTS.

## Add Piper local neural TTS

```bash
scripts/download_piper_assets.sh
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

This installs/downloads:

- Piper's current macOS Python runtime into `Resources/PiperRuntime/venv`
- `en_GB-alan-medium`, a British English male voice used as the default
- `en_US-lessac-medium`, kept as a fallback voice

The voice model and runtime are bundled into the generated `.app` by `scripts/build_app.sh`.

## Current Scope

- Menu-bar app
- Small widget-style app window
- Global hotkey for selected text
- Play, Stop, Pin controls
- Speech speed slider plus Slower/Faster buttons
- macOS Service receiver for selected text
- Clipboard speaking from the menu bar
- Piper engine via bundled executable/model
- Apple local speech fallback
- Immediate interruption when a new speech request starts
