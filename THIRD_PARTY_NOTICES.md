# Third-Party Notices

Gallaxy TTS can use third-party software, services, models, and fonts.

## Bundled assets

- The app icon files in `Resources/` are project assets and are copied into the generated app bundle.
- The font files in `Resources/Fonts/` are third-party font files. Keep their license terms with the project before publishing a public release.

## Optional downloaded assets

These are intentionally not committed to Git:

- Kokoro MLX runtime and model files installed by `scripts/download_kokoro_assets.sh`
- Piper runtime and voice models installed by `scripts/download_piper_assets.sh`

Users download those assets locally by running the setup scripts. Review the upstream licenses for any third-party model/runtime before redistributing a prebuilt app bundle that includes them.

## Cloud services

ElevenLabs support requires each user to provide their own API key. No ElevenLabs key is bundled with this repository.
