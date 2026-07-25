# Contributing

Thanks for helping Gallaxy TTS improve.

## Local setup

```bash
scripts/build_app.sh
open "build/Gallaxy TTS.app"
```

For the Kokoro local voice on Apple Silicon:

```bash
scripts/download_kokoro_assets.sh
scripts/build_app.sh
```

Do not commit generated apps, downloaded model weights, local Python runtimes, backups, logs, or API keys. The `.gitignore` file is set up to keep those out of Git.

## Pull requests

Before opening a PR:

```bash
scripts/validate_source.sh
scripts/audit_dependencies.sh
script/build_and_run.sh --verify
```

If you changed packaging or release behavior, also run:

```bash
scripts/package_release.sh
```
