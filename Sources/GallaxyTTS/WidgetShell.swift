import AppKit
import Carbon
import QuartzCore
import SwiftUI

struct RetroShell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        GallaxyBrand.brandMaroonReadable,
                        GallaxyBrand.pageBackground,
                        GallaxyBrand.brandMaroon,
                        GallaxyBrand.brandGreen
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                GallaxyBrand.brandMaroonReadable.opacity(0.34),
                                GallaxyBrand.brandMaroon.opacity(0.28),
                                .black.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
            )
            .padding(4)
    }
}

struct GallaxyGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    private let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        content()
    }
}

enum GallaxyDrawerGlassDirection {
    case voice
    case rack
}

struct GallaxyDrawerGlassBackground: View {
    let direction: GallaxyDrawerGlassDirection

    var body: some View {
        drawerSurface
            .padding(bleedInsets)
    }

    @ViewBuilder
    private var drawerSurface: some View {
        let shape = GallaxyDrawerColumnShape(direction: direction, radius: 8)

        shape
            .fill(GallaxyBrand.pageBackground.opacity(0.60))
            .overlay(
                shape.fill(glassGradient)
            )
            .overlay(
                shape.stroke(GallaxyBrand.textMain.opacity(0.24), lineWidth: 1)
            )
    }

    private var bleedInsets: EdgeInsets {
        switch direction {
        case .voice:
            return EdgeInsets(top: 0, leading: -24, bottom: 0, trailing: 0)
        case .rack:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: -24)
        }
    }

    private var glassGradient: LinearGradient {
        switch direction {
        case .voice:
            return LinearGradient(
                colors: [
                    GallaxyBrand.pageBackground.opacity(0.98),
                    GallaxyBrand.brandMaroon.opacity(0.91),
                    GallaxyBrand.brandGreen.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .rack:
            return LinearGradient(
                colors: [
                    GallaxyBrand.brandGreen.opacity(0.88),
                    GallaxyBrand.brandMaroon.opacity(0.91),
                    GallaxyBrand.pageBackground.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct GallaxyDrawerColumnShape: Shape {
    let direction: GallaxyDrawerGlassDirection
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        let c = radius * 0.5522847498
        var path = Path()

        switch direction {
        case .voice:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + radius),
                control1: CGPoint(x: rect.minX + radius - c, y: rect.minY),
                control2: CGPoint(x: rect.minX, y: rect.minY + radius - c)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                control1: CGPoint(x: rect.minX, y: rect.maxY - radius + c),
                control2: CGPoint(x: rect.minX + radius - c, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        case .rack:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control1: CGPoint(x: rect.maxX - radius + c, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + radius - c)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.maxY - radius + c),
                control2: CGPoint(x: rect.maxX - radius + c, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}

enum SpeakerRackSide {
    case left
    case right
}

struct DrawerSpeakerJoinSeal: View {
    let side: SpeakerRackSide

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        GallaxyBrand.textMain.opacity(0.28),
                        GallaxyBrand.brandMaroonReadable.opacity(0.88),
                        GallaxyBrand.brandMaroon.opacity(0.95),
                        GallaxyBrand.pageBackground.opacity(0.86)
                    ],
                    startPoint: side == .left ? .topTrailing : .topLeading,
                    endPoint: side == .left ? .bottomLeading : .bottomTrailing
                )
            )
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                GallaxyBrand.brandMaroon.opacity(0.22),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .accessibilityHidden(true)
    }
}

struct SideSpeakerRack: View {
    let side: SpeakerRackSide
    var expanded = false
    var speakerLevel = 0.0
    var panelLabel = "Side Panel"
    var toggleAction: (() -> Void)?

    var body: some View {
        let wingShape = SpeakerWingShape(side: side, verticalInsetFraction: 0.0, bottomExtension: 3)
        let rimShape = SpeakerWingRimShape(side: side, verticalInsetFraction: 0.0, bottomExtension: 3)

        ZStack {
            wingShape
                .fill(
                    LinearGradient(
                    colors: [
                            GallaxyBrand.textMain,
                            GallaxyBrand.brandMaroonReadable,
                            GallaxyBrand.brandMaroon,
                            GallaxyBrand.pageBackground
                        ],
                        startPoint: side == .left ? .topTrailing : .topLeading,
                        endPoint: side == .left ? .bottomLeading : .bottomTrailing
                    )
                )
                .overlay(
                    rimShape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    GallaxyBrand.textMain.opacity(0.55),
                                    GallaxyBrand.brandMaroonReadable.opacity(0.60),
                                    .black.opacity(0.65)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .clipShape(wingShape)
                )

            VStack(spacing: 10) {
                SpeakerCone(size: 64, level: speakerLevel)
                SpeakerCone(size: 58, level: speakerLevel * 0.82)
                SpeakerCone(size: 52, level: speakerLevel * 0.66)
            }
            .offset(x: side == .left ? -4 : 4, y: 1)

            if let toggleAction {
                Button(action: toggleAction) {
                    Image(systemName: chevronName)
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 28, height: 42)
                }
                .buttonStyle(SpeakerChevronButtonStyle(active: expanded))
                .offset(x: side == .left ? -43 : 43, y: 1)
                .accessibilityLabel(expanded ? "Collapse \(panelLabel)" : "Expand \(panelLabel)")
                .help(expanded ? "Collapse \(panelLabel.lowercased())" : "Expand \(panelLabel.lowercased())")
            } else {
                Image(systemName: side == .left ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.5))
                    .offset(x: side == .left ? -43 : 43, y: 1)
            }
        }
    }

    private var chevronName: String {
        switch side {
        case .left:
            return expanded ? "chevron.right" : "chevron.left"
        case .right:
            return expanded ? "chevron.left" : "chevron.right"
        }
    }
}
