# Security

## API keys

Gallaxy TTS does not ship with an ElevenLabs API key. Users enter their own key in the app. The key is stored locally on that user's Mac at:

```text
~/Library/Application Support/Gallaxy TTS/elevenlabs-api-key.txt
```

That file is outside the repository and is ignored by `.gitignore` if it is ever copied into the project by accident.

## Before publishing

Run these checks before pushing a public release:

```bash
rg -n --hidden -S "sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|ghp_[0-9A-Za-z]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}" -g '!build/**' -g '!backups/**' -g '!Resources/PiperRuntime/**' -g '!Resources/Models/**' -g '!.git/**'
git grep -n -I -E "sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|ghp_[0-9A-Za-z]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}" $(git rev-list --all)
```

If a real secret ever appears in Git history, revoke it at the provider first, then rewrite history before publishing.
