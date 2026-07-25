import AppKit
import Carbon
import Foundation

struct HotkeyConfiguration: Codable, Equatable {
    static let defaultValue = HotkeyConfiguration(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey),
        displayLabel: "Option + Space"
    )

    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayLabel: String

    private static let defaultsKey = "hotkeyConfiguration"

    static func load(from defaults: UserDefaults = .standard) -> HotkeyConfiguration {
        guard let data = defaults.data(forKey: defaultsKey),
              let configuration = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) else {
            return defaultValue
        }
        return configuration
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func captured(from event: NSEvent) -> HotkeyConfiguration? {
        let keyCode = event.keyCode
        let keyName = displayName(for: keyCode, event: event)
        guard keyName.isEmpty == false else { return nil }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var labelParts: [String] = []

        if flags.contains(.control) {
            labelParts.append("Control")
        }
        if flags.contains(.option) {
            labelParts.append("Option")
        }
        if flags.contains(.shift) {
            labelParts.append("Shift")
        }
        if flags.contains(.command) {
            labelParts.append("Command")
        }

        labelParts.append(keyName)
        return HotkeyConfiguration(
            keyCode: UInt32(keyCode),
            carbonModifiers: carbonModifiers(from: flags),
            displayLabel: labelParts.joined(separator: " + ")
        )
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        return carbonModifiers
    }

    private static func displayName(for keyCode: UInt16, event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Return): "Return",
            UInt16(kVK_Tab): "Tab",
            UInt16(kVK_Delete): "Delete",
            UInt16(kVK_ForwardDelete): "Forward Delete",
            UInt16(kVK_Home): "Home",
            UInt16(kVK_End): "End",
            UInt16(kVK_PageUp): "Page Up",
            UInt16(kVK_PageDown): "Page Down",
            UInt16(kVK_LeftArrow): "Left Arrow",
            UInt16(kVK_RightArrow): "Right Arrow",
            UInt16(kVK_UpArrow): "Up Arrow",
            UInt16(kVK_DownArrow): "Down Arrow",
            UInt16(kVK_F1): "F1",
            UInt16(kVK_F2): "F2",
            UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5",
            UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7",
            UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10",
            UInt16(kVK_F11): "F11",
            UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13",
            UInt16(kVK_F14): "F14",
            UInt16(kVK_F15): "F15",
            UInt16(kVK_F16): "F16",
            UInt16(kVK_F17): "F17",
            UInt16(kVK_F18): "F18",
            UInt16(kVK_F19): "F19",
            UInt16(kVK_F20): "F20"
        ]

        if let specialKey = specialKeys[keyCode] {
            return specialKey
        }

        return event.charactersIgnoringModifiers?.uppercased() ?? ""
    }
}

enum HotkeyRegistrationError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "The shortcut could not be registered (OSStatus \(status)). It may already be in use."
        }
    }
}
