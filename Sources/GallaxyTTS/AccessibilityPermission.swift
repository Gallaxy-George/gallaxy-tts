import ApplicationServices

/// Permission is requested only in response to an explicit selection action.
/// Registering the shortcut and playing clipboard text never request access.
final class AccessibilityPermission {
    private let isTrusted: () -> Bool
    private let requestAccess: () -> Bool
    private var hasRequestedAccess = false

    init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        requestAccess: @escaping () -> Bool = {
            AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
        }
    ) {
        self.isTrusted = isTrusted
        self.requestAccess = requestAccess
    }

    func checkForSelection() -> Bool {
        // Always check silently first, including after access was granted while
        // this process was running. Never prompt an already trusted process.
        if isTrusted() { return true }
        guard !hasRequestedAccess else { return false }
        hasRequestedAccess = true
        return requestAccess()
    }
}
