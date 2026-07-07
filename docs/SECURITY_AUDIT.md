# Gallaxy TTS — Security & Quality Audit

*Audit date: July 2026*
*Audit performed by: Hermes Agent*

---

## How This Audit Works

An automated agent read every source code file in the Gallaxy TTS codebase, checked for common security mistakes, data privacy issues, and code quality problems. Each finding below includes:

- **What the problem is** (plain English)
- **Where it lives** (file + line)
- **Why it matters** (the real-world risk)
- **How to fix it** (what to change)

---

## 🔴 HIGH: ElevenLabs API Key Stored as Plain Text

**The problem:** When you enter your ElevenLabs API key into the app, it saves it to a file called `elevenlabs-api-key.txt` in your Application Support folder.

**File:** `ElevenLabsCredentialStore.swift`, line 43

**Why it matters:** Any other app running on your Mac — a browser extension, a background utility, even malware — can read that file. The file permissions are set to owner-only (`0600`), but that only stops *other users on the same Mac*, not *other apps under your user account*. On macOS, any app you run has access to your files unless you're in a sandbox.

**How to fix:** Use the macOS Keychain instead. Apple provides `Security.framework` (`SecItemAdd` / `SecItemCopyMatching`) specifically for storing secrets. It's the same system Safari uses to save passwords. The Keychain encrypts the data at rest and only your app can read it.

**How much work:** ~50 lines of code. Add a `KeychainStore` struct with `save(key:)`, `load(key:)`, `delete(key:)` methods, then swap out the file-based store.

---

## 🔴 HIGH: Clipboard History Saved in Plain Text

**The problem:** Every time you copy text and play it through Gallaxy TTS, the app saves it to a clipboard history. Up to 8 clips, up to 16,000 characters each. This is stored in macOS `UserDefaults` — a `.plist` file under your `~/Library/Preferences/`.

**File:** `WidgetWindowController.swift`, lines 504–517

**Why it matters:** This could include passwords you copied from a password manager, credit card numbers, API keys, private messages, or other sensitive text. `UserDefaults` is not encrypted and can be read by any app on your system.

**How to fix (pick one):**
- **Best:** Encrypt clipboard entries before saving. Use the Keychain or encrypt the JSON data with `CryptoKit` before writing to `UserDefaults`.
- **Good:** Store clipboard history only in memory (not persisted between app restarts). Remove the `persistClipboardHistory()` / `loadClipboardHistory()` methods.
- **Simple:** Add a user setting "Save clipboard history" that defaults to OFF. Only persist when the user explicitly opts in.

**How much work:** 30 minutes for the simple fix, a few hours for the Keychain approach.

---

## 🟡 MEDIUM: App Simulates Cmd+C on Other Apps

**The problem:** When the Accessibility API can't read selected text (some apps don't support it), Gallaxy TTS falls back to sending a fake Cmd+C keystroke to the frontmost app. It briefly takes the keyboard away from you.

**File:** `ClipboardSelectionReader.swift`, lines 145–154

```swift
private func sendCopyKeystroke() {
    let cKeyCode: CGKeyCode = 8
    // ... sends Command+C as system-level keyboard events
}
```

**Why it matters:**
1. **Clipboard disruption** — It temporarily replaces your clipboard with the selected text, then restores it. But if another app was monitoring the clipboard (password manager clearing a copied password, clipboard manager app), it could get confused.
2. **Surprising behavior** — Users don't expect an app to inject keystrokes. It makes a sound (C key press) and may interfere with the app you're using.
3. **Anti-pattern** — This technique is sometimes flagged by security tools as potentially suspicious.

**How to fix (pick one):**
- **Best:** Remove the Cmd+C fallback entirely. The Accessibility API path covers most apps. For apps that don't support it, display a message: "Could not read selection. Try copying the text first (Cmd+C), then press Play."
- **Good:** Add a user setting "Allow Cmd+C fallback when accessibility fails" defaulting to OFF. Add a one-time permission dialog when it's about to be used.

**How much work:** 30 minutes to add a toggle, 5 minutes to remove the fallback.

---

## 🟡 MEDIUM: Continuous Clipboard Monitoring

**The problem:** The app polls the system pasteboard every 1 second to detect new clipboard content.

**File:** `WidgetWindowController.swift`, lines 461–471

**Why it matters:** The app is watching everything you copy, even when you're not using it to read text aloud. Every password, URL, credit card number, and snippet you copy is detected and stored in the internal clipboard history.

**How to fix:** Only check the clipboard when the user presses the Play button. Remove the polling timer. If you want the clipboard preview in the UI, only show it when the user explicitly opens the app.

**How much work:** 15 minutes.

---

## 🟡 MEDIUM: No HTTPS Certificate Validation (ElevenLabs)

**The problem:** The ElevenLabs API calls use `URLSession.shared` with default TLS settings — no certificate pinning.

**File:** `ElevenLabsEngine.swift`, line 174

**Why it matters:** If someone intercepts the network traffic (corporate proxy, malicious WiFi, VPN), they could read your API key and the audio being requested. Unlikely for a personal TTS app, but worth noting.

**How to fix:** Implement `URLSessionDelegate` with `urlSession(_:didReceive:completionHandler:)` to add certificate pinning for `api.elevenlabs.io`.

**How much work:** Medium. Pinning requires managing certificates across updates.

---

## 🟢 LOW: WidgetWindowController.swift is 2,787 Lines

**The problem:** One file contains the entire widget UI — view model, all SwiftUI views, AppKit controls, custom shapes, animations, and dozens of component structs all in the same file.

**File:** `WidgetWindowController.swift` — the entire file

**Why it matters:** Hard to navigate, easy to break something, hard to review changes, and poor separation of concerns. A single developer might manage, but it makes collaboration and code review harder.

**How to fix:** Split into:
- `WidgetWindowController.swift` — the NSWindowController (keep)
- `WidgetViewModel.swift` — the view model
- `WidgetViews/` directory with individual component files:
  - `MainDeckView.swift` — the main content area
  - `VoiceProviderPanel.swift` — the voice model selector
  - `SideSpeakerRack.swift` — the speaker visualizers
  - `ButtonStyles.swift` — custom button styles
  - `Sliders.swift` — the speed control
  - `ShapeEffects.swift` — glass backgrounds, gradients

**How much work:** 2–3 hours of careful extraction with testing.

---

## 🟢 LOW: Zero Test Coverage

**The problem:** There are no automated tests — no unit tests, no UI tests, nothing.

**Why it matters:** Without tests, you can't know if a change breaks something without manually launching the app and trying every feature. As the app grows, this becomes a maintenance bottleneck.

**How to fix:** Start with tests for the non-UI parts:
- `TextNormalizer` — test various text inputs (whitespace, unicode, etc.)
- `ElevenLabsCredentialStore` — test save/load/delete cycles
- `SpeechChunks` (in ElevenLabsEngine and PiperEngine) — test chunking logic
- `ClipboardClip` — test title/preview generation

**How much work:** ~1 hour for the initial batch.

---

## 🟢 LOW: Inconsistent Logging

**The problem:** Some parts use `OSLog` (the modern macOS logging system), other parts use `NSLog` or print statements.

**Files:** Various — `ElevenLabsEngine.swift`, `KokoroEngine.swift` use OSLog; `PiperEngine.swift` uses `NSLog`; `FontRegistrar.swift` uses `NSLog`.

**Why it matters:** Minor inconsistency. `OSLog` is better because it's structured, filterable, and doesn't appear in the Terminal unless you ask for it.

**How to fix:** Replace all `NSLog("Gallaxy TTS ...")` calls with `os_log` or `Logger`.

**How much work:** 15 minutes.

---

## 🟢 LOW: AppDelegate Not Marked @MainActor

**The problem:** With Swift 6's strict concurrency checking, the `AppDelegate` should be annotated `@MainActor` since it manages the entire UI lifecycle.

**File:** `AppDelegate.swift`

**Why it matters:** Currently harmless, but future Swift versions may warn or error on unannotated delegate classes.

**How to fix:** Add `@MainActor` annotation to `AppDelegate`, `WidgetWindowController`, and `SettingsWindowController`.

**How much work:** 10 minutes.

---

## 🟢 LOW: Heterogeneous Collection Warning

**The problem:** The ElevenLabs request payload dictionary is inferred as `[String: Any]` implicitly.

**File:** `ElevenLabsEngine.swift`, line 153

**How to fix:** Add `: [String: Any]` type annotation to the payload variable declaration.

**How much work:** 1 minute.

---

## Summary Table

| # | Issue | Severity | Effort | Impact |
|---|-------|----------|--------|--------|
| 1 | ElevenLabs key as plaintext file | 🔴 HIGH | 2–4 hours | API key theft |
| 2 | Clipboard history in plaintext | 🔴 HIGH | 30 min–2 hrs | All copied data exposed |
| 3 | Cmd+C keystroke injection | 🟡 MEDIUM | 5–30 min | Surprising/invasive |
| 4 | Continuous clipboard polling | 🟡 MEDIUM | 15 min | Privacy concern |
| 5 | No cert pinning on ElevenLabs | 🟡 MEDIUM | Complex | MITM risk |
| 6 | 2,787-line Widget file | 🟢 LOW | 2–3 hours | Maintainability |
| 7 | Zero tests | 🟢 LOW | 1 hour | Quality assurance |
| 8 | Inconsistent logging | 🟢 LOW | 15 min | Consistency |
| 9 | Missing @MainActor | 🟢 LOW | 10 min | Future-proofing |
| 10 | Explicit type warning | 🟢 LOW | 1 min | Clean build |

---

## Recommended Order

1. **Do first (highest impact, lowest effort):** Fix the plaintext clipboard history (#2) and Cmd+C fallback (#3) — 1 hour total, massive privacy improvement.
2. **Do second:** Migrate the ElevenLabs API key to Keychain (#1) — this is the most technically critical fix.
3. **Do third:** Split the giant file (#6) and add tests (#7) — makes the codebase maintainable for future work.
4. **Do whenever:** The small cleanups (#8, #9, #10) — trivially easy.
5. **Consider but can skip:** Certificate pinning (#5) — real but overkill for a personal TTS app.

---

*This document was generated by an automated code audit. It is not a substitute for a professional security review.*