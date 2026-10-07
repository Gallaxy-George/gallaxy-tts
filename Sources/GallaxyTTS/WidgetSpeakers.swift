import AppKit
import Carbon
import QuartzCore
import SwiftUI

struct SpeakerChevronButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(chevronColor.opacity(configuration.isPressed ? 0.72 : 1))
            .contentShape(Rectangle())
            .shadow(color: GallaxyBrand.textMain.opacity(active ? 0.12 : 0.07), radius: 1, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }

    private var chevronColor: Color {
        active ? GallaxyBrand.brandMaroon : GallaxyBrand.brandMaroon.opacity(0.86)
    }
}

struct SpeakerWingShape: Shape {
    let side: SpeakerRackSide
    var verticalInsetFraction: CGFloat = 0.08
    var bottomExtension: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = rect.minY + rect.height * verticalInsetFraction
        let bottom = rect.maxY - rect.height * verticalInsetFraction + bottomExtension
        let innerX = rect.minX
        let outerX = rect.maxX
        let shelfX = rect.minX + rect.width * 0.26

        path.move(to: CGPoint(x: innerX, y: top))
        path.addLine(to: CGPoint(x: shelfX, y: top))

        path.addCurve(
            to: CGPoint(x: outerX, y: rect.midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.11, y: top),
            control2: CGPoint(x: outerX, y: rect.minY + rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: shelfX, y: bottom),
            control1: CGPoint(x: outerX, y: rect.maxY - rect.height * 0.28),
            control2: CGPoint(x: rect.maxX - rect.width * 0.11, y: bottom)
        )

        path.addLine(to: CGPoint(x: innerX, y: bottom))
        path.addLine(to: CGPoint(x: innerX, y: top))
        path.closeSubpath()

        if side == .left {
            let mirror = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -rect.midX, y: -rect.midY)
            return path.applying(mirror)
        }

        return path
    }
}

struct SpeakerWingRimShape: Shape {
    let side: SpeakerRackSide
    var verticalInsetFraction: CGFloat = 0.08
    var bottomExtension: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = rect.minY + rect.height * verticalInsetFraction
        let bottom = rect.maxY - rect.height * verticalInsetFraction + bottomExtension
        let innerX = rect.minX
        let outerX = rect.maxX
        let shelfX = rect.minX + rect.width * 0.26

        path.move(to: CGPoint(x: innerX, y: top))
        path.addLine(to: CGPoint(x: shelfX, y: top))
        path.addCurve(
            to: CGPoint(x: outerX, y: rect.midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.11, y: top),
            control2: CGPoint(x: outerX, y: rect.minY + rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: shelfX, y: bottom),
            control1: CGPoint(x: outerX, y: rect.maxY - rect.height * 0.28),
            control2: CGPoint(x: rect.maxX - rect.width * 0.11, y: bottom)
        )
        path.addLine(to: CGPoint(x: innerX, y: bottom))

        if side == .left {
            let mirror = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -rect.midX, y: -rect.midY)
            return path.applying(mirror)
        }

        return path
    }
}

struct SpeakerCone: View {
    let size: CGFloat
    var level = 0.0

    private var pulse: CGFloat {
        CGFloat(min(1, max(0, level)))
    }

    var body: some View {
        let coneScale = 1 + pulse * 0.10
        let capScale = 1 + pulse * 0.13

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.10, green: 0.10, blue: 0.09),
                            Color(red: 0.02, green: 0.02, blue: 0.02)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.34),
                        startRadius: size * 0.20,
                        endRadius: size * 0.55
                    )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    GallaxyBrand.textMain.opacity(0.28),
                                    .black.opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                )

            Circle()
                .fill(Color(red: 0.025, green: 0.024, blue: 0.022))
                .frame(width: size * 0.84, height: size * 0.84)
                .shadow(color: .black.opacity(0.66), radius: 2, x: 0, y: 1)

            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.63, green: 0.52, blue: 0.36),
                                Color(red: 0.08, green: 0.07, blue: 0.06)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.32),
                            startRadius: 0,
                            endRadius: 3
                        )
                    )
                    .frame(width: size * 0.075, height: size * 0.075)
                    .offset(y: -(size * 0.43))
                    .rotationEffect(.degrees(Double(index) * 90 + 45))
                    .accessibilityHidden(true)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.78, green: 0.62, blue: 0.40),
                            Color(red: 0.54, green: 0.37, blue: 0.22),
                            Color(red: 0.19, green: 0.13, blue: 0.09)
                        ],
                        center: UnitPoint(x: 0.40, y: 0.32),
                        startRadius: size * 0.04,
                        endRadius: size * 0.34
                    )
                )
                .frame(width: size * 0.68, height: size * 0.68)
                .overlay(
                    Circle()
                        .stroke(.black.opacity(0.72), lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .trim(from: 0.05, to: 0.38)
                        .stroke(GallaxyBrand.textMain.opacity(0.17), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-18))
                )
                .scaleEffect(coneScale)
                .brightness(Double(pulse) * 0.04)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.20, green: 0.22, blue: 0.20),
                            Color(red: 0.045, green: 0.047, blue: 0.045)
                        ],
                        center: UnitPoint(x: 0.36, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.18
                    )
                )
                .frame(width: size * 0.29, height: size * 0.29)
                .overlay(
                    Circle()
                        .stroke(.black.opacity(0.86), lineWidth: 1.6)
                )
                .scaleEffect(capScale)
                .shadow(
                    color: GallaxyBrand.brandMaroonReadable.opacity(0.10 + Double(pulse) * 0.22),
                    radius: 1 + Double(pulse) * 3,
                    x: 0,
                    y: 0
                )
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.035), value: level)
    }
}
