import AppKit
import Carbon
import QuartzCore
import SwiftUI

enum DrawerResizeAnchor {
    case left
    case right
}

enum RightDrawerMode {
    case clips
    case hotkey
}

enum GallaxyBrand {
    enum Weight {
        case regular
        case medium
        case semibold
        case bold
    }

    static let pageBackground = color(0x070706)
    static let textMain = color(0xe9e3d5)
    static let textMuted = color(0xe9e3d5).opacity(0.64)
    static let brandMaroon = color(0x6b1f26)
    static let brandMaroonReadable = color(0xa63a43)
    static let brandGreen = color(0x566b57)
    static let borderSubtle = color(0xe9e3d5).opacity(0.15)
    static let panelSurface = color(0xe9e3d5).opacity(0.032)

    static func brandFont(size: CGFloat) -> Font {
        .custom("Audiowide-Regular", size: size)
    }

    static func displayFont(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(displayFontName(for: weight), size: size)
    }

    static func bodyFont(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(bodyFontName(for: weight), size: size)
    }

    private static func displayFontName(for weight: Weight) -> String {
        switch weight {
        case .regular:
            return "Oxanium-Regular"
        case .medium:
            return "Oxanium-Medium"
        case .semibold:
            return "Oxanium-SemiBold"
        case .bold:
            return "Oxanium-Bold"
        }
    }

    private static func bodyFontName(for weight: Weight) -> String {
        switch weight {
        case .regular:
            return "Rubik-Regular"
        case .medium:
            return "Rubik-Medium"
        case .semibold:
            return "Rubik-SemiBold"
        case .bold:
            return "Rubik-Bold"
        }
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }
}
