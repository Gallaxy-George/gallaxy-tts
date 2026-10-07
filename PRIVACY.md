# Privacy

Gallaxy TTS does not include analytics, advertising, crash-reporting SDKs, or
other built-in telemetry.

## Text and speech providers

Kokoro is the only active speech provider. Text is synthesized locally on the
user's Mac. The app ignores legacy cloud-provider preferences and does not read
cloud credentials or send narration text to a cloud speech service.

## Clipboard and selected text

While the app is running, its widget reads the current macOS clipboard to show
a clipboard preview. Clipboard text is held in memory only. Recent clip history
contains only clips the user chooses to play, remains in memory for the current
session, and is not persisted to `UserDefaults` or a file.

Startup does not request Accessibility permission. Reading selected text through
the selection shortcut requires macOS Accessibility permission. The app uses
that permission when the user asks it to read the current selection. Its global
shortcut is registered with macOS as one specific key combination; the app does
not install a general system-wide keyboard event monitor.

## Credentials and temporary files

Credentials saved by older versions remain untouched in macOS Keychain; this
Kokoro-only version does not load, migrate, or delete them.

Local speech creates temporary text, audio, and caption files. Text is removed
after synthesis, caption files when loaded or discarded, and audio after playback,
cancellation, or failure. Captions in the widget are held in memory.

## Network access

No Gallaxy TTS server exists. Kokoro setup downloads the pinned Python packages
and model/voice assets. The runtime may check or download missing model assets
from Hugging Face; narration text stays local. Once assets are cached, local
synthesis can run offline.

## Questions and security reports

See [SECURITY.md](SECURITY.md) for the private vulnerability-reporting process,
or contact [support@gallaxyenterprises.com](mailto:support@gallaxyenterprises.com).
