import AppKit
import Carbon
import QuartzCore
import SwiftUI

@MainActor
final class GallaxyTTSWidgetViewModel: ObservableObject {
    @Published var speed: Double
    @Published var status: String
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var isPinned = false
    @Published var leftDrawerExpanded = false
    @Published var rightDrawerExpanded = false
    @Published var caption = ""
    @Published var speakerLevel: Double = 0
    @Published var currentClipboardClip: ClipboardClip?
    @Published var recentClipboardClips: [ClipboardClip] = []
    @Published var rightDrawerMode: RightDrawerMode = .clips
    @Published var hotkeyDraft: HotkeyConfiguration
    @Published var isCapturingHotkey = false
    @Published var hotkeyMessage = ""
    @Published var consoleLines = [
        "GALLAXY TTS CONSOLE",
        "> ready",
        "> select text or copy text",
        "> press play"
    ]

    weak var window: NSWindow?
    private let router: SpeechRequestRouter
    private let hotkeyController: HotkeyController
    private let playHandler: () -> WidgetPlayResult?
    private let defaults = UserDefaults.standard
    private let pinnedDefaultsKey = "widgetPinned"
    private let leftDrawerDefaultsKey = "leftDrawerExpanded"
    private let rightDrawerDefaultsKey = "rightDrawerExpanded"
    private let clipboardHistoryDefaultsKey = "clipboardHistory"
    private let pasteboard = NSPasteboard.general
    private let maxClipboardHistory = 8
    private let maxStoredClipCharacters = 16_000
    private var hasStartedPlayback = false
    private var clipboardHistory: [ClipboardClip] = []
    private var lastPasteboardChangeCount = 0
    private var clipboardPollTimer: Timer?

    static let sideSpeakerWidth: CGFloat = 118
    static let mainDeckWidth: CGFloat = 430
    static let drawerPanelWidth: CGFloat = 238
    static let drawerPanelHeight: CGFloat = 310
    static let interSectionOverlap: CGFloat = 22
    static let widgetHeight: CGFloat = 350
    static let drawerAnimationDuration: TimeInterval = 0.36
    static let minimumWidgetScale: CGFloat = 0.5
    static let maximumWidgetScale: CGFloat = 1.4
    static let collapsedWindowWidth: CGFloat = (sideSpeakerWidth * 2) + mainDeckWidth - (interSectionOverlap * 2)
    static let drawerWidthDelta: CGFloat = drawerPanelWidth - interSectionOverlap

    static func minimumWindowSize(for baseWidgetWidth: CGFloat) -> NSSize {
        NSSize(
            width: baseWidgetWidth * minimumWidgetScale,
            height: widgetHeight * minimumWidgetScale
        )
    }

    static func clampedWidgetScale(_ scale: CGFloat) -> CGFloat {
        min(maximumWidgetScale, max(minimumWidgetScale, scale))
    }

    init(
        router: SpeechRequestRouter,
        hotkeyController: HotkeyController,
        playHandler: @escaping () -> WidgetPlayResult?
    ) {
        self.router = router
        self.hotkeyController = hotkeyController
        self.playHandler = playHandler
        self.hotkeyDraft = HotkeyConfiguration.load()
        self.speed = router.speechSpeedMultiplier
        self.status = router.statusLine
        self.isPinned = defaults.bool(forKey: pinnedDefaultsKey)
        self.leftDrawerExpanded = defaults.bool(forKey: leftDrawerDefaultsKey)
        self.rightDrawerExpanded = defaults.bool(forKey: rightDrawerDefaultsKey)
        clearPersistedClipboardHistory()
        refreshClipboardSnapshot(record: false)
        startClipboardPolling()
        caption = router.currentCaption
        router.captionHandler = { [weak self] caption in
            self?.caption = caption
        }
        router.activityHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        router.levelHandler = { [weak self] level in
            DispatchQueue.main.async {
                self?.speakerLevel = level
            }
        }
    }

    deinit {
        clipboardPollTimer?.invalidate()
    }

    func refresh() {
        speed = router.speechSpeedMultiplier
        status = router.statusLine
        isSpeaking = router.isSpeaking
        isPaused = router.isPaused
        refreshClipboardSnapshot(record: false)
        if !isSpeaking && !isPaused {
            speakerLevel = 0
        }
        if let error = router.lastError {
            consoleLines = ["GALLAXY TTS CONSOLE", "> Kokoro unavailable", "> \(error)"]
            hasStartedPlayback = false
        } else if !isSpeaking && !isPaused && hasStartedPlayback {
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> ready",
                "> playback finished"
            ]
            hasStartedPlayback = false
        }
    }

    func play() {
        if router.resume() {
            hasStartedPlayback = true
            isPaused = false
            isSpeaking = true
            status = "Speaking"
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> resumed playback"
            ]
            return
        }

        status = "Reading text"
        consoleLines = [
            "GALLAXY TTS CONSOLE",
            "> checking clipboard",
            "> selection if clipboard is empty"
        ]
        switch playHandler() {
        case .selection(let text):
            rememberClip(text, source: "selection")
            hasStartedPlayback = true
            isPaused = false
            isSpeaking = true
            status = "Preparing voice"
            setSpeakingConsole(source: "selection", text: text)
        case .clipboard(let text):
            rememberClip(text, source: "clipboard")
            hasStartedPlayback = true
            isPaused = false
            isSpeaking = true
            status = "Preparing voice"
            setSpeakingConsole(source: "clipboard", text: text)
        case .empty:
            isPaused = false
            isSpeaking = false
            status = "No text found"
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> clipboard is empty",
                "> no quick selection found"
            ]
            NSSound.beep()
        case .none:
            isPaused = false
            isSpeaking = false
            status = "Starting"
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> starting"
            ]
        }
    }

    func stop() {
        if router.isPaused {
            router.stop()
            hasStartedPlayback = false
            isPaused = false
            isSpeaking = false
            speakerLevel = 0
            status = "Stopped"
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> stopped"
            ]
            return
        }

        if router.pause() {
            isPaused = true
            isSpeaking = false
            speakerLevel = 0
            status = "Paused"
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> paused",
                "> press play to continue"
            ]
            return
        }

        router.stop()
        hasStartedPlayback = false
        isPaused = false
        isSpeaking = false
        speakerLevel = 0
        status = "Stopped"
        consoleLines = [
            "GALLAXY TTS CONSOLE",
            "> stopped"
        ]
    }

    func slower() {
        speed = max(0.75, speed - 0.05)
        commitSpeed()
    }

    func faster() {
        speed = min(1.6, speed + 0.05)
        commitSpeed()
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        defaults.set(pinned, forKey: pinnedDefaultsKey)
        applyPinnedWindowLevel()
        if pinned {
            window?.orderFrontRegardless()
        }
    }

    func applyPinnedWindowLevel() {
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = isPinned
            panel.hidesOnDeactivate = false
        }
        window?.level = isPinned ? .statusBar : .normal
        window?.collectionBehavior = isPinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            : [.fullScreenAuxiliary]
    }

    func commitSpeed() {
        router.speechSpeedMultiplier = speed
    }

    func setLeftDrawerExpanded(_ expanded: Bool) {
        guard leftDrawerExpanded != expanded else { return }
        let previousWidgetWidth = widgetWidth
        let preservedMainDeckMinX = mainDeckScreenMinX(previousWidgetWidth: previousWidgetWidth)
        leftDrawerExpanded = expanded
        defaults.set(leftDrawerExpanded, forKey: leftDrawerDefaultsKey)
        applyDrawerWindowSize(
            animated: false,
            anchor: .right,
            previousWidgetWidth: previousWidgetWidth,
            preservedMainDeckMinX: preservedMainDeckMinX
        )
    }

    func setRightDrawerExpanded(_ expanded: Bool) {
        guard rightDrawerExpanded != expanded else { return }
        let previousWidgetWidth = widgetWidth
        let preservedMainDeckMinX = mainDeckScreenMinX(previousWidgetWidth: previousWidgetWidth)
        rightDrawerExpanded = expanded
        if rightDrawerExpanded {
            refreshClipboardSnapshot(record: false)
        }
        defaults.set(rightDrawerExpanded, forKey: rightDrawerDefaultsKey)
        applyDrawerWindowSize(
            animated: false,
            anchor: .left,
            previousWidgetWidth: previousWidgetWidth,
            preservedMainDeckMinX: preservedMainDeckMinX
        )
    }

    func speakClip(_ clip: ClipboardClip) {
        rememberClip(clip.text, source: clip.source)
        hasStartedPlayback = true
        isPaused = false
        isSpeaking = true
        status = "Preparing voice"
        setSpeakingConsole(source: "clip", text: clip.text)
        router.speak(clip.text, source: "clip history")
    }

    func refreshClipboardSnapshot(record: Bool = false) {
        lastPasteboardChangeCount = pasteboard.changeCount
        guard let text = clipboardText() else {
            currentClipboardClip = nil
            updateRecentClipboardClips()
            return
        }

        let clip = ClipboardClip(text: trimmedStoredText(text), source: "clipboard")
        currentClipboardClip = clip
        if record {
            rememberClip(clip.text, source: clip.source)
        } else {
            updateRecentClipboardClips()
        }
    }

    private func startClipboardPolling() {
        lastPasteboardChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.pasteboard.changeCount != self.lastPasteboardChangeCount else { return }
                self.refreshClipboardSnapshot(record: false)
            }
        }
        clipboardPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func clipboardText() -> String? {
        guard let text = pasteboard.string(forType: .string) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func rememberClip(_ text: String, source: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let storedText = trimmedStoredText(trimmed)
        clipboardHistory.removeAll { $0.text == storedText }
        clipboardHistory.insert(ClipboardClip(text: storedText, source: source), at: 0)
        if clipboardHistory.count > maxClipboardHistory {
            clipboardHistory = Array(clipboardHistory.prefix(maxClipboardHistory))
        }
        updateRecentClipboardClips()
    }

    private func trimmedStoredText(_ text: String) -> String {
        if text.count <= maxStoredClipCharacters {
            return text
        }
        return String(text.prefix(maxStoredClipCharacters))
    }

    private func clearPersistedClipboardHistory() {
        defaults.removeObject(forKey: clipboardHistoryDefaultsKey)
    }

    private func updateRecentClipboardClips() {
        let currentText = currentClipboardClip?.text
        recentClipboardClips = clipboardHistory
            .filter { $0.text != currentText }
            .prefix(maxClipboardHistory)
            .map { $0 }
    }

    func captureHotkey(_ configuration: HotkeyConfiguration) {
        hotkeyDraft = configuration
        isCapturingHotkey = false
        hotkeyMessage = "READY TO SAVE"
    }

    func saveHotkey() {
        switch hotkeyController.updateHotkey(to: hotkeyDraft) {
        case .success:
            hotkeyMessage = "SAVED"
        case .failure(let error):
            switch error {
            case .registrationFailed:
                hotkeyMessage = "SHORTCUT UNAVAILABLE"
            }
            NSSound.beep()
        }
    }

    func applyDrawerWindowSize(
        animated: Bool,
        anchor: DrawerResizeAnchor = .left,
        preserveCurrentScale: Bool = true,
        previousWidgetWidth: CGFloat? = nil,
        preservedMainDeckMinX: CGFloat? = nil
    ) {
        guard let window else { return }
        let oldWidth = window.frame.width
        let baseWidth = widgetWidth
        let scale = preserveCurrentScale ? currentWindowScale(previousWidgetWidth: previousWidgetWidth ?? baseWidth) : 1
        let width = baseWidth * scale
        let height = Self.widgetHeight * scale
        updateWindowResizeConstraints(for: baseWidth)

        var frame = window.frame
        frame.size = NSSize(width: width, height: height)
        if let preservedMainDeckMinX {
            frame.origin.x = preservedMainDeckMinX - Self.mainDeckXOffset(leftDrawerExpanded: leftDrawerExpanded) * scale
        } else if anchor == .right {
            frame.origin.x -= width - oldWidth
        }

        if preservedMainDeckMinX == nil, let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let rightInset: CGFloat = 18
            if frame.maxX > visibleFrame.maxX - rightInset {
                frame.origin.x = max(visibleFrame.minX + rightInset, visibleFrame.maxX - width - rightInset)
            }
            if frame.minX < visibleFrame.minX + rightInset {
                frame.origin.x = visibleFrame.minX + rightInset
            }
        }

        guard animated else {
            window.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.drawerAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func mainDeckScreenMinX(previousWidgetWidth: CGFloat) -> CGFloat? {
        guard let window else { return nil }
        let scale = currentWindowScale(previousWidgetWidth: previousWidgetWidth)
        return window.frame.minX + Self.mainDeckXOffset(leftDrawerExpanded: leftDrawerExpanded) * scale
    }

    private static func mainDeckXOffset(leftDrawerExpanded: Bool) -> CGFloat {
        sideSpeakerWidth
            - interSectionOverlap
            + (leftDrawerExpanded ? drawerWidthDelta : 0)
    }

    private func currentWindowScale(previousWidgetWidth: CGFloat) -> CGFloat {
        guard let window else { return 1 }
        let widthScale = window.frame.width / max(1, previousWidgetWidth)
        let heightScale = window.frame.height / Self.widgetHeight
        return Self.clampedWidgetScale(min(widthScale, heightScale))
    }

    private func updateWindowResizeConstraints(for baseWidgetWidth: CGFloat) {
        guard let window else { return }
        let minimumSize = Self.minimumWindowSize(for: baseWidgetWidth)
        window.minSize = minimumSize
        window.contentMinSize = minimumSize
        window.maxSize = NSSize(
            width: baseWidgetWidth * Self.maximumWidgetScale,
            height: Self.widgetHeight * Self.maximumWidgetScale
        )
        window.contentAspectRatio = NSSize(width: baseWidgetWidth, height: Self.widgetHeight)
    }

    var activityLabel: String {
        if router.lastError != nil { return "KOKORO UNAVAILABLE" }
        if isPaused {
            return "PAUSED"
        }
        if status == "Preparing voice" {
            return "PREPARING"
        }
        if isSpeaking {
            return "SPEAKING"
        }
        switch status {
        case "Reading text":
            return "READING"
        case "No text found":
            return "NO TEXT"
        case "Starting":
            return "STARTING"
        case "Stopped":
            return "STOPPED"
        default:
            break
        }
        return "READY"
    }

    var widgetWidth: CGFloat {
        Self.collapsedWindowWidth
            + (leftDrawerExpanded ? Self.drawerWidthDelta : 0)
            + (rightDrawerExpanded ? Self.drawerWidthDelta : 0)
    }

    private func setSpeakingConsole(source: String, text: String) {
        consoleLines = [
            "GALLAXY TTS CONSOLE",
            "> source: \(source)",
            "> chars: \(text.count)",
            "> \(previewText(from: text))"
        ]
    }

    private func previewText(from text: String) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else {
            return "(empty)"
        }

        let limit = 260
        if collapsed.count > limit {
            return String(collapsed.prefix(limit)) + " ..."
        }
        return collapsed
    }
}
