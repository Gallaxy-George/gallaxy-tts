import AppKit
import ApplicationServices

final class ClipboardSelectionReader {
    private let pasteboard = NSPasteboard.general

    func readSelection(
        from sourceApplication: NSRunningApplication? = nil,
        restoreApplication: NSRunningApplication? = nil
    ) -> String? {
        if let text = readSelectionWithAccessibility(from: sourceApplication) {
            restoreApplication?.activate(options: [.activateIgnoringOtherApps])
            return text
        }

        return readSelectionByCopying(
            from: sourceApplication,
            restoreApplication: restoreApplication
        )
    }

    func readSelectionWithAccessibilityOnly(from sourceApplication: NSRunningApplication? = nil) -> String? {
        readSelectionWithAccessibility(from: sourceApplication, focusedWindowDepth: 2)
    }

    func readSelectionByCopying(
        from sourceApplication: NSRunningApplication? = nil,
        restoreApplication: NSRunningApplication? = nil
    ) -> String? {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        let copyStartChangeCount = pasteboard.changeCount
        if let sourceApplication {
            sourceApplication.unhide()
            sourceApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            waitForActivation(of: sourceApplication)
        }

        for _ in 0..<2 {
            sendCopyKeystroke()

            let deadline = Date().addingTimeInterval(1.2)
            while Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                if pasteboard.changeCount != copyStartChangeCount,
                   let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    snapshot.restore(to: pasteboard)
                    restoreApplication?.activate(options: [.activateIgnoringOtherApps])
                    return text
                }
            }
        }

        snapshot.restore(to: pasteboard)
        restoreApplication?.activate(options: [.activateIgnoringOtherApps])
        return nil
    }

    private func readSelectionWithAccessibility(
        from sourceApplication: NSRunningApplication?,
        focusedWindowDepth: Int = 5
    ) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let application = sourceApplication ?? NSWorkspace.shared.frontmostApplication
        guard let processIdentifier = application?.processIdentifier else { return nil }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        if let focusedElement = copiedElement(from: applicationElement, attribute: kAXFocusedUIElementAttribute),
           let text = selectedText(in: focusedElement) {
            return text
        }

        if let focusedWindow = copiedElement(from: applicationElement, attribute: kAXFocusedWindowAttribute),
           let text = selectedText(in: focusedWindow, maxDepth: focusedWindowDepth) {
            return text
        }

        return nil
    }

    private func selectedText(in element: AXUIElement, maxDepth: Int = 2) -> String? {
        if let text = copiedString(from: element, attribute: kAXSelectedTextAttribute) {
            return text
        }

        guard maxDepth > 0,
              let children = copiedChildren(from: element) else {
            return nil
        }

        for child in children.prefix(80) {
            if let text = selectedText(in: child, maxDepth: maxDepth - 1) {
                return text
            }
        }

        return nil
    }

    private func copiedString(from element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func copiedElement(from element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func copiedChildren(from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return nil
        }

        return children
    }

    private func waitForActivation(of application: NSRunningApplication) {
        let deadline = Date().addingTimeInterval(0.9)
        while Date() < deadline {
            if application.isActive { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
        }
    }

    private func sendCopyKeystroke() {
        let cKeyCode: CGKeyCode = 8
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    struct Item {
        let values: [Value]
    }

    struct Value {
        let type: NSPasteboard.PasteboardType
        let string: String?
        let data: Data?
    }

    let items: [Item]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let copiedItems = (pasteboard.pasteboardItems ?? []).map { item in
            Item(values: item.types.compactMap { type in
                let string = item.string(forType: type)
                let data = string == nil ? item.data(forType: type) : nil
                guard string != nil || data != nil else { return nil }
                return Value(type: type, string: string, data: data)
            })
        }.filter { !$0.values.isEmpty }
        return PasteboardSnapshot(items: copiedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            let restoredItems = items.map { item in
                let pasteboardItem = NSPasteboardItem()
                for value in item.values {
                    if let string = value.string {
                        pasteboardItem.setString(string, forType: value.type)
                    } else if let data = value.data {
                        pasteboardItem.setData(data, forType: value.type)
                    }
                }
                return pasteboardItem
            }
            pasteboard.writeObjects(restoredItems)
        }
    }
}
