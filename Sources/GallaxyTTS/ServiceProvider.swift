import AppKit

final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    weak var router: SpeechRequestRouter?

    @objc func speakSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = selectedText(from: pasteboard) else {
            error.pointee = "Gallaxy TTS did not receive readable selected text."
            NSSound.beep()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.router?.speak(text, source: "service")
        }
    }

    private func selectedText(from pasteboard: NSPasteboard) -> String? {
        let candidateTypes: [NSPasteboard.PasteboardType] = [
            .string,
            NSPasteboard.PasteboardType("NSStringPboardType"),
            NSPasteboard.PasteboardType("public.utf8-plain-text"),
            NSPasteboard.PasteboardType("public.text")
        ]

        for type in candidateTypes {
            if let value = pasteboard.string(forType: type) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }
}
