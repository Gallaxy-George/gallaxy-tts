# Privacy

Gallaxy TTS does not include analytics, advertising, crash-reporting SDKs, or
other built-in telemetry.

## Text and speech providers

- **Apple local speech:** Text is synthesized by macOS on the user's Mac.
- **Kokoro local speech:** Text is synthesized by the optional Kokoro runtime
  on the user's Mac.
- **ElevenLabs cloud speech:** When the user selects ElevenLabs and requests
  speech, the requested text is sent over HTTPS to ElevenLabs for synthesis.
  ElevenLabs receives the text and the user's API credential according to its
  own service terms and privacy policy. Gallaxy TTS does not proxy that request.

No text is sent to ElevenLabs unless the ElevenLabs provider is selected.

## Clipboard and selected text

While the app is running, its widget reads the current macOS clipboard to show
a clipboard preview. Clipboard text is held in memory only. Recent clip history
contains only clips the user chooses to play, remains in memory for the current
session, and is not persisted to `UserDefaults` or a file.

Reading selected text requires macOS Accessibility permission. The app uses
that permission when the user asks it to read the current selection. Its global
shortcut is registered with macOS as one specific key combination; the app does
not install a general system-wide keyboard event monitor.

## Credentials and temporary files

An ElevenLabs API key entered by the user is stored in macOS Keychain with
device-only accessibility while the user is logged in and the device is
unlocked. It is not written to application preferences or bundled with the app.

Cloud and local neural speech may create temporary audio files for playback.
Gallaxy TTS removes those files after playback, cancellation, or failure.

## Network access

Normal Apple and Kokoro speech playback does not require Gallaxy TTS to contact
a Gallaxy TTS server; no such server exists. Network access is used for:

- ElevenLabs synthesis when that provider is selected.
- The optional Kokoro setup script, which downloads its pinned Python
  dependencies and model snapshot.

## Questions and security reports

See [SECURITY.md](SECURITY.md) for the private vulnerability-reporting process,
or contact [support@gallaxyenterprises.com](mailto:support@gallaxyenterprises.com).
