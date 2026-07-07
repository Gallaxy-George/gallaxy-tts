# Building Gallaxy TTS on Older macOS Versions

Gallaxy TTS uses SwiftUI APIs introduced in macOS 26 (e.g., `GlassEffectContainer`, `.glassProminent`, `.glassEffect`). This document explains how to build and run the app on older macOS versions without those APIs.

## Requirements

| Dependency | Minimum | Recommended |
|-----------|---------|-------------|
| macOS version | 14.0 | 15.0+ |
| Xcode CLT | 16.0 (macOS 15 SDK) | 16.4+ |
| Swift | 6.0 | 6.1+ |

The app targets macOS 13 in `Info.plist` but actually needs **macOS 14** at minimum for the SwiftUI APIs it uses at runtime. The macOS 26 APIs are gated behind `#available(macOS 26.0, *)` runtime checks — they just need compile-time stubs to build on older SDKs.

## The Two Issues

### 1. Command Line Tools Too Old

**Symptom:** `scripts/build_app.sh` fails with `xcrun: error: unable to find utility "swiftc"` or compiler errors about missing SDK features.

**Cause:** The pre-installed Command Line Tools ship with a macOS SDK that's too old for this project. For example, macOS 15.6 Sequoia ships with CLT that includes the **macOS 13.3 SDK** by default.

**Fix:** Install the latest CLT from Software Update:

```bash
# List available updates
softwareupdate --list

# Install the latest CLT (16.4 as of this writing)
sudo softwareupdate --install "Command Line Tools for Xcode-16.4"

# Verify
swift --version
# Should show: Apple Swift version 6.1+ (swiftlang-6.1.x)
xcrun --sdk macosx --show-sdk-version
# Should show: 15.5 or higher
```

You'll also want **Xcode 16+** (from the Mac App Store or Developer Portal) if you need the full IDE — but the CLT alone is sufficient for `scripts/build_app.sh`.

### 2. macOS 26+ APIs Unavailable at Compile Time

**Symptom:** Compiler errors like:
```
error: cannot find 'GlassEffectContainer' in scope
error: reference to member 'glassProminent' cannot be resolved
error: value of type '...' has no member 'glassEffect'
```

**Cause:** `GallaxyGlassContainer`, `.glassProminent`, `.glassEffect`, `ButtonBorderShape.circle`, and `.glass` button style are macOS 26 APIs that don't exist in any macOS 15 SDK.

The code already uses `#available(macOS 26.0, *)` runtime guards, so the app would work fine at runtime on older systems — but **the compiler still needs the type declarations to exist** at build time.

**Proper fix (not yet applied — see PR #X):** Add compile-time compatibility stubs so the existing `#available` branches compile on older SDKs:

```swift
// Place at the bottom of WidgetWindowController.swift
// or in a separate Compatibility.swift file

#if canImport(SwiftUI)
import SwiftUI

// GlassEffectContainer — introduced in macOS 26
// Provide a compile-time alias so #available branches compile on older SDKs
@available(macOS, unavailable)
public struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat?
    let content: Content
    public var body: some View { content }
    
    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
}

// .glassProminent button style — introduced in macOS 26
@available(macOS, unavailable)
extension ButtonStyle where Self == GlassProminentButtonStyle {
    static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

@available(macOS, unavailable)
struct GlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// .glass button style — introduced in macOS 26
@available(macOS, unavailable)
extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
}

// .glassEffect view modifier — introduced in macOS 26
@available(macOS, unavailable)
extension View {
    func glassEffect(
        _ material: Any,
        in shape: some Shape
    ) -> some View {
        self
    }
}

// ButtonBorderShape.circle — introduced in macOS 26
@available(macOS, unavailable)
extension ButtonBorderShape {
    static var circle: ButtonBorderShape { .capsule }
}
#endif
```

These stubs are marked `@available(macOS, unavailable)` so they only resolve at compile time — the runtime `#available(macOS 26.0, *)` check ensures the fallback code runs instead.

### 3. Swift 5.8 Concurrency Issues (Less Common)

**Symptom:**
```
error: reference to captured var 'self' in concurrently-executing code
```

**Cause:** Swift 5.8 (shipped with Xcode 14.3) is stricter about `[weak self]` + `guard let self` in `@Sendable` closures inside `Task { @MainActor in }` blocks and `DispatchQueue.main.async`.

**Fix:** Upgrade to Swift 6.0+ (Xcode 16+ or CLT 16+) — the Swift 6 compiler handles these patterns correctly without errors. This comes free with the CLT upgrade in step 1.

## Recovery Options

If you can't upgrade your SDK (corporate-managed machine, etc.):

1. **Do what I did temporarily:** Strip the `#available(macOS 26.0, *)` branches and use only the else/fallback paths. The app works fine — it just uses the retro glass styles instead of native macOS 26 glass effects.
2. **Better (not yet done):** Add the compile-time stubs described above, commit them to the repo, and keep the `#available` runtime guards. This preserves forward compatibility.

Option 2 is preferred and should be contributed as a PR to the main repo.

## Verification

After building, confirm the app launches:

```bash
open build/Gallaxy\ TTS.app
```

Check it falls back to Apple speech when Kokoro runtime isn't installed:

```bash
log stream --predicate 'subsystem BEGINSWITH "app.gallaxy"' --style compact
# Expected: "Kokoro warmup failed error=Kokoro MLX runtime is missing."
# Expected: Falls back to Apple speech automatically
```