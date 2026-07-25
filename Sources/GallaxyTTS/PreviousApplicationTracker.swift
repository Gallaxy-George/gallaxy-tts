import AppKit

final class PreviousApplicationTracker {
    private let ownBundleIdentifier: String
    private(set) var lastNonGallaxyTTSApplication: NSRunningApplication?

    init(ownBundleIdentifier: String) {
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    func start() {
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            update(with: frontmost)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        update(with: application)
    }

    private func update(with application: NSRunningApplication) {
        guard application.bundleIdentifier != ownBundleIdentifier else { return }
        lastNonGallaxyTTSApplication = application
    }
}
