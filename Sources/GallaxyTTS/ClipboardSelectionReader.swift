import AppKit
import ApplicationServices

final class ClipboardSelectionReader {
    func readSelection(
        from sourceApplication: NSRunningApplication? = nil,
        restoreApplication: NSRunningApplication? = nil
    ) -> String? {
        if let text = readSelectionWithAccessibility(from: sourceApplication) {
            restoreApplication?.activate(options: [.activateIgnoringOtherApps])
            return text
        }

        restoreApplication?.activate(options: [.activateIgnoringOtherApps])
        return nil
    }

    func readSelectionWithAccessibilityOnly(from sourceApplication: NSRunningApplication? = nil) -> String? {
        readSelectionWithAccessibility(from: sourceApplication, focusedWindowDepth: 2)
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
}
