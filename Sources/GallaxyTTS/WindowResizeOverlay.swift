import AppKit
import Carbon
import QuartzCore
import SwiftUI

struct WindowResizeOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleNSView {
        ResizeHandleNSView()
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {}
}

final class ResizeHandleNSView: NSView {
    private enum ResizeRegion {
        case left
        case right
        case top
        case bottom
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    private let hitThickness: CGFloat = 18
    private let cornerLength: CGFloat = 42
    private var activeRegion: ResizeRegion?
    private var initialWindowFrame = NSRect.zero
    private var initialMouseLocation = NSPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        resizeRegion(at: point) == nil ? nil : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x: 0, y: bounds.maxY - cornerLength, width: cornerLength, height: cornerLength), cursor: Self.northWestSouthEastCursor)
        addCursorRect(NSRect(x: bounds.maxX - cornerLength, y: bounds.maxY - cornerLength, width: cornerLength, height: cornerLength), cursor: Self.northEastSouthWestCursor)
        addCursorRect(NSRect(x: 0, y: 0, width: cornerLength, height: cornerLength), cursor: Self.northEastSouthWestCursor)
        addCursorRect(NSRect(x: bounds.maxX - cornerLength, y: 0, width: cornerLength, height: cornerLength), cursor: Self.northWestSouthEastCursor)
        addCursorRect(NSRect(x: hitThickness, y: bounds.maxY - hitThickness, width: max(0, bounds.width - hitThickness * 2), height: hitThickness), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: hitThickness, y: 0, width: max(0, bounds.width - hitThickness * 2), height: hitThickness), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: hitThickness, width: hitThickness, height: max(0, bounds.height - hitThickness * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.maxX - hitThickness, y: hitThickness, width: hitThickness, height: max(0, bounds.height - hitThickness * 2)), cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        activeRegion = resizeRegion(at: convert(event.locationInWindow, from: nil))
        initialWindowFrame = window?.frame ?? .zero
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let activeRegion else { return }
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y
        let nextFrame = resizedFrame(
            for: activeRegion,
            deltaX: deltaX,
            deltaY: deltaY,
            window: window
        )
        window.setFrame(nextFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        activeRegion = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    private func resizeRegion(at point: NSPoint) -> ResizeRegion? {
        let nearLeft = point.x <= hitThickness
        let nearRight = point.x >= bounds.maxX - hitThickness
        let nearBottom = point.y <= hitThickness
        let nearTop = point.y >= bounds.maxY - hitThickness
        let inLeftCorner = point.x <= cornerLength
        let inRightCorner = point.x >= bounds.maxX - cornerLength
        let inBottomCorner = point.y <= cornerLength
        let inTopCorner = point.y >= bounds.maxY - cornerLength

        if inLeftCorner && inTopCorner { return .topLeft }
        if inRightCorner && inTopCorner { return .topRight }
        if inLeftCorner && inBottomCorner { return .bottomLeft }
        if inRightCorner && inBottomCorner { return .bottomRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        return nil
    }

    private func resizedFrame(for region: ResizeRegion, deltaX: CGFloat, deltaY: CGFloat, window: NSWindow) -> NSRect {
        let minimumSize = window.minSize
        let maximumSize = window.maxSize
        let ratio = max(0.1, window.contentAspectRatio.width / max(1, window.contentAspectRatio.height))
        let minimumScale = max(minimumSize.width / initialWindowFrame.width, minimumSize.height / initialWindowFrame.height)
        let maximumScale = min(maximumSize.width / initialWindowFrame.width, maximumSize.height / initialWindowFrame.height)
        let rawScale = rawResizeScale(for: region, deltaX: deltaX, deltaY: deltaY)
        let clampedScale = min(maximumScale, max(minimumScale, rawScale))
        let nextWidth = initialWindowFrame.width * clampedScale
        let nextHeight = nextWidth / ratio

        var nextFrame = initialWindowFrame
        nextFrame.size = NSSize(width: nextWidth, height: nextHeight)

        switch region {
        case .left, .topLeft, .bottomLeft:
            nextFrame.origin.x = initialWindowFrame.maxX - nextWidth
        default:
            break
        }

        switch region {
        case .bottom, .bottomLeft, .bottomRight:
            nextFrame.origin.y = initialWindowFrame.maxY - nextHeight
        default:
            break
        }

        if let visibleFrame = window.screen?.visibleFrame {
            nextFrame.size.width = min(nextFrame.width, visibleFrame.width)
            nextFrame.size.height = min(nextFrame.height, visibleFrame.height)
        }

        return nextFrame
    }

    private func rawResizeScale(for region: ResizeRegion, deltaX: CGFloat, deltaY: CGFloat) -> CGFloat {
        let width = max(1, initialWindowFrame.width)
        let height = max(1, initialWindowFrame.height)

        switch region {
        case .right:
            return (initialWindowFrame.width + deltaX) / width
        case .left:
            return (initialWindowFrame.width - deltaX) / width
        case .top:
            return (initialWindowFrame.height + deltaY) / height
        case .bottom:
            return (initialWindowFrame.height - deltaY) / height
        case .topRight:
            return dominantScale(widthScale: (initialWindowFrame.width + deltaX) / width, heightScale: (initialWindowFrame.height + deltaY) / height)
        case .topLeft:
            return dominantScale(widthScale: (initialWindowFrame.width - deltaX) / width, heightScale: (initialWindowFrame.height + deltaY) / height)
        case .bottomRight:
            return dominantScale(widthScale: (initialWindowFrame.width + deltaX) / width, heightScale: (initialWindowFrame.height - deltaY) / height)
        case .bottomLeft:
            return dominantScale(widthScale: (initialWindowFrame.width - deltaX) / width, heightScale: (initialWindowFrame.height - deltaY) / height)
        }
    }

    private func dominantScale(widthScale: CGFloat, heightScale: CGFloat) -> CGFloat {
        abs(widthScale - 1) >= abs(heightScale - 1) ? widthScale : heightScale
    }

    private static let northWestSouthEastCursor = diagonalCursor(systemName: "arrow.up.left.and.down.right", fallback: .resizeLeftRight)
    private static let northEastSouthWestCursor = diagonalCursor(systemName: "arrow.up.right.and.down.left", fallback: .resizeLeftRight)

    private static func diagonalCursor(systemName: String, fallback: NSCursor) -> NSCursor {
        guard let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return fallback
        }
        image.size = NSSize(width: 22, height: 22)
        return NSCursor(image: image, hotSpot: NSPoint(x: 11, y: 11))
    }
}

struct RetroSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? Color.black.opacity(0.55) : Color.black.opacity(0.32))
            )
            .overlay(Capsule().stroke(.white.opacity(0.20), lineWidth: 1))
    }
}

struct RetroSideButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? .green.opacity(0.95) : .white.opacity(0.82))
            .background(
                Capsule()
                    .fill(configuration.isPressed ? Color.black.opacity(0.58) : Color.black.opacity(0.30))
            )
            .overlay(Capsule().stroke(active ? .green.opacity(0.45) : .white.opacity(0.20), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
