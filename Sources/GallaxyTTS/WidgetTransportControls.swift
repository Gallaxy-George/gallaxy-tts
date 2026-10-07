import AppKit
import Carbon
import QuartzCore
import SwiftUI

struct GallaxyHoverGlow: ViewModifier {
    let radius: CGFloat
    let scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .shadow(
                color: GallaxyBrand.brandMaroonReadable.opacity(hovering ? 0.46 : 0),
                radius: hovering ? radius : 0,
                x: 0,
                y: hovering ? 2 : 0
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func gallaxyHoverGlow(radius: CGFloat, scale: CGFloat) -> some View {
        modifier(GallaxyHoverGlow(radius: radius, scale: scale))
    }
}

struct GallaxySpeedControl: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> GallaxySpeedSliderControl {
        let control = GallaxySpeedSliderControl()
        control.minimumValue = range.lowerBound
        control.maximumValue = range.upperBound
        control.setSpeedValue(value, notify: false)
        control.target = context.coordinator
        control.action = #selector(Coordinator.speedChanged(_:))
        return control
    }

    func updateNSView(_ nsView: GallaxySpeedSliderControl, context: Context) {
        context.coordinator.parent = self
        nsView.minimumValue = range.lowerBound
        nsView.maximumValue = range.upperBound
        nsView.setSpeedValue(value, notify: false)
    }

    final class Coordinator: NSObject {
        var parent: GallaxySpeedControl

        init(_ parent: GallaxySpeedControl) {
            self.parent = parent
        }

        @objc func speedChanged(_ sender: GallaxySpeedSliderControl) {
            parent.value = sender.speedValue
        }
    }
}

final class GallaxySpeedSliderControl: NSControl {
    var minimumValue: Double = 0.75 {
        didSet { setSpeedValue(speedValue, notify: false) }
    }

    var maximumValue: Double = 1.6 {
        didSet { setSpeedValue(speedValue, notify: false) }
    }

    private(set) var speedValue: Double = 1.15
    private var hovering = false
    private var dragging = false
    private var tracking: NSTrackingArea?

    private let knobDiameter: CGFloat = 25
    private let trackHeight: CGFloat = 16

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 34) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Speed")
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Speed")
        updateAccessibilityValue()
    }

    func setSpeedValue(_ nextValue: Double, notify: Bool) {
        let clamped = min(maximumValue, max(minimumValue, nextValue))
        guard abs(clamped - speedValue) > 0.0001 else {
            updateAccessibilityValue()
            return
        }

        speedValue = clamped
        needsDisplay = true
        updateAccessibilityValue()

        if notify, let action {
            sendAction(action, to: target)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
        let nextTracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(nextTracking)
        tracking = nextTracking
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragging = true
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow, .downArrow:
            setSpeedValue(speedValue - 0.05, notify: true)
        case .rightArrow, .upArrow:
            setSpeedValue(speedValue + 0.05, notify: true)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        setSpeedValue(speedValue + 0.05, notify: true)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        setSpeedValue(speedValue - 0.05, notify: true)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let progress = CGFloat((speedValue - minimumValue) / max(0.001, maximumValue - minimumValue))
        let knobRadius = knobDiameter / 2
        let trackRect = NSRect(
            x: knobRadius,
            y: bounds.midY - trackHeight / 2,
            width: max(1, bounds.width - knobDiameter),
            height: trackHeight
        )
        let progressWidth = max(trackHeight, trackRect.width * min(1, max(0, progress)))
        let progressRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: min(trackRect.width, progressWidth),
            height: trackRect.height
        )
        let knobX = trackRect.minX + trackRect.width * min(1, max(0, progress))
        let knobRect = NSRect(
            x: knobX - knobRadius,
            y: bounds.midY - knobRadius,
            width: knobDiameter,
            height: knobDiameter
        )

        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.gallaxyHex(0x070706, alpha: hovering || dragging ? 0.88 : 0.72).setFill()
        trackPath.fill()
        NSColor.gallaxyHex(0xe9e3d5, alpha: hovering || dragging ? 0.22 : 0.14).setStroke()
        trackPath.lineWidth = 1
        trackPath.stroke()

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        let progressPath = NSBezierPath(roundedRect: progressRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        let progressGradient = NSGradient(colors: [
            NSColor.gallaxyHex(0x6b1f26, alpha: 0.96),
            NSColor.gallaxyHex(0xa63a43, alpha: 0.98),
            NSColor.gallaxyHex(0xe9e3d5, alpha: 0.72)
        ])
        progressGradient?.draw(in: progressPath, angle: 0)

        let shineRect = NSRect(x: trackRect.minX, y: trackRect.midY, width: trackRect.width, height: trackRect.height / 2)
        NSColor.white.withAlphaComponent(hovering || dragging ? 0.12 : 0.08).setFill()
        NSBezierPath(roundedRect: shineRect, xRadius: shineRect.height / 2, yRadius: shineRect.height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        let knobPath = NSBezierPath(ovalIn: knobRect)
        NSShadow.gallaxy(color: .black.withAlphaComponent(0.48), blur: dragging ? 5 : 4, y: dragging ? 2 : 3) {
            NSGradient(colors: [
                NSColor.gallaxyHex(0xe9e3d5, alpha: 0.98),
                NSColor.gallaxyHex(0xbeb6a7, alpha: 0.95),
                NSColor.gallaxyHex(0x566b57, alpha: 0.58)
            ])?.draw(in: knobPath, angle: -90)
        }

        NSColor.gallaxyHex(0xe9e3d5, alpha: dragging ? 0.58 : 0.34).setStroke()
        knobPath.lineWidth = dragging ? 2 : 1.4
        knobPath.stroke()
    }

    private func updateValue(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let knobRadius = knobDiameter / 2
        let usableWidth = max(1, bounds.width - knobDiameter)
        let progress = min(1, max(0, (point.x - knobRadius) / usableWidth))
        let nextValue = minimumValue + Double(progress) * (maximumValue - minimumValue)
        setSpeedValue(nextValue, notify: true)
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue(String(format: "%.2fx", speedValue))
    }
}

private extension NSColor {
    static func gallaxyHex(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private extension NSShadow {
    static func gallaxy(color: NSColor, blur: CGFloat, y: CGFloat, draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -y)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct GallaxyPlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 24, weight: .black))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(RetroRoundButtonStyle())
        .gallaxyHoverGlow(radius: 7, scale: 1.045)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityLabel("Play")
    }
}

struct GallaxyStopButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: 16, weight: .black))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(RetroStopButtonStyle(active: active))
        .gallaxyHoverGlow(radius: 5, scale: 1.04)
        .accessibilityLabel("Stop")
    }
}

struct GallaxyPinButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: active ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(RetroPinButtonStyle(active: active))
        .gallaxyHoverGlow(radius: 4, scale: 1.08)
        .accessibilityLabel(active ? "Unpin Window" : "Pin Window")
    }
}

struct GlassPlayButtonBackground: View {
    let pressed: Bool

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: pressed
                        ? [GallaxyBrand.brandMaroon.opacity(0.92), GallaxyBrand.pageBackground.opacity(0.86)]
                        : [GallaxyBrand.brandMaroonReadable.opacity(0.96), GallaxyBrand.brandMaroon.opacity(0.78), GallaxyBrand.pageBackground.opacity(0.66)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                GallaxyBrand.textMain.opacity(pressed ? 0.16 : 0.28),
                                .clear
                            ],
                            center: UnitPoint(x: 0.32, y: 0.24),
                            startRadius: 1,
                            endRadius: 30
                        )
                    )
            )
    }
}

struct GlassStopButtonBackground: View {
    let active: Bool
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        shape
            .fill(
                LinearGradient(
                    colors: pressed
                        ? [GallaxyBrand.pageBackground, GallaxyBrand.brandMaroon.opacity(0.52)]
                        : [GallaxyBrand.textMain.opacity(0.22), GallaxyBrand.pageBackground.opacity(0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                GallaxyBrand.textMain.opacity(active ? 0.13 : 0.08),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }
}

struct GlassPinButtonBackground: View {
    let active: Bool
    let pressed: Bool

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: active
                        ? [GallaxyBrand.textMain.opacity(pressed ? 0.14 : 0.22), GallaxyBrand.brandMaroon.opacity(0.48)]
                        : [GallaxyBrand.textMain.opacity(pressed ? 0.12 : 0.18), GallaxyBrand.pageBackground.opacity(0.70)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

struct GlassRowButtonBackground: View {
    let active: Bool
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        shape
            .fill(active ? GallaxyBrand.brandMaroonReadable.opacity(0.34) : GallaxyBrand.pageBackground.opacity(pressed ? 0.42 : 0.26))
    }
}

struct GlassCommandButtonBackground: View {
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        shape
            .fill(pressed ? GallaxyBrand.brandMaroon.opacity(0.74) : GallaxyBrand.pageBackground.opacity(0.36))
    }
}

struct RetroSpeedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let knobSize: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let progress = progress(for: value)
            let usableWidth = max(1, geometry.size.width - knobSize)
            let knobX = knobSize / 2 + usableWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(GallaxyBrand.pageBackground.opacity(0.72))
                    .frame(height: 7)
                    .padding(.horizontal, knobSize / 2)
                    .overlay(
                        Capsule()
                            .stroke(GallaxyBrand.borderSubtle, lineWidth: 1)
                            .padding(.horizontal, knobSize / 2)
                    )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                GallaxyBrand.brandMaroon.opacity(0.76),
                                GallaxyBrand.brandMaroonReadable.opacity(0.94)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, knobX - knobSize / 2), height: 5)
                    .padding(.leading, knobSize / 2)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                GallaxyBrand.textMain.opacity(0.96),
                                GallaxyBrand.textMain.opacity(0.64)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: knobSize, height: knobSize)
                    .overlay(Circle().stroke(GallaxyBrand.borderSubtle, lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
                    .position(x: knobX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        setValue(from: gesture.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel("Speed")
        .accessibilityValue(Text(String(format: "%.2fx", value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(range.upperBound, value + 0.05)
            case .decrement:
                value = max(range.lowerBound, value - 0.05)
            @unknown default:
                break
            }
        }
    }

    private func progress(for value: Double) -> CGFloat {
        let span = max(0.001, range.upperBound - range.lowerBound)
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        return CGFloat((clamped - range.lowerBound) / span)
    }

    private func setValue(from locationX: CGFloat, width: CGFloat) {
        let usableWidth = max(1, width - knobSize)
        let rawProgress = (locationX - knobSize / 2) / usableWidth
        let clampedProgress = min(1, max(0, rawProgress))
        let nextValue = range.lowerBound + Double(clampedProgress) * (range.upperBound - range.lowerBound)
        value = nextValue
    }
}

struct RetroStopButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? GallaxyBrand.textMain : GallaxyBrand.textMain.opacity(0.94))
            .background(GlassStopButtonBackground(active: active, pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(active ? GallaxyBrand.brandMaroonReadable.opacity(0.48) : GallaxyBrand.borderSubtle, lineWidth: 1.2)
            )
            .shadow(color: GallaxyBrand.brandMaroon.opacity(configuration.isPressed ? 0.16 : 0.32), radius: configuration.isPressed ? 1 : 4, x: 0, y: configuration.isPressed ? 1 : 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct RetroPinButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? GallaxyBrand.textMain : GallaxyBrand.textMain.opacity(0.86))
            .background(GlassPinButtonBackground(active: active, pressed: configuration.isPressed))
            .overlay(
                Circle()
                    .stroke(active ? GallaxyBrand.brandMaroonReadable.opacity(0.62) : GallaxyBrand.textMain.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: active ? GallaxyBrand.brandMaroonReadable.opacity(0.24) : .clear, radius: 4, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

struct RetroRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(GallaxyBrand.textMain)
            .background(GlassPlayButtonBackground(pressed: configuration.isPressed))
            .overlay(Circle().stroke(GallaxyBrand.textMain.opacity(0.22), lineWidth: 1.5))
            .shadow(color: GallaxyBrand.brandMaroonReadable.opacity(configuration.isPressed ? 0.12 : 0.34), radius: configuration.isPressed ? 1 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.2 : 0.5), radius: configuration.isPressed ? 1 : 4, x: 0, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
    }
}

struct RetroTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(0.88))
            .background(
                Capsule()
                    .fill(configuration.isPressed ? Color.gray.opacity(0.45) : Color.black.opacity(0.32))
            )
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
