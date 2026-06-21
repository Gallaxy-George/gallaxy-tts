import AppKit
import Carbon

final class HotkeyController {
    private weak var router: SpeechRequestRouter?
    private let selectionReader = ClipboardSelectionReader()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

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
        checkAccessibilitySilently()
        installEventHandler()
        registerOptionSpace()
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

    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.speakCurrentSelection()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    private func registerOptionSpace() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let signature = OSType(fourCharacterCode: "TXBZ")
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let spaceKeyCode: UInt32 = 49
        RegisterEventHotKey(
            spaceKeyCode,
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func checkAccessibilitySilently() {
        if !AXIsProcessTrusted() {
            NSLog("Gallaxy TTS accessibility access is not enabled. Selection copy hotkey may not work until it is granted in System Settings.")
        }
    }
}

private extension OSType {
    init(fourCharacterCode string: String) {
        precondition(string.utf8.count == 4)
        self = string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
