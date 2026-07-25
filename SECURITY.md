# Security

## API keys

Gallaxy TTS does not ship with an ElevenLabs API key. Users enter their own key in the app. The key is stored locally in macOS Keychain:

```text
service: app.gallaxy.tts.elevenlabs
account: api-key
```

Older development builds stored the key in `~/Library/Application Support/Gallaxy TTS/elevenlabs-api-key.txt`. Current builds migrate that legacy file into Keychain and delete it after a successful migration or save. The app does not use the plaintext key when Keychain migration fails.

Keychain access is limited to this device and requires the user to be logged in
with the device unlocked.

## Clipboard data

Gallaxy TTS keeps clipboard history in memory for the current app session only. It does not persist clipboard history to `UserDefaults`.

The app updates the current clipboard preview while the widget is open, but recent history is only populated by clips the user chooses to play.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability or exposed
credential. Use GitHub's **Security > Advisories > Report a vulnerability**
flow for this repository so the report and any fix can be coordinated
privately.

If private vulnerability reporting is unavailable, email
[support@gallaxyenterprises.com](mailto:support@gallaxyenterprises.com) with
`SECURITY` in the subject line. Do not include live credentials; revoke an
exposed credential with its provider immediately.

The current `main` branch is supported. Security fixes are released from the
latest version only.

## Before publishing

Run these checks before pushing a public release:

```bash
scripts/validate_source.sh
scripts/audit_public_release.sh
scripts/audit_dependencies.sh
```

If a real secret ever appears in Git history, revoke it at the provider first, then rewrite history before publishing.
