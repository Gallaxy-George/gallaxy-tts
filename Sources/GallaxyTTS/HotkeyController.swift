import AppKit
import ApplicationServices
import Carbon
import OSLog

private let hotkeyLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.gallaxy.tts.local",
    category: "Hotkey"
)

final class HotkeyController {
    private weak var router: SpeechRequestRouter?
    private let selectionReader = ClipboardSelectionReader()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var didRequestAccessibilityPermission = false
    private var activeConfiguration: HotkeyConfiguration?

    init(router: SpeechRequestRouter) {
        self.router = router
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func start() {
        requestAccessibilityIfNeeded()
        let handlerStatus = installEventHandler()
        guard handlerStatus == noErr else {
            hotkeyLogger.error("Could not install hotkey event handler status=\(handlerStatus, privacy: .public)")
            return
        }

        let configuration = HotkeyConfiguration.load()
        let result = registerHotkey(configuration)
        switch result {
        case .success:
            activeConfiguration = configuration
            hotkeyLogger.info("Hotkey listener started shortcut=\(configuration.displayLabel, privacy: .public)")
        case .failure(let error):
            hotkeyLogger.error("Hotkey registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func updateHotkey(to configuration: HotkeyConfiguration) -> Result<Void, HotkeyRegistrationError> {
        let handlerStatus = installEventHandler()
        guard handlerStatus == noErr else {
            return .failure(.registrationFailed(handlerStatus))
        }

        let result = registerHotkey(configuration)
        guard case .success = result else {
            return result
        }

        activeConfiguration = configuration
        configuration.save()
        hotkeyLogger.info("Hotkey saved shortcut=\(configuration.displayLabel, privacy: .public) code=\(configuration.keyCode, privacy: .public) modifiers=\(configuration.carbonModifiers, privacy: .public)")
        return .success(())
    }

    @discardableResult
    func speakCurrentSelection() -> Bool {
        speakCurrentSelection(from: nil, restoreApplication: nil)
    }

    func currentSelectionTextFast(from sourceApplication: NSRunningApplication?) -> String? {
        selectionReader.readSelectionWithAccessibilityOnly(from: sourceApplication)
    }

    @discardableResult
    func speakCurrentSelection(
        from sourceApplication: NSRunningApplication?,
        restoreApplication: NSRunningApplication?,
        beepOnFailure: Bool = true
    ) -> Bool {
        guard accessibilityIsTrusted(promptIfNeeded: true) else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }

        guard let text = selectionReader.readSelection(
            from: sourceApplication,
            restoreApplication: restoreApplication
        ) else {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }
        router?.speak(text, source: "hotkey")
        return true
    }

    private func installEventHandler() -> OSStatus {
        guard eventHandler == nil else { return noErr }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotkeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.handleRegisteredHotkey()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        return status
    }

    private func registerHotkey(
        _ configuration: HotkeyConfiguration
    ) -> Result<Void, HotkeyRegistrationError> {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        var newHotKeyRef: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x474C5859, id: 1) // "GLXY"
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )
        guard status == noErr, let newHotKeyRef else {
            hotkeyLogger.error(
                "Hotkey registration failed shortcut=\(configuration.displayLabel, privacy: .public) status=\(status, privacy: .public)"
            )
            if let activeConfiguration {
                restoreHotkey(activeConfiguration)
            }
            return .failure(.registrationFailed(status))
        }

        hotKeyRef = newHotKeyRef
        return .success(())
    }

    private func restoreHotkey(_ configuration: HotkeyConfiguration) {
        var restoredHotKeyRef: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x474C5859, id: 1)
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &restoredHotKeyRef
        )
        if status == noErr {
            hotKeyRef = restoredHotKeyRef
        } else {
            hotkeyLogger.error("Could not restore the previous hotkey status=\(status, privacy: .public)")
        }
    }

    private func handleRegisteredHotkey() {
        DispatchQueue.main.async { [weak self] in
            self?.toggleSpeechFromHotkey()
        }
    }

    private func toggleSpeechFromHotkey() {
        guard let router else { return }

        if router.isSpeaking || router.isPaused {
            hotkeyLogger.info("Hotkey invoked stop shortcut=\(self.activeConfiguration?.displayLabel ?? "none", privacy: .public)")
            router.stop()
            return
        }

        hotkeyLogger.info("Hotkey invoked speak shortcut=\(self.activeConfiguration?.displayLabel ?? "none", privacy: .public)")
        let didSpeak = speakCurrentSelection()
        if !didSpeak {
            hotkeyLogger.error("Hotkey invocation could not read a selection")
        }
    }

    private func requestAccessibilityIfNeeded() {
        if !accessibilityIsTrusted(promptIfNeeded: true) {
            hotkeyLogger.error("Hotkey listener is waiting for Accessibility access")
            NSLog("Gallaxy TTS accessibility access is not enabled. Selection hotkey may not work until it is granted in System Settings.")
        }
    }

    private func accessibilityIsTrusted(promptIfNeeded: Bool) -> Bool {
        guard promptIfNeeded, !didRequestAccessibilityPermission else {
            return AXIsProcessTrusted()
        }

        didRequestAccessibilityPermission = true
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
