# Release Guide

## What goes on GitHub

Commit the source, scripts, icon assets, app plist, docs, and lightweight helper files.

Do not commit:

- `build/`
- `dist/`
- `backups/`
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

## Release zip

For a local test package:

```bash
scripts/package_release.sh
```

The package script ad hoc signs by default. This seals the bundle for local testing, but it does not make the app trusted by Gatekeeper for public downloads.

Release packages do not bundle the optional Kokoro runtime or model, so
locally downloaded assets cannot accidentally ship in a public zip.

For a public GitHub Release that opens cleanly for most users, use a Developer ID Application certificate and notarization:

```bash
xcrun notarytool store-credentials gallaxy-tts --apple-id "<Apple ID email>" --team-id "<TEAM_ID>" --password "<app-specific-password>"
CODESIGN_IDENTITY="<Developer ID Application identity>" NOTARY_PROFILE="gallaxy-tts" scripts/package_release.sh
```

The package is written to `dist/`.

## History-free source archive

```bash
scripts/package_source.sh
```

This creates a source zip from existing tracked and non-ignored source files.
It excludes `.git`, local backups, generated apps, distributions, downloaded
models, and Python runtimes. Use it to inspect the exact source payload or to
initialize a fresh public history after choosing the intended public commit
identity.

## Validation

```bash
scripts/validate_source.sh
scripts/audit_public_release.sh
scripts/audit_dependencies.sh
scripts/package_release.sh
codesign -dvvv --entitlements :- "build/Gallaxy TTS.app" || true
spctl -a -vv "build/Gallaxy TTS.app" || true
```

Before changing repository visibility, also inspect the output of
`git log --format='%h %an <%ae>' --all` and confirm that every published author
name and email is intended to be public. Review prior CI logs and release
artifacts separately because they are not part of the working tree scan.
`scripts/audit_public_release.sh` intentionally fails on common personal email
providers and local-only commit addresses until the history uses an intended
public identity.

Ad hoc signed builds are fine for local development, but public binary
downloads should be Developer ID signed and notarized.
