import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Compatibility stubs for macOS 26+ APIs
// =============================================================================
// These stubs exist so the #available(macOS 26.0, *) branches in this file
// compile on older SDKs. They are marked @available(macOS, introduced: 26.0)
// so the compiler knows to only use them inside #available(macOS 26.0, *)
// guards.
//
// At runtime, the #available check returns false on macOS < 26, so the
// fallback (else) code runs instead.
//
// Remove this file when the project's minimum deployment target is macOS 26+.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - GlassEffectContainer

@available(macOS, introduced: 26.0)
public struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat?
    let content: Content

    public var body: some View {
        content
    }

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
}

// MARK: - .glassProminent ButtonStyle

@available(macOS, introduced: 26.0)
public struct GlassProminentButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

@available(macOS, introduced: 26.0)
extension ButtonStyle where Self == GlassProminentButtonStyle {
    public static var glassProminent: GlassProminentButtonStyle {
        GlassProminentButtonStyle()
    }
}

// MARK: - .glass ButtonStyle

@available(macOS, introduced: 26.0)
public struct GlassButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

@available(macOS, introduced: 26.0)
extension ButtonStyle where Self == GlassButtonStyle {
    public static var glass: GlassButtonStyle {
        GlassButtonStyle()
    }
}

// MARK: - .glassEffect View Modifier

@available(macOS, introduced: 26.0)
public struct GlassMaterial {
    public func tint(_ color: Color) -> GlassMaterial { self }
    public func interactive() -> GlassMaterial { self }
    public static var regular: GlassMaterial { GlassMaterial() }
}

@available(macOS, introduced: 26.0)
extension View {
    public func glassEffect(
        _ material: GlassMaterial,
        in shape: some Shape
    ) -> some View {
        self
    }
}

// MARK: - ButtonBorderShape.circle

@available(macOS, introduced: 26.0)
extension ButtonBorderShape {
    public static var circle: ButtonBorderShape {
        .capsule
    }
}