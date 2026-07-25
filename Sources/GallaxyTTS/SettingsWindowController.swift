import AppKit

final class SettingsWindowController: NSWindowController {
    private let router: SpeechRequestRouter
    private let statusLabel = NSTextField(labelWithString: "")

    init(router: SpeechRequestRouter) {
        self.router = router

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gallaxy TTS Settings"
        window.center()
        window.contentView = contentView

        super.init(window: window)

        buildUI(in: contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        statusLabel.stringValue = router.statusLine
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func buildUI(in contentView: NSView) {
        let title = NSTextField(labelWithString: "Gallaxy TTS")
        title.font = .boldSystemFont(ofSize: 20)

        let service = NSTextField(labelWithString: "Use: select text, right-click, Services, Speak Selection with Gallaxy TTS.")
        service.lineBreakMode = .byWordWrapping
        service.maximumNumberOfLines = 2

        statusLabel.stringValue = router.statusLine
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        let stopButton = NSButton(title: "Stop Speaking", target: self, action: #selector(stopSpeaking))
        stopButton.bezelStyle = .rounded

        let stack = NSStackView(views: [title, service, statusLabel, stopButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24)
        ])
    }

    @objc private func stopSpeaking() {
        router.stop()
    }
}
