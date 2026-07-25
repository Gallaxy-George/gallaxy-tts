# Third-Party Notices

Gallaxy TTS can use third-party software, services, models, and fonts.

## Bundled assets

- The app icon files in `Resources/` are project assets and are copied into the generated app bundle.
- Audiowide: Copyright (c) 2012, Brian J. Bonislawsky DBA
  Astigmatic (AOETI), with Reserved Font Name "Audiowide".
- Oxanium: Copyright 2019 The Oxanium Project Authors.
- Rubik: Copyright 2015 The Rubik Project Authors.

The bundled font files are licensed under the SIL Open Font License 1.1. The
app and repository include the required copyright notices and license text in
`Resources/Fonts/OFL-1.1.txt`.

## Optional downloaded assets

These are intentionally not committed to Git:

- Kokoro MLX runtime and model files installed by `scripts/download_kokoro_assets.sh`

Users download those assets locally by running the setup scripts. Review the upstream licenses for any third-party model/runtime before redistributing a prebuilt app bundle that includes them.

## Cloud services

ElevenLabs support requires each user to provide their own API key. No ElevenLabs key is bundled with this repository.
