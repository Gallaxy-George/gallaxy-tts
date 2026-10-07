import AppKit
import Carbon
import QuartzCore
import SwiftUI

final class WidgetWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: GallaxyTTSWidgetViewModel

    init(
        router: SpeechRequestRouter,
        hotkeyController: HotkeyController,
        playHandler: @escaping () -> WidgetPlayResult?
    ) {
        self.viewModel = GallaxyTTSWidgetViewModel(
            router: router,
            hotkeyController: hotkeyController,
            playHandler: playHandler
        )

        let rootView = GallaxyTTSWidgetView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: GallaxyTTSWidgetViewModel.collapsedWindowWidth,
                height: GallaxyTTSWidgetViewModel.widgetHeight
            ),
            styleMask: [.titled, .fullSizeContentView, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        window.title = "Gallaxy TTS"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        let minimumSize = GallaxyTTSWidgetViewModel.minimumWindowSize(for: GallaxyTTSWidgetViewModel.collapsedWindowWidth)
        window.minSize = minimumSize
        window.contentMinSize = minimumSize
        window.contentAspectRatio = NSSize(
            width: GallaxyTTSWidgetViewModel.collapsedWindowWidth,
            height: GallaxyTTSWidgetViewModel.widgetHeight
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)

        viewModel.window = window
        viewModel.applyPinnedWindowLevel()
        viewModel.applyDrawerWindowSize(animated: false, preserveCurrentScale: false)
        window.delegate = self
        placeWindowOnScreen()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        viewModel.refresh()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func placeWindowOnScreen() {
        guard let window else { return }
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let frame = window.frame
        let x = min(max(visibleFrame.midX - frame.width / 2, visibleFrame.minX + 24), visibleFrame.maxX - frame.width - 24)
        let y = min(max(visibleFrame.midY - frame.height / 2, visibleFrame.minY + 24), visibleFrame.maxY - frame.height - 24)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
