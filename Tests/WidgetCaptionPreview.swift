import AppKit
import SwiftUI

@main
struct WidgetCaptionPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        FontRegistrar.registerBundledFonts()
        let router = SpeechRequestRouter.shared
        let model = GallaxyTTSWidgetViewModel(router: router, hotkeyController: HotkeyController(router: router), playHandler: { nil })
        model.leftDrawerExpanded = false
        model.rightDrawerExpanded = false
        model.isSpeaking = true
        model.caption = "“Wait,” she said, “is this working?”"
        let view = NSHostingView(rootView: GallaxyTTSWidgetView(viewModel: model))
        let size = NSSize(width: GallaxyTTSWidgetViewModel.collapsedWindowWidth, height: 350)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.center()
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
            app.terminate(nil)
        }
        app.run()
    }
}
