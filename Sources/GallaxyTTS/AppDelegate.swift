import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let router = SpeechRequestRouter.shared
    private lazy var previousApplicationTracker = PreviousApplicationTracker(
        ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.gallaxy.tts.local"
    )
    private lazy var hotkeyController = HotkeyController(router: router)
    private lazy var widgetWindow = WidgetWindowController(
        router: router,
        playHandler: { [weak self] in self?.playFromWidget() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        FontRegistrar.registerBundledFonts()

        ServiceProvider.shared.router = router
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()

        previousApplicationTracker.start()
        setupStatusItem()
        hotkeyController.start()
        router.warmUp()
        widgetWindow.showWindow(nil)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "GT"
        item.button?.toolTip = "Gallaxy TTS"

        let menu = NSMenu()
        let speakSelectionItem = NSMenuItem(title: "Speak Selection", action: #selector(speakSelection), keyEquivalent: " ")
        speakSelectionItem.keyEquivalentModifierMask = [.option]
        menu.addItem(speakSelectionItem)
        menu.addItem(NSMenuItem(title: "Speak Clipboard", action: #selector(speakClipboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop Speaking", action: #selector(stopSpeaking), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Widget", action: #selector(showWidget), keyEquivalent: "w"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Gallaxy TTS", action: #selector(quit), keyEquivalent: "q"))

        for menuItem in menu.items {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    @objc private func speakSelection() {
        speakSelectionFromPreviousApp()
    }

    private func speakSelectionFromPreviousApp() {
        hotkeyController.speakCurrentSelection(
            from: previousApplicationTracker.lastNonGallaxyTTSApplication,
            restoreApplication: NSRunningApplication.current
        )
    }

    private func playFromWidget() -> WidgetPlayResult {
        if let selectedText = hotkeyController.currentSelectionTextFast(
            from: previousApplicationTracker.lastNonGallaxyTTSApplication
        ) {
            router.speak(selectedText, source: "selection")
            return .selection(selectedText)
        }

        if let clipboardText = clipboardText() {
            router.speak(clipboardText, source: "clipboard")
            return .clipboard(clipboardText)
        }

        return .empty
    }

    @objc private func speakClipboard() {
        _ = speakClipboardText(beepOnFailure: true)
    }

    @discardableResult
    private func speakClipboardText(beepOnFailure: Bool) -> Bool {
        guard let text = clipboardText() else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }
        router.speak(text, source: "clipboard")
        return true
    }

    private func clipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @objc private func stopSpeaking() {
        router.stop()
    }

    @objc private func showWidget() {
        NSApp.activate(ignoringOtherApps: true)
        widgetWindow.showWindow(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
