import AppKit
import OSLog

private let appLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.gallaxy.tts.local",
    category: "App"
)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var responsivenessActivity: NSObjectProtocol?
    private let router = SpeechRequestRouter.shared
    private let selectionFallbackQueue = DispatchQueue(label: "app.gallaxy.tts.selectionFallback", qos: .userInitiated)
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
        beginResponsivenessActivity()
        router.warmUp()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        widgetWindow.showWindow(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let responsivenessActivity {
            ProcessInfo.processInfo.endActivity(responsivenessActivity)
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.toolTip = "Gallaxy TTS"
            if let image = statusBarImage() {
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                item.length = NSStatusItem.variableLength
                button.title = "GT"
            }
        }

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

    private func statusBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "GallaxyTTS", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private func beginResponsivenessActivity() {
        responsivenessActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Keep Gallaxy TTS speech playback responsive."
        )
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
        let startedAt = Date()
        if let clipboardText = clipboardText() {
            appLogger.info("Widget play using clipboard chars=\(clipboardText.count, privacy: .public) elapsedMs=\(self.elapsedMilliseconds(since: startedAt), privacy: .public)")
            router.speak(clipboardText, source: "clipboard")
            return .clipboard(clipboardText)
        }

        if let selectedText = fastSelectionText(timeout: 0.30, startedAt: startedAt) {
            appLogger.info("Widget play using selection chars=\(selectedText.count, privacy: .public) elapsedMs=\(self.elapsedMilliseconds(since: startedAt), privacy: .public)")
            router.speak(selectedText, source: "selection")
            return .selection(selectedText)
        }

        appLogger.info("Widget play found no text elapsedMs=\(self.elapsedMilliseconds(since: startedAt), privacy: .public)")
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

    @objc private func systemDidWake() {
        appLogger.info("System wake detected; refreshing speech engines")
        router.prepareAfterWake()
    }

    @objc private func showWidget() {
        NSApp.activate(ignoringOtherApps: true)
        widgetWindow.showWindow(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func fastSelectionText(timeout: TimeInterval, startedAt: Date) -> String? {
        let sourceApplication = previousApplicationTracker.lastNonGallaxyTTSApplication
        let semaphore = DispatchSemaphore(value: 0)
        var selectedText: String?

        selectionFallbackQueue.async { [hotkeyController] in
            selectedText = hotkeyController.currentSelectionTextFast(from: sourceApplication)
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + timeout)
        guard result == .success else {
            appLogger.info("Widget selection fallback timed out timeoutMs=\(Int(timeout * 1000), privacy: .public) elapsedMs=\(self.elapsedMilliseconds(since: startedAt), privacy: .public)")
            return nil
        }
        return selectedText
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
