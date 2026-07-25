import AppKit
import Carbon
import QuartzCore
import SwiftUI

enum VoiceProviderOption: String, CaseIterable, Identifiable {
    case localKokoro = "localKokoro"
    case elevenLabs = "elevenLabs"

    var id: String { rawValue }

    static func savedValue(_ rawValue: String?) -> VoiceProviderOption {
        guard let rawValue else { return .localKokoro }
        switch rawValue {
        case VoiceProviderOption.elevenLabs.rawValue:
            return .elevenLabs
        default:
            return .localKokoro
        }
    }

    var title: String {
        switch self {
        case .localKokoro:
            return "LOCAL"
        case .elevenLabs:
            return "CLOUD"
        }
    }

    var detail: String {
        switch self {
        case .localKokoro:
            return "Kokoro 82M"
        case .elevenLabs:
            return "ElevenLabs"
        }
    }
}

enum WidgetPlayResult {
    case selection(String)
    case clipboard(String)
    case empty
}

struct ClipboardClip: Identifiable, Codable {
    let id: UUID
    let text: String
    let source: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, source: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.source = source
        self.createdAt = createdAt
    }

    var title: String {
        let words = normalizedText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .prefix(3)
        let title = words.joined(separator: " ")
        return title.isEmpty ? "CLIP" : title.uppercased()
    }

    var preview: String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
        let preview = lines.joined(separator: " / ")
        guard !preview.isEmpty else { return "(empty)" }
        return preview.count > 94 ? String(preview.prefix(91)) + "..." : preview
    }

    private var normalizedText: String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "https://", with: " ")
            .replacingOccurrences(of: "http://", with: " ")
    }
}

final class WidgetWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: GallaxyTTSWidgetViewModel

    init(
        router: SpeechRequestRouter,
        hotkeyController: HotkeyController,
        playHandler: @escaping () -> WidgetPlayResult?
    ) {
        self.viewModel = GallaxyTTSWidgetViewModel(
            router: router,
            hotkeyController: hotkeyController,
            playHandler: playHandler
        )

        let rootView = GallaxyTTSWidgetView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: GallaxyTTSWidgetViewModel.collapsedWindowWidth,
                height: GallaxyTTSWidgetViewModel.widgetHeight
            ),
            styleMask: [.titled, .fullSizeContentView, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        window.title = "Gallaxy TTS"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        let minimumSize = GallaxyTTSWidgetViewModel.minimumWindowSize(for: GallaxyTTSWidgetViewModel.collapsedWindowWidth)
        window.minSize = minimumSize
        window.contentMinSize = minimumSize
        window.contentAspectRatio = NSSize(
            width: GallaxyTTSWidgetViewModel.collapsedWindowWidth,
            height: GallaxyTTSWidgetViewModel.widgetHeight
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)

        viewModel.window = window
        viewModel.applyPinnedWindowLevel()
        viewModel.applyDrawerWindowSize(animated: false, preserveCurrentScale: false)
        window.delegate = self
        placeWindowOnScreen()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        viewModel.refresh()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func placeWindowOnScreen() {
        guard let window else { return }
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let frame = window.frame
        let x = min(max(visibleFrame.midX - frame.width / 2, visibleFrame.minX + 24), visibleFrame.maxX - frame.width - 24)
        let y = min(max(visibleFrame.midY - frame.height / 2, visibleFrame.minY + 24), visibleFrame.maxY - frame.height - 24)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class GallaxyTTSWidgetViewModel: ObservableObject {
    @Published var speed: Double
    @Published var status: String
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var isPinned = false
    @Published var leftDrawerExpanded = false
    @Published var rightDrawerExpanded = false
    @Published var selectedVoiceProvider: VoiceProviderOption = .localKokoro
    @Published var elevenLabsAPIKeyDraft = ""
    @Published var hasElevenLabsAPIKey = false
    @Published var credentialMessage = ""
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
    private let voiceProviderDefaultsKey = "voiceProvider"
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
        self.selectedVoiceProvider = VoiceProviderOption.savedValue(defaults.string(forKey: voiceProviderDefaultsKey))
        clearPersistedClipboardHistory()
        refreshClipboardSnapshot(record: false)
        startClipboardPolling()
        refreshElevenLabsCredentialState()
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
        if !isSpeaking && !isPaused && hasStartedPlayback && status == router.statusLine {
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

    func selectVoiceProvider(_ provider: VoiceProviderOption) {
        selectedVoiceProvider = provider
        defaults.set(provider.rawValue, forKey: voiceProviderDefaultsKey)
        router.voiceProviderDidChange(to: provider)
        credentialMessage = ""

        if provider == .elevenLabs {
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> voice source: CLOUD",
                "> provider: ELEVENLABS",
                hasElevenLabsAPIKey ? "> api key saved" : "> checking api key"
            ]
            refreshElevenLabsCredentialState(updateConsole: true)
            return
        }

        consoleLines = [
            "GALLAXY TTS CONSOLE",
            "> voice source: LOCAL",
            "> model: KOKORO 82M",
            "> ready"
        ]
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

    func saveElevenLabsAPIKey() {
        do {
            try ElevenLabsCredentialStore.saveAPIKey(elevenLabsAPIKeyDraft)
            elevenLabsAPIKeyDraft = ""
            hasElevenLabsAPIKey = true
            selectedVoiceProvider = .elevenLabs
            defaults.set(VoiceProviderOption.elevenLabs.rawValue, forKey: voiceProviderDefaultsKey)
            credentialMessage = "KEY SAVED"
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> elevenlabs key saved",
                "> press play"
            ]
        } catch {
            hasElevenLabsAPIKey = ElevenLabsCredentialStore.hasAPIKey()
            credentialMessage = "SAVE FAILED"
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> key save failed",
                "> \(error.localizedDescription)"
            ]
            NSSound.beep()
        }
    }

    func deleteElevenLabsAPIKey() {
        ElevenLabsCredentialStore.deleteAPIKey()
        hasElevenLabsAPIKey = false
        elevenLabsAPIKeyDraft = ""
        credentialMessage = "KEY REMOVED"
        consoleLines = [
            "GALLAXY TTS CONSOLE",
            "> elevenlabs key removed"
        ]
    }

    private func refreshElevenLabsCredentialState(updateConsole: Bool = false) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let hasKey = ElevenLabsCredentialStore.hasAPIKey()
            DispatchQueue.main.async {
                guard let self else { return }
                self.hasElevenLabsAPIKey = hasKey
                guard updateConsole, self.selectedVoiceProvider == .elevenLabs else { return }
                self.consoleLines = [
                    "GALLAXY TTS CONSOLE",
                    "> voice source: CLOUD",
                    "> provider: ELEVENLABS",
                    hasKey ? "> api key saved" : "> enter api key"
                ]
            }
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
        if isPaused {
            return "PAUSED"
        }
        if status == "Preparing voice" {
            return "PREPARING"
        }
        if isSpeaking {
            return "SPEAKING"
        }
        if selectedVoiceProvider == .elevenLabs && !hasElevenLabsAPIKey {
            return "API KEY"
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

enum DrawerResizeAnchor {
    case left
    case right
}

enum RightDrawerMode {
    case clips
    case hotkey
}

enum GallaxyBrand {
    enum Weight {
        case regular
        case medium
        case semibold
        case bold
    }

    static let pageBackground = color(0x070706)
    static let textMain = color(0xe9e3d5)
    static let textMuted = color(0xe9e3d5).opacity(0.64)
    static let brandMaroon = color(0x6b1f26)
    static let brandMaroonReadable = color(0xa63a43)
    static let brandGreen = color(0x566b57)
    static let borderSubtle = color(0xe9e3d5).opacity(0.15)
    static let panelSurface = color(0xe9e3d5).opacity(0.032)

    static func brandFont(size: CGFloat) -> Font {
        .custom("Audiowide-Regular", size: size)
    }

    static func displayFont(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(displayFontName(for: weight), size: size)
    }

    static func bodyFont(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(bodyFontName(for: weight), size: size)
    }

    private static func displayFontName(for weight: Weight) -> String {
        switch weight {
        case .regular:
            return "Oxanium-Regular"
        case .medium:
            return "Oxanium-Medium"
        case .semibold:
            return "Oxanium-SemiBold"
        case .bold:
            return "Oxanium-Bold"
        }
    }

    private static func bodyFontName(for weight: Weight) -> String {
        switch weight {
        case .regular:
            return "Rubik-Regular"
        case .medium:
            return "Rubik-Medium"
        case .semibold:
            return "Rubik-SemiBold"
        case .bold:
            return "Rubik-Bold"
        }
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }
}

struct GallaxyTTSWidgetView: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel
    @State private var leftDrawerMotionOffset: CGFloat = 0
    @State private var rightDrawerMotionOffset: CGFloat = 0
    @State private var leftDrawerAnimating = false
    @State private var rightDrawerAnimating = false

    private let drawerAnimation = Animation.timingCurve(
        0.22,
        0.86,
        0.24,
        1.0,
        duration: GallaxyTTSWidgetViewModel.drawerAnimationDuration
    )

    var body: some View {
        GeometryReader { geometry in
            let scale = widgetScale(for: geometry.size)

            widgetBody
                .scaleEffect(scale, anchor: .center)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .overlay(WindowResizeOverlay())
        .frame(
            minWidth: viewModel.widgetWidth * GallaxyTTSWidgetViewModel.minimumWidgetScale,
            minHeight: GallaxyTTSWidgetViewModel.widgetHeight * GallaxyTTSWidgetViewModel.minimumWidgetScale
        )
    }

    private var widgetBody: some View {
        let leftDelta = viewModel.leftDrawerExpanded ? GallaxyTTSWidgetViewModel.drawerWidthDelta : 0
        let rightDelta = viewModel.rightDrawerExpanded ? GallaxyTTSWidgetViewModel.drawerWidthDelta : 0
        let mainX = GallaxyTTSWidgetViewModel.sideSpeakerWidth
            - GallaxyTTSWidgetViewModel.interSectionOverlap
            + leftDelta
        let mainY = (GallaxyTTSWidgetViewModel.widgetHeight - CGFloat(330)) / 2
        let drawerY = (GallaxyTTSWidgetViewModel.widgetHeight - GallaxyTTSWidgetViewModel.drawerPanelHeight) / 2
        let leftSpeakerX = GallaxyTTSWidgetViewModel.sideSpeakerWidth / 2
        let rightSpeakerX = mainX
            + GallaxyTTSWidgetViewModel.mainDeckWidth
            - GallaxyTTSWidgetViewModel.interSectionOverlap
            + rightDelta
            + GallaxyTTSWidgetViewModel.sideSpeakerWidth / 2
        let leftDrawerX = mainX
            + GallaxyTTSWidgetViewModel.interSectionOverlap
            - GallaxyTTSWidgetViewModel.drawerPanelWidth
        let rightDrawerX = mainX
            + GallaxyTTSWidgetViewModel.mainDeckWidth
            - GallaxyTTSWidgetViewModel.interSectionOverlap
        let leftSpeakerMinX = leftSpeakerX - GallaxyTTSWidgetViewModel.sideSpeakerWidth / 2
        let rightSpeakerMinX = rightSpeakerX - GallaxyTTSWidgetViewModel.sideSpeakerWidth / 2

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                VoiceProviderPanel(viewModel: viewModel)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.drawerPanelWidth,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .offset(
                        x: leftDrawerX + (viewModel.leftDrawerExpanded ? 0 : GallaxyTTSWidgetViewModel.drawerWidthDelta),
                        y: drawerY
                    )
                    .allowsHitTesting(viewModel.leftDrawerExpanded && !leftDrawerAnimating)
                    .zIndex(1)

                DrawerSpeakerJoinSeal(side: .left)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.interSectionOverlap + 2,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .offset(
                        x: leftSpeakerMinX + GallaxyTTSWidgetViewModel.sideSpeakerWidth - GallaxyTTSWidgetViewModel.interSectionOverlap - 1,
                        y: drawerY
                    )
                    .opacity(viewModel.leftDrawerExpanded ? 1 : 0)
                    .zIndex(1.5)

                SideSpeakerRack(
                    side: .left,
                    expanded: viewModel.leftDrawerExpanded,
                    speakerLevel: viewModel.speakerLevel,
                    panelLabel: "Voice Model Panel",
                    toggleAction: toggleLeftDrawer
                )
                .frame(
                    width: GallaxyTTSWidgetViewModel.sideSpeakerWidth,
                    height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                )
                .position(
                    x: leftSpeakerX,
                    y: drawerY + GallaxyTTSWidgetViewModel.drawerPanelHeight / 2
                )
                .zIndex(2)
            }
            .offset(x: leftDrawerMotionOffset)
            .zIndex(2)

            mainDeck
                .offset(x: mainX, y: mainY)
                .zIndex(3)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .animation(nil, value: viewModel.leftDrawerExpanded)
                .animation(nil, value: viewModel.rightDrawerExpanded)

            ZStack(alignment: .topLeading) {
                SlideoutRackPanel(viewModel: viewModel)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.drawerPanelWidth,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .offset(
                        x: rightDrawerX - (viewModel.rightDrawerExpanded ? 0 : GallaxyTTSWidgetViewModel.drawerWidthDelta),
                        y: drawerY
                    )
                    .allowsHitTesting(viewModel.rightDrawerExpanded && !rightDrawerAnimating)
                    .zIndex(1)

                DrawerSpeakerJoinSeal(side: .right)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.interSectionOverlap + 2,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .offset(
                        x: rightSpeakerMinX - 1,
                        y: drawerY
                    )
                    .opacity(viewModel.rightDrawerExpanded ? 1 : 0)
                    .zIndex(1.5)

                SideSpeakerRack(
                    side: .right,
                    expanded: viewModel.rightDrawerExpanded,
                    speakerLevel: viewModel.speakerLevel,
                    panelLabel: "Side Panel",
                    toggleAction: toggleRightDrawer
                )
                .frame(
                    width: GallaxyTTSWidgetViewModel.sideSpeakerWidth,
                    height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                )
                .position(
                    x: rightSpeakerX,
                    y: drawerY + GallaxyTTSWidgetViewModel.drawerPanelHeight / 2
                )
                .zIndex(2)
            }
            .offset(x: rightDrawerMotionOffset)
            .zIndex(2)
        }
        .frame(width: viewModel.widgetWidth, height: GallaxyTTSWidgetViewModel.widgetHeight, alignment: .leading)
    }

    private func toggleLeftDrawer() {
        guard !leftDrawerAnimating else { return }
        leftDrawerAnimating = true

        if viewModel.leftDrawerExpanded {
            withAnimation(drawerAnimation) {
                leftDrawerMotionOffset = GallaxyTTSWidgetViewModel.drawerWidthDelta
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GallaxyTTSWidgetViewModel.drawerAnimationDuration) {
                withTransaction(Transaction(animation: nil)) {
                    viewModel.setLeftDrawerExpanded(false)
                    leftDrawerMotionOffset = 0
                    leftDrawerAnimating = false
                }
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                viewModel.setLeftDrawerExpanded(true)
                leftDrawerMotionOffset = GallaxyTTSWidgetViewModel.drawerWidthDelta
            }
            DispatchQueue.main.async {
                withAnimation(drawerAnimation) {
                    leftDrawerMotionOffset = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GallaxyTTSWidgetViewModel.drawerAnimationDuration) {
                withTransaction(Transaction(animation: nil)) {
                    leftDrawerAnimating = false
                }
            }
        }
    }

    private func toggleRightDrawer() {
        guard !rightDrawerAnimating else { return }
        rightDrawerAnimating = true

        if viewModel.rightDrawerExpanded {
            withAnimation(drawerAnimation) {
                rightDrawerMotionOffset = -GallaxyTTSWidgetViewModel.drawerWidthDelta
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GallaxyTTSWidgetViewModel.drawerAnimationDuration) {
                withTransaction(Transaction(animation: nil)) {
                    viewModel.setRightDrawerExpanded(false)
                    rightDrawerMotionOffset = 0
                    rightDrawerAnimating = false
                }
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                viewModel.setRightDrawerExpanded(true)
                rightDrawerMotionOffset = -GallaxyTTSWidgetViewModel.drawerWidthDelta
            }
            DispatchQueue.main.async {
                withAnimation(drawerAnimation) {
                    rightDrawerMotionOffset = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GallaxyTTSWidgetViewModel.drawerAnimationDuration) {
                withTransaction(Transaction(animation: nil)) {
                    rightDrawerAnimating = false
                }
            }
        }
    }

    private var mainDeck: some View {
        ZStack {
            RetroShell()

            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(GallaxyBrand.pageBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(GallaxyBrand.borderSubtle, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.75), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(viewModel.activityLabel)
                                .font(GallaxyBrand.displayFont(size: 10, weight: .bold))
                                .foregroundStyle(GallaxyBrand.brandMaroonReadable)
                            Spacer()
                        }

                        TerminalConsoleView(
                            lines: viewModel.consoleLines,
                            active: viewModel.isSpeaking,
                            paused: viewModel.isPaused
                        )
                            .frame(height: 196)
                    }
                    .padding(10)
                }
                .frame(minWidth: 230, minHeight: 236)

                GallaxyGlassContainer(spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        GallaxyPlayButton(action: viewModel.play)

                        GallaxyStopButton(
                            active: viewModel.isPaused,
                            action: viewModel.stop
                        )

                        GallaxySpeedControl(
                            value: Binding(
                                get: { viewModel.speed },
                                set: { newValue in
                                    viewModel.speed = newValue
                                    viewModel.commitSpeed()
                                }
                            ),
                            range: 0.75...1.6
                        )
                        .frame(minWidth: 124, maxWidth: 190)

                        Text(String(format: "%.2fx", viewModel.speed))
                            .font(GallaxyBrand.displayFont(size: 10, weight: .semibold))
                            .foregroundStyle(GallaxyBrand.textMuted)
                            .frame(width: 44, alignment: .trailing)

                        GallaxyPinButton(
                            active: viewModel.isPinned,
                            action: { viewModel.setPinned(!viewModel.isPinned) }
                        )
                        .help(viewModel.isPinned ? "Unpin widget" : "Pin widget above other windows")
                    }
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: GallaxyTTSWidgetViewModel.mainDeckWidth, height: 330)
    }

    private func widgetScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / max(1, viewModel.widgetWidth)
        let heightScale = size.height / GallaxyTTSWidgetViewModel.widgetHeight
        let rawScale = GallaxyTTSWidgetViewModel.clampedWidgetScale(min(widthScale, heightScale))
        let snappedScale = (rawScale * 20).rounded(.toNearestOrAwayFromZero) / 20
        return GallaxyTTSWidgetViewModel.clampedWidgetScale(snappedScale)
    }
}

struct RetroShell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        GallaxyBrand.brandMaroonReadable,
                        GallaxyBrand.pageBackground,
                        GallaxyBrand.brandMaroon,
                        GallaxyBrand.brandGreen
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                GallaxyBrand.brandMaroonReadable.opacity(0.34),
                                GallaxyBrand.brandMaroon.opacity(0.28),
                                .black.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
            )
            .padding(4)
    }
}

struct GallaxyGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    private let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        content()
    }
}

enum GallaxyDrawerGlassDirection {
    case voice
    case rack
}

struct GallaxyDrawerGlassBackground: View {
    let direction: GallaxyDrawerGlassDirection

    var body: some View {
        drawerSurface
            .padding(bleedInsets)
    }

    @ViewBuilder
    private var drawerSurface: some View {
        let shape = GallaxyDrawerColumnShape(direction: direction, radius: 8)

        shape
            .fill(GallaxyBrand.pageBackground.opacity(0.60))
            .overlay(
                shape.fill(glassGradient)
            )
            .overlay(
                shape.stroke(GallaxyBrand.textMain.opacity(0.24), lineWidth: 1)
            )
    }

    private var bleedInsets: EdgeInsets {
        switch direction {
        case .voice:
            return EdgeInsets(top: 0, leading: -24, bottom: 0, trailing: 0)
        case .rack:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: -24)
        }
    }

    private var glassGradient: LinearGradient {
        switch direction {
        case .voice:
            return LinearGradient(
                colors: [
                    GallaxyBrand.pageBackground.opacity(0.98),
                    GallaxyBrand.brandMaroon.opacity(0.91),
                    GallaxyBrand.brandGreen.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .rack:
            return LinearGradient(
                colors: [
                    GallaxyBrand.brandGreen.opacity(0.88),
                    GallaxyBrand.brandMaroon.opacity(0.91),
                    GallaxyBrand.pageBackground.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct GallaxyDrawerColumnShape: Shape {
    let direction: GallaxyDrawerGlassDirection
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        let c = radius * 0.5522847498
        var path = Path()

        switch direction {
        case .voice:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + radius),
                control1: CGPoint(x: rect.minX + radius - c, y: rect.minY),
                control2: CGPoint(x: rect.minX, y: rect.minY + radius - c)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                control1: CGPoint(x: rect.minX, y: rect.maxY - radius + c),
                control2: CGPoint(x: rect.minX + radius - c, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        case .rack:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control1: CGPoint(x: rect.maxX - radius + c, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + radius - c)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.maxY - radius + c),
                control2: CGPoint(x: rect.maxX - radius + c, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}

enum SpeakerRackSide {
    case left
    case right
}

struct DrawerSpeakerJoinSeal: View {
    let side: SpeakerRackSide

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        GallaxyBrand.textMain.opacity(0.28),
                        GallaxyBrand.brandMaroonReadable.opacity(0.88),
                        GallaxyBrand.brandMaroon.opacity(0.95),
                        GallaxyBrand.pageBackground.opacity(0.86)
                    ],
                    startPoint: side == .left ? .topTrailing : .topLeading,
                    endPoint: side == .left ? .bottomLeading : .bottomTrailing
                )
            )
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                GallaxyBrand.brandMaroon.opacity(0.22),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .accessibilityHidden(true)
    }
}

struct SideSpeakerRack: View {
    let side: SpeakerRackSide
    var expanded = false
    var speakerLevel = 0.0
    var panelLabel = "Side Panel"
    var toggleAction: (() -> Void)?

    var body: some View {
        let wingShape = SpeakerWingShape(side: side, verticalInsetFraction: 0.0, bottomExtension: 3)
        let rimShape = SpeakerWingRimShape(side: side, verticalInsetFraction: 0.0, bottomExtension: 3)

        ZStack {
            wingShape
                .fill(
                    LinearGradient(
                    colors: [
                            GallaxyBrand.textMain,
                            GallaxyBrand.brandMaroonReadable,
                            GallaxyBrand.brandMaroon,
                            GallaxyBrand.pageBackground
                        ],
                        startPoint: side == .left ? .topTrailing : .topLeading,
                        endPoint: side == .left ? .bottomLeading : .bottomTrailing
                    )
                )
                .overlay(
                    rimShape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    GallaxyBrand.textMain.opacity(0.55),
                                    GallaxyBrand.brandMaroonReadable.opacity(0.60),
                                    .black.opacity(0.65)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .clipShape(wingShape)
                )

            VStack(spacing: 10) {
                SpeakerCone(size: 64, level: speakerLevel)
                SpeakerCone(size: 58, level: speakerLevel * 0.82)
                SpeakerCone(size: 52, level: speakerLevel * 0.66)
            }
            .offset(x: side == .left ? -4 : 4, y: 1)

            if let toggleAction {
                Button(action: toggleAction) {
                    Image(systemName: chevronName)
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 28, height: 42)
                }
                .buttonStyle(SpeakerChevronButtonStyle(active: expanded))
                .offset(x: side == .left ? -43 : 43, y: 1)
                .accessibilityLabel(expanded ? "Collapse \(panelLabel)" : "Expand \(panelLabel)")
                .help(expanded ? "Collapse \(panelLabel.lowercased())" : "Expand \(panelLabel.lowercased())")
            } else {
                Image(systemName: side == .left ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.5))
                    .offset(x: side == .left ? -43 : 43, y: 1)
            }
        }
    }

    private var chevronName: String {
        switch side {
        case .left:
            return expanded ? "chevron.right" : "chevron.left"
        case .right:
            return expanded ? "chevron.left" : "chevron.right"
        }
    }
}

struct VoiceProviderPanel: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    var body: some View {
        ZStack {
            GallaxyDrawerGlassBackground(direction: .voice)

            VStack(alignment: .leading, spacing: 8) {
                Text("VOICE SOURCE")
                    .font(GallaxyBrand.displayFont(size: 11.4, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.96))

                Text("SELECT SOURCE")
                    .font(GallaxyBrand.displayFont(size: 9.8, weight: .bold))
                    .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))

                VStack(spacing: 5) {
                    ForEach(VoiceProviderOption.allCases) { provider in
                        Button {
                            viewModel.selectVoiceProvider(provider)
                        } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(provider == viewModel.selectedVoiceProvider ? GallaxyBrand.textMain : GallaxyBrand.pageBackground.opacity(0.45))
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(GallaxyBrand.textMain.opacity(0.28), lineWidth: 1))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(provider.title)
                                        .font(GallaxyBrand.displayFont(size: 10.9, weight: .bold))
                                    Text(provider.detail)
                                        .font(GallaxyBrand.bodyFont(size: 9.4, weight: .semibold))
                                        .foregroundStyle(GallaxyBrand.textMain.opacity(0.82))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(VoiceProviderButtonStyle(active: provider == viewModel.selectedVoiceProvider))
                        .accessibilityLabel("Select \(provider.title)")
                    }
                }

                if viewModel.selectedVoiceProvider == .elevenLabs {
                    ElevenLabsCredentialPanel(viewModel: viewModel)
                }

                Spacer(minLength: 0)

                Text(providerStatus)
                    .font(GallaxyBrand.displayFont(size: 9.2, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.80))
            }
            .padding(EdgeInsets(top: 12, leading: 34, bottom: 12, trailing: 34))
        }
    }

    private var providerStatus: String {
        if viewModel.selectedVoiceProvider == .elevenLabs {
            return viewModel.hasElevenLabsAPIKey ? "ELEVENLABS READY" : "API KEY NEEDED"
        }
        return "KOKORO LOCAL"
    }
}

struct ElevenLabsCredentialPanel: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
                .overlay(GallaxyBrand.borderSubtle)

            HStack {
                Text(viewModel.hasElevenLabsAPIKey ? "API KEY SAVED" : "API KEY")
                    .font(GallaxyBrand.displayFont(size: 9.2, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.80))
                Spacer()
                if viewModel.credentialMessage.isEmpty == false {
                    Text(viewModel.credentialMessage)
                        .font(GallaxyBrand.displayFont(size: 8.4, weight: .bold))
                        .foregroundStyle(GallaxyBrand.brandMaroonReadable)
                }
            }

            SecureField("xi-api-key", text: $viewModel.elevenLabsAPIKeyDraft)
                .font(GallaxyBrand.bodyFont(size: 9.8, weight: .medium))
                .textFieldStyle(.plain)
                .foregroundStyle(GallaxyBrand.textMain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(GallaxyBrand.pageBackground.opacity(0.54))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(GallaxyBrand.borderSubtle, lineWidth: 1)
                )

            HStack(spacing: 6) {
                Button {
                    viewModel.saveElevenLabsAPIKey()
                } label: {
                    Text(viewModel.hasElevenLabsAPIKey ? "UPDATE" : "SAVE")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PanelCommandButtonStyle())
                .disabled(!canSave)

                if viewModel.hasElevenLabsAPIKey {
                    Button {
                        viewModel.deleteElevenLabsAPIKey()
                    } label: {
                        Text("FORGET")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PanelCommandButtonStyle())
                }
            }
            .font(GallaxyBrand.displayFont(size: 9, weight: .bold))
        }
    }

    private var canSave: Bool {
        viewModel.elevenLabsAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

struct VoiceProviderButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? GallaxyBrand.textMain : GallaxyBrand.textMain.opacity(0.88))
            .background(GlassRowButtonBackground(active: active, pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(active ? GallaxyBrand.textMain.opacity(0.34) : GallaxyBrand.textMain.opacity(0.20), lineWidth: 1)
            )
    }
}

struct PanelCommandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(GallaxyBrand.textMain.opacity(configuration.isPressed ? 0.72 : 0.88))
            .padding(.vertical, 5)
            .background(GlassCommandButtonBackground(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(GallaxyBrand.textMain.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SlideoutRackPanel: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    var body: some View {
        ZStack {
            GallaxyDrawerGlassBackground(direction: .rack)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        viewModel.rightDrawerMode = .clips
                    } label: {
                        Text("CLIPS")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VoiceProviderButtonStyle(active: viewModel.rightDrawerMode == .clips))

                    Button {
                        viewModel.rightDrawerMode = .hotkey
                    } label: {
                        Text("HOTKEY")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VoiceProviderButtonStyle(active: viewModel.rightDrawerMode == .hotkey))
                }
                .font(GallaxyBrand.displayFont(size: 8.8, weight: .bold))
                .frame(height: 30)

                if viewModel.rightDrawerMode == .clips {
                    ClipTrayPanelContent(viewModel: viewModel)
                } else {
                    HotkeyConfigurationPanel(viewModel: viewModel)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 34, bottom: 12, trailing: 34))
        }
    }
}

struct ClipTrayPanelContent: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CLIP TRAY")
                    .font(GallaxyBrand.displayFont(size: 11.4, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.96))
                Spacer()
                Text("\(viewModel.recentClipboardClips.count + (viewModel.currentClipboardClip == nil ? 0 : 1))")
                    .font(GallaxyBrand.displayFont(size: 9.8, weight: .bold))
                    .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))
            }

            Text("CURRENT CLIP")
                .font(GallaxyBrand.displayFont(size: 8.8, weight: .bold))
                .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))

            if let currentClip = viewModel.currentClipboardClip {
                ClipTrayRow(
                    clip: currentClip,
                    badge: "NOW",
                    compact: false,
                    action: { viewModel.speakClip(currentClip) }
                )
                .frame(height: 54)
            } else {
                ClipTrayEmptyRow(text: "clipboard empty")
                    .frame(height: 54)
            }

            Divider()
                .overlay(GallaxyBrand.borderSubtle)

            Text("RECENT CLIPS")
                .font(GallaxyBrand.displayFont(size: 8.8, weight: .bold))
                .foregroundStyle(GallaxyBrand.textMain.opacity(0.78))

            let clips = viewModel.recentClipboardClips
            ScrollView(.vertical, showsIndicators: clips.count > 3) {
                VStack(spacing: 5) {
                    if clips.isEmpty {
                        ClipTrayEmptyRow(text: "no recent clips")
                            .frame(height: 34)
                    } else {
                        ForEach(clips) { clip in
                            ClipTrayRow(
                                clip: clip,
                                badge: clip.source.uppercased().prefix(4).description,
                                compact: true,
                                action: { viewModel.speakClip(clip) }
                            )
                            .frame(height: 34)
                        }
                    }
                }
                .padding(.trailing, clips.count > 3 ? 5 : 0)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

struct HotkeyConfigurationPanel: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("HOTKEY")
                    .font(GallaxyBrand.displayFont(size: 11.4, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.96))
                Spacer()
                if viewModel.hotkeyMessage.isEmpty == false {
                    Text(viewModel.hotkeyMessage)
                        .font(GallaxyBrand.displayFont(size: 8.2, weight: .bold))
                        .foregroundStyle(viewModel.hotkeyMessage == "UNAVAILABLE" ? GallaxyBrand.brandMaroonReadable : GallaxyBrand.textMain.opacity(0.78))
                }
            }

            Text(viewModel.isCapturingHotkey ? "PRESS A KEY" : "SPEAK SELECTION")
                .font(GallaxyBrand.displayFont(size: 8.8, weight: .bold))
                .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))

            HotkeyRecorderField(
                configuration: viewModel.hotkeyDraft,
                isRecording: $viewModel.isCapturingHotkey,
                onCapture: viewModel.captureHotkey
            )
            .frame(height: 38)

            Button {
                viewModel.saveHotkey()
            } label: {
                Text("SAVE")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelCommandButtonStyle())
            .font(GallaxyBrand.displayFont(size: 9, weight: .bold))

            Spacer(minLength: 0)
        }
    }
}

struct HotkeyRecorderField: NSViewRepresentable {
    let configuration: HotkeyConfiguration
    @Binding var isRecording: Bool
    let onCapture: (HotkeyConfiguration) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: HotkeyRecorderNSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: HotkeyRecorderNSView) {
        view.displayLabel = isRecording ? "PRESS A KEY" : configuration.displayLabel
        view.isRecording = isRecording
        view.onRecordingChange = { isRecording in
            DispatchQueue.main.async {
                self.isRecording = isRecording
            }
        }
        view.onCapture = { configuration in
            DispatchQueue.main.async {
                self.isRecording = false
                onCapture(configuration)
            }
        }
    }
}

final class HotkeyRecorderNSView: NSView {
    var displayLabel = "" {
        didSet { needsDisplay = true }
    }
    var isRecording = false {
        didSet { needsDisplay = true }
    }
    var onRecordingChange: ((Bool) -> Void)?
    var onCapture: ((HotkeyConfiguration) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if !isRecording {
            isRecording = true
            onRecordingChange?(true)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            onRecordingChange?(false)
            return
        }

        guard let configuration = HotkeyConfiguration.captured(from: event) else { return }
        isRecording = false
        onRecordingChange?(false)
        onCapture?(configuration)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            onRecordingChange?(false)
        }
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor(calibratedWhite: 0.03, alpha: isRecording ? 0.92 : 0.64).setFill()
        shape.fill()

        (isRecording ? NSColor(calibratedRed: 0.68, green: 0.08, blue: 0.12, alpha: 0.96) : NSColor(calibratedWhite: 0.82, alpha: 0.22)).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 0.95)
        ]
        let size = (displayLabel as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: max(8, (bounds.width - size.width) / 2),
            y: (bounds.height - size.height) / 2,
            width: min(size.width, max(0, bounds.width - 16)),
            height: size.height
        )
        (displayLabel as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

struct ClipTrayRow: View {
    let clip: ClipboardClip
    let badge: String
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                HStack(spacing: 5) {
                    Text(badge)
                        .font(GallaxyBrand.displayFont(size: compact ? 7.3 : 7.8, weight: .bold))
                        .foregroundStyle(GallaxyBrand.brandMaroonReadable.opacity(0.96))
                        .frame(width: 24, alignment: .leading)

                    Text(clip.title)
                        .font(GallaxyBrand.displayFont(size: compact ? 8.6 : 9.6, weight: .bold))
                        .foregroundStyle(GallaxyBrand.textMain.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(clip.preview)
                    .font(GallaxyBrand.bodyFont(size: compact ? 8.2 : 8.8, weight: .semibold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.76))
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, compact ? 4 : 6)
        }
        .buttonStyle(ClipTrayButtonStyle(active: !compact))
        .help(clip.preview)
    }
}

struct ClipTrayEmptyRow: View {
    let text: String

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(GallaxyBrand.pageBackground.opacity(0.22))
            .overlay(
                Text(text.uppercased())
                    .font(GallaxyBrand.displayFont(size: 8.2, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(GallaxyBrand.borderSubtle, lineWidth: 1)
            )
    }
}

struct ClipTrayButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(GlassRowButtonBackground(active: active, pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(active ? GallaxyBrand.textMain.opacity(0.30) : GallaxyBrand.textMain.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SpeakerChevronButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(chevronColor.opacity(configuration.isPressed ? 0.72 : 1))
            .contentShape(Rectangle())
            .shadow(color: GallaxyBrand.textMain.opacity(active ? 0.12 : 0.07), radius: 1, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }

    private var chevronColor: Color {
        active ? GallaxyBrand.brandMaroon : GallaxyBrand.brandMaroon.opacity(0.86)
    }
}

struct SpeakerWingShape: Shape {
    let side: SpeakerRackSide
    var verticalInsetFraction: CGFloat = 0.08
    var bottomExtension: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = rect.minY + rect.height * verticalInsetFraction
        let bottom = rect.maxY - rect.height * verticalInsetFraction + bottomExtension
        let innerX = rect.minX
        let outerX = rect.maxX
        let shelfX = rect.minX + rect.width * 0.26

        path.move(to: CGPoint(x: innerX, y: top))
        path.addLine(to: CGPoint(x: shelfX, y: top))

        path.addCurve(
            to: CGPoint(x: outerX, y: rect.midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.11, y: top),
            control2: CGPoint(x: outerX, y: rect.minY + rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: shelfX, y: bottom),
            control1: CGPoint(x: outerX, y: rect.maxY - rect.height * 0.28),
            control2: CGPoint(x: rect.maxX - rect.width * 0.11, y: bottom)
        )

        path.addLine(to: CGPoint(x: innerX, y: bottom))
        path.addLine(to: CGPoint(x: innerX, y: top))
        path.closeSubpath()

        if side == .left {
            let mirror = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -rect.midX, y: -rect.midY)
            return path.applying(mirror)
        }

        return path
    }
}

struct SpeakerWingRimShape: Shape {
    let side: SpeakerRackSide
    var verticalInsetFraction: CGFloat = 0.08
    var bottomExtension: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = rect.minY + rect.height * verticalInsetFraction
        let bottom = rect.maxY - rect.height * verticalInsetFraction + bottomExtension
        let innerX = rect.minX
        let outerX = rect.maxX
        let shelfX = rect.minX + rect.width * 0.26

        path.move(to: CGPoint(x: innerX, y: top))
        path.addLine(to: CGPoint(x: shelfX, y: top))
        path.addCurve(
            to: CGPoint(x: outerX, y: rect.midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.11, y: top),
            control2: CGPoint(x: outerX, y: rect.minY + rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: shelfX, y: bottom),
            control1: CGPoint(x: outerX, y: rect.maxY - rect.height * 0.28),
            control2: CGPoint(x: rect.maxX - rect.width * 0.11, y: bottom)
        )
        path.addLine(to: CGPoint(x: innerX, y: bottom))

        if side == .left {
            let mirror = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -rect.midX, y: -rect.midY)
            return path.applying(mirror)
        }

        return path
    }
}

struct SpeakerCone: View {
    let size: CGFloat
    var level = 0.0

    private var pulse: CGFloat {
        CGFloat(min(1, max(0, level)))
    }

    var body: some View {
        let coneScale = 1 + pulse * 0.10
        let capScale = 1 + pulse * 0.13

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.10, green: 0.10, blue: 0.09),
                            Color(red: 0.02, green: 0.02, blue: 0.02)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.34),
                        startRadius: size * 0.20,
                        endRadius: size * 0.55
                    )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    GallaxyBrand.textMain.opacity(0.28),
                                    .black.opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                )

            Circle()
                .fill(Color(red: 0.025, green: 0.024, blue: 0.022))
                .frame(width: size * 0.84, height: size * 0.84)
                .shadow(color: .black.opacity(0.66), radius: 2, x: 0, y: 1)

            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.63, green: 0.52, blue: 0.36),
                                Color(red: 0.08, green: 0.07, blue: 0.06)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.32),
                            startRadius: 0,
                            endRadius: 3
                        )
                    )
                    .frame(width: size * 0.075, height: size * 0.075)
                    .offset(y: -(size * 0.43))
                    .rotationEffect(.degrees(Double(index) * 90 + 45))
                    .accessibilityHidden(true)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.78, green: 0.62, blue: 0.40),
                            Color(red: 0.54, green: 0.37, blue: 0.22),
                            Color(red: 0.19, green: 0.13, blue: 0.09)
                        ],
                        center: UnitPoint(x: 0.40, y: 0.32),
                        startRadius: size * 0.04,
                        endRadius: size * 0.34
                    )
                )
                .frame(width: size * 0.68, height: size * 0.68)
                .overlay(
                    Circle()
                        .stroke(.black.opacity(0.72), lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .trim(from: 0.05, to: 0.38)
                        .stroke(GallaxyBrand.textMain.opacity(0.17), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-18))
                )
                .scaleEffect(coneScale)
                .brightness(Double(pulse) * 0.04)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.20, green: 0.22, blue: 0.20),
                            Color(red: 0.045, green: 0.047, blue: 0.045)
                        ],
                        center: UnitPoint(x: 0.36, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.18
                    )
                )
                .frame(width: size * 0.29, height: size * 0.29)
                .overlay(
                    Circle()
                        .stroke(.black.opacity(0.86), lineWidth: 1.6)
                )
                .scaleEffect(capScale)
                .shadow(
                    color: GallaxyBrand.brandMaroonReadable.opacity(0.10 + Double(pulse) * 0.22),
                    radius: 1 + Double(pulse) * 3,
                    x: 0,
                    y: 0
                )
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.035), value: level)
    }
}

struct TerminalConsoleView: View {
    let lines: [String]
    let active: Bool
    let paused: Bool

    var body: some View {
        let displayLines = lines.filter { $0 != "GALLAXY TTS CONSOLE" }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            GallaxyBrand.panelSurface,
                            GallaxyBrand.brandMaroon.opacity(0.12),
                            GallaxyBrand.pageBackground.opacity(0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(foregroundColor(for: index))
                        .lineLimit(index == displayLines.count - 1 ? 3 : 1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var borderColor: Color {
        if paused {
            return GallaxyBrand.textMuted.opacity(0.28)
        }
        return active ? GallaxyBrand.brandMaroonReadable.opacity(0.42) : GallaxyBrand.borderSubtle
    }

    private func foregroundColor(for index: Int) -> Color {
        if paused {
            return GallaxyBrand.textMuted
        }
        return active ? GallaxyBrand.textMain.opacity(0.86) : GallaxyBrand.textMuted
    }
}

struct GallaxyHoverGlow: ViewModifier {
    let radius: CGFloat
    let scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .shadow(
                color: GallaxyBrand.brandMaroonReadable.opacity(hovering ? 0.46 : 0),
                radius: hovering ? radius : 0,
                x: 0,
                y: hovering ? 2 : 0
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func gallaxyHoverGlow(radius: CGFloat, scale: CGFloat) -> some View {
        modifier(GallaxyHoverGlow(radius: radius, scale: scale))
    }
}

struct GallaxySpeedControl: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> GallaxySpeedSliderControl {
        let control = GallaxySpeedSliderControl()
        control.minimumValue = range.lowerBound
        control.maximumValue = range.upperBound
        control.setSpeedValue(value, notify: false)
        control.target = context.coordinator
        control.action = #selector(Coordinator.speedChanged(_:))
        return control
    }

    func updateNSView(_ nsView: GallaxySpeedSliderControl, context: Context) {
        context.coordinator.parent = self
        nsView.minimumValue = range.lowerBound
        nsView.maximumValue = range.upperBound
        nsView.setSpeedValue(value, notify: false)
    }

    final class Coordinator: NSObject {
        var parent: GallaxySpeedControl

        init(_ parent: GallaxySpeedControl) {
            self.parent = parent
        }

        @objc func speedChanged(_ sender: GallaxySpeedSliderControl) {
            parent.value = sender.speedValue
        }
    }
}

final class GallaxySpeedSliderControl: NSControl {
    var minimumValue: Double = 0.75 {
        didSet { setSpeedValue(speedValue, notify: false) }
    }

    var maximumValue: Double = 1.6 {
        didSet { setSpeedValue(speedValue, notify: false) }
    }

    private(set) var speedValue: Double = 1.15
    private var hovering = false
    private var dragging = false
    private var tracking: NSTrackingArea?

    private let knobDiameter: CGFloat = 25
    private let trackHeight: CGFloat = 16

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 34) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Speed")
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Speed")
        updateAccessibilityValue()
    }

    func setSpeedValue(_ nextValue: Double, notify: Bool) {
        let clamped = min(maximumValue, max(minimumValue, nextValue))
        guard abs(clamped - speedValue) > 0.0001 else {
            updateAccessibilityValue()
            return
        }

        speedValue = clamped
        needsDisplay = true
        updateAccessibilityValue()

        if notify, let action {
            sendAction(action, to: target)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
        let nextTracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(nextTracking)
        tracking = nextTracking
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragging = true
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow, .downArrow:
            setSpeedValue(speedValue - 0.05, notify: true)
        case .rightArrow, .upArrow:
            setSpeedValue(speedValue + 0.05, notify: true)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        setSpeedValue(speedValue + 0.05, notify: true)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        setSpeedValue(speedValue - 0.05, notify: true)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let progress = CGFloat((speedValue - minimumValue) / max(0.001, maximumValue - minimumValue))
        let knobRadius = knobDiameter / 2
        let trackRect = NSRect(
            x: knobRadius,
            y: bounds.midY - trackHeight / 2,
            width: max(1, bounds.width - knobDiameter),
            height: trackHeight
        )
        let progressWidth = max(trackHeight, trackRect.width * min(1, max(0, progress)))
        let progressRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: min(trackRect.width, progressWidth),
            height: trackRect.height
        )
        let knobX = trackRect.minX + trackRect.width * min(1, max(0, progress))
        let knobRect = NSRect(
            x: knobX - knobRadius,
            y: bounds.midY - knobRadius,
            width: knobDiameter,
            height: knobDiameter
        )

        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.gallaxyHex(0x070706, alpha: hovering || dragging ? 0.88 : 0.72).setFill()
        trackPath.fill()
        NSColor.gallaxyHex(0xe9e3d5, alpha: hovering || dragging ? 0.22 : 0.14).setStroke()
        trackPath.lineWidth = 1
        trackPath.stroke()

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        let progressPath = NSBezierPath(roundedRect: progressRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        let progressGradient = NSGradient(colors: [
            NSColor.gallaxyHex(0x6b1f26, alpha: 0.96),
            NSColor.gallaxyHex(0xa63a43, alpha: 0.98),
            NSColor.gallaxyHex(0xe9e3d5, alpha: 0.72)
        ])
        progressGradient?.draw(in: progressPath, angle: 0)

        let shineRect = NSRect(x: trackRect.minX, y: trackRect.midY, width: trackRect.width, height: trackRect.height / 2)
        NSColor.white.withAlphaComponent(hovering || dragging ? 0.12 : 0.08).setFill()
        NSBezierPath(roundedRect: shineRect, xRadius: shineRect.height / 2, yRadius: shineRect.height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        let knobPath = NSBezierPath(ovalIn: knobRect)
        NSShadow.gallaxy(color: .black.withAlphaComponent(0.48), blur: dragging ? 5 : 4, y: dragging ? 2 : 3) {
            NSGradient(colors: [
                NSColor.gallaxyHex(0xe9e3d5, alpha: 0.98),
                NSColor.gallaxyHex(0xbeb6a7, alpha: 0.95),
                NSColor.gallaxyHex(0x566b57, alpha: 0.58)
            ])?.draw(in: knobPath, angle: -90)
        }

        NSColor.gallaxyHex(0xe9e3d5, alpha: dragging ? 0.58 : 0.34).setStroke()
        knobPath.lineWidth = dragging ? 2 : 1.4
        knobPath.stroke()
    }

    private func updateValue(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let knobRadius = knobDiameter / 2
        let usableWidth = max(1, bounds.width - knobDiameter)
        let progress = min(1, max(0, (point.x - knobRadius) / usableWidth))
        let nextValue = minimumValue + Double(progress) * (maximumValue - minimumValue)
        setSpeedValue(nextValue, notify: true)
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue(String(format: "%.2fx", speedValue))
    }
}

private extension NSColor {
    static func gallaxyHex(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private extension NSShadow {
    static func gallaxy(color: NSColor, blur: CGFloat, y: CGFloat, draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -y)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct GallaxyPlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 24, weight: .black))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(RetroRoundButtonStyle())
        .gallaxyHoverGlow(radius: 7, scale: 1.045)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityLabel("Play")
    }
}

struct GallaxyStopButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: 16, weight: .black))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(RetroStopButtonStyle(active: active))
        .gallaxyHoverGlow(radius: 5, scale: 1.04)
        .accessibilityLabel("Stop")
    }
}

struct GallaxyPinButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: active ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(RetroPinButtonStyle(active: active))
        .gallaxyHoverGlow(radius: 4, scale: 1.08)
        .accessibilityLabel(active ? "Unpin Window" : "Pin Window")
    }
}

struct GlassPlayButtonBackground: View {
    let pressed: Bool

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: pressed
                        ? [GallaxyBrand.brandMaroon.opacity(0.92), GallaxyBrand.pageBackground.opacity(0.86)]
                        : [GallaxyBrand.brandMaroonReadable.opacity(0.96), GallaxyBrand.brandMaroon.opacity(0.78), GallaxyBrand.pageBackground.opacity(0.66)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                GallaxyBrand.textMain.opacity(pressed ? 0.16 : 0.28),
                                .clear
                            ],
                            center: UnitPoint(x: 0.32, y: 0.24),
                            startRadius: 1,
                            endRadius: 30
                        )
                    )
            )
    }
}

struct GlassStopButtonBackground: View {
    let active: Bool
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        shape
            .fill(
                LinearGradient(
                    colors: pressed
                        ? [GallaxyBrand.pageBackground, GallaxyBrand.brandMaroon.opacity(0.52)]
                        : [GallaxyBrand.textMain.opacity(0.22), GallaxyBrand.pageBackground.opacity(0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                GallaxyBrand.textMain.opacity(active ? 0.13 : 0.08),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }
}

struct GlassPinButtonBackground: View {
    let active: Bool
    let pressed: Bool

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: active
                        ? [GallaxyBrand.textMain.opacity(pressed ? 0.14 : 0.22), GallaxyBrand.brandMaroon.opacity(0.48)]
                        : [GallaxyBrand.textMain.opacity(pressed ? 0.12 : 0.18), GallaxyBrand.pageBackground.opacity(0.70)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

struct GlassRowButtonBackground: View {
    let active: Bool
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        shape
            .fill(active ? GallaxyBrand.brandMaroonReadable.opacity(0.34) : GallaxyBrand.pageBackground.opacity(pressed ? 0.42 : 0.26))
    }
}

struct GlassCommandButtonBackground: View {
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        shape
            .fill(pressed ? GallaxyBrand.brandMaroon.opacity(0.74) : GallaxyBrand.pageBackground.opacity(0.36))
    }
}

struct RetroSpeedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let knobSize: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let progress = progress(for: value)
            let usableWidth = max(1, geometry.size.width - knobSize)
            let knobX = knobSize / 2 + usableWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(GallaxyBrand.pageBackground.opacity(0.72))
                    .frame(height: 7)
                    .padding(.horizontal, knobSize / 2)
                    .overlay(
                        Capsule()
                            .stroke(GallaxyBrand.borderSubtle, lineWidth: 1)
                            .padding(.horizontal, knobSize / 2)
                    )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                GallaxyBrand.brandMaroon.opacity(0.76),
                                GallaxyBrand.brandMaroonReadable.opacity(0.94)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, knobX - knobSize / 2), height: 5)
                    .padding(.leading, knobSize / 2)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                GallaxyBrand.textMain.opacity(0.96),
                                GallaxyBrand.textMain.opacity(0.64)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: knobSize, height: knobSize)
                    .overlay(Circle().stroke(GallaxyBrand.borderSubtle, lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
                    .position(x: knobX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        setValue(from: gesture.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel("Speed")
        .accessibilityValue(Text(String(format: "%.2fx", value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(range.upperBound, value + 0.05)
            case .decrement:
                value = max(range.lowerBound, value - 0.05)
            @unknown default:
                break
            }
        }
    }

    private func progress(for value: Double) -> CGFloat {
        let span = max(0.001, range.upperBound - range.lowerBound)
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        return CGFloat((clamped - range.lowerBound) / span)
    }

    private func setValue(from locationX: CGFloat, width: CGFloat) {
        let usableWidth = max(1, width - knobSize)
        let rawProgress = (locationX - knobSize / 2) / usableWidth
        let clampedProgress = min(1, max(0, rawProgress))
        let nextValue = range.lowerBound + Double(clampedProgress) * (range.upperBound - range.lowerBound)
        value = nextValue
    }
}

struct RetroStopButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? GallaxyBrand.textMain : GallaxyBrand.textMain.opacity(0.94))
            .background(GlassStopButtonBackground(active: active, pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(active ? GallaxyBrand.brandMaroonReadable.opacity(0.48) : GallaxyBrand.borderSubtle, lineWidth: 1.2)
            )
            .shadow(color: GallaxyBrand.brandMaroon.opacity(configuration.isPressed ? 0.16 : 0.32), radius: configuration.isPressed ? 1 : 4, x: 0, y: configuration.isPressed ? 1 : 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct RetroPinButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? GallaxyBrand.textMain : GallaxyBrand.textMain.opacity(0.86))
            .background(GlassPinButtonBackground(active: active, pressed: configuration.isPressed))
            .overlay(
                Circle()
                    .stroke(active ? GallaxyBrand.brandMaroonReadable.opacity(0.62) : GallaxyBrand.textMain.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: active ? GallaxyBrand.brandMaroonReadable.opacity(0.24) : .clear, radius: 4, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

struct RetroRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(GallaxyBrand.textMain)
            .background(GlassPlayButtonBackground(pressed: configuration.isPressed))
            .overlay(Circle().stroke(GallaxyBrand.textMain.opacity(0.22), lineWidth: 1.5))
            .shadow(color: GallaxyBrand.brandMaroonReadable.opacity(configuration.isPressed ? 0.12 : 0.34), radius: configuration.isPressed ? 1 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.2 : 0.5), radius: configuration.isPressed ? 1 : 4, x: 0, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
    }
}

struct RetroTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(0.88))
            .background(
                Capsule()
                    .fill(configuration.isPressed ? Color.gray.opacity(0.45) : Color.black.opacity(0.32))
            )
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct WindowResizeOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleNSView {
        ResizeHandleNSView()
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {}
}

final class ResizeHandleNSView: NSView {
    private enum ResizeRegion {
        case left
        case right
        case top
        case bottom
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    private let hitThickness: CGFloat = 18
    private let cornerLength: CGFloat = 42
    private var activeRegion: ResizeRegion?
    private var initialWindowFrame = NSRect.zero
    private var initialMouseLocation = NSPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        resizeRegion(at: point) == nil ? nil : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x: 0, y: bounds.maxY - cornerLength, width: cornerLength, height: cornerLength), cursor: Self.northWestSouthEastCursor)
        addCursorRect(NSRect(x: bounds.maxX - cornerLength, y: bounds.maxY - cornerLength, width: cornerLength, height: cornerLength), cursor: Self.northEastSouthWestCursor)
        addCursorRect(NSRect(x: 0, y: 0, width: cornerLength, height: cornerLength), cursor: Self.northEastSouthWestCursor)
        addCursorRect(NSRect(x: bounds.maxX - cornerLength, y: 0, width: cornerLength, height: cornerLength), cursor: Self.northWestSouthEastCursor)
        addCursorRect(NSRect(x: hitThickness, y: bounds.maxY - hitThickness, width: max(0, bounds.width - hitThickness * 2), height: hitThickness), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: hitThickness, y: 0, width: max(0, bounds.width - hitThickness * 2), height: hitThickness), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: hitThickness, width: hitThickness, height: max(0, bounds.height - hitThickness * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.maxX - hitThickness, y: hitThickness, width: hitThickness, height: max(0, bounds.height - hitThickness * 2)), cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        activeRegion = resizeRegion(at: convert(event.locationInWindow, from: nil))
        initialWindowFrame = window?.frame ?? .zero
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let activeRegion else { return }
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y
        let nextFrame = resizedFrame(
            for: activeRegion,
            deltaX: deltaX,
            deltaY: deltaY,
            window: window
        )
        window.setFrame(nextFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        activeRegion = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    private func resizeRegion(at point: NSPoint) -> ResizeRegion? {
        let nearLeft = point.x <= hitThickness
        let nearRight = point.x >= bounds.maxX - hitThickness
        let nearBottom = point.y <= hitThickness
        let nearTop = point.y >= bounds.maxY - hitThickness
        let inLeftCorner = point.x <= cornerLength
        let inRightCorner = point.x >= bounds.maxX - cornerLength
        let inBottomCorner = point.y <= cornerLength
        let inTopCorner = point.y >= bounds.maxY - cornerLength

        if inLeftCorner && inTopCorner { return .topLeft }
        if inRightCorner && inTopCorner { return .topRight }
        if inLeftCorner && inBottomCorner { return .bottomLeft }
        if inRightCorner && inBottomCorner { return .bottomRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        return nil
    }

    private func resizedFrame(for region: ResizeRegion, deltaX: CGFloat, deltaY: CGFloat, window: NSWindow) -> NSRect {
        let minimumSize = window.minSize
        let maximumSize = window.maxSize
        let ratio = max(0.1, window.contentAspectRatio.width / max(1, window.contentAspectRatio.height))
        let minimumScale = max(minimumSize.width / initialWindowFrame.width, minimumSize.height / initialWindowFrame.height)
        let maximumScale = min(maximumSize.width / initialWindowFrame.width, maximumSize.height / initialWindowFrame.height)
        let rawScale = rawResizeScale(for: region, deltaX: deltaX, deltaY: deltaY)
        let clampedScale = min(maximumScale, max(minimumScale, rawScale))
        let nextWidth = initialWindowFrame.width * clampedScale
        let nextHeight = nextWidth / ratio

        var nextFrame = initialWindowFrame
        nextFrame.size = NSSize(width: nextWidth, height: nextHeight)

        switch region {
        case .left, .topLeft, .bottomLeft:
            nextFrame.origin.x = initialWindowFrame.maxX - nextWidth
        default:
            break
        }

        switch region {
        case .bottom, .bottomLeft, .bottomRight:
            nextFrame.origin.y = initialWindowFrame.maxY - nextHeight
        default:
            break
        }

        if let visibleFrame = window.screen?.visibleFrame {
            nextFrame.size.width = min(nextFrame.width, visibleFrame.width)
            nextFrame.size.height = min(nextFrame.height, visibleFrame.height)
        }

        return nextFrame
    }

    private func rawResizeScale(for region: ResizeRegion, deltaX: CGFloat, deltaY: CGFloat) -> CGFloat {
        let width = max(1, initialWindowFrame.width)
        let height = max(1, initialWindowFrame.height)

        switch region {
        case .right:
            return (initialWindowFrame.width + deltaX) / width
        case .left:
            return (initialWindowFrame.width - deltaX) / width
        case .top:
            return (initialWindowFrame.height + deltaY) / height
        case .bottom:
            return (initialWindowFrame.height - deltaY) / height
        case .topRight:
            return dominantScale(widthScale: (initialWindowFrame.width + deltaX) / width, heightScale: (initialWindowFrame.height + deltaY) / height)
        case .topLeft:
            return dominantScale(widthScale: (initialWindowFrame.width - deltaX) / width, heightScale: (initialWindowFrame.height + deltaY) / height)
        case .bottomRight:
            return dominantScale(widthScale: (initialWindowFrame.width + deltaX) / width, heightScale: (initialWindowFrame.height - deltaY) / height)
        case .bottomLeft:
            return dominantScale(widthScale: (initialWindowFrame.width - deltaX) / width, heightScale: (initialWindowFrame.height - deltaY) / height)
        }
    }

    private func dominantScale(widthScale: CGFloat, heightScale: CGFloat) -> CGFloat {
        abs(widthScale - 1) >= abs(heightScale - 1) ? widthScale : heightScale
    }

    private static let northWestSouthEastCursor = diagonalCursor(systemName: "arrow.up.left.and.down.right", fallback: .resizeLeftRight)
    private static let northEastSouthWestCursor = diagonalCursor(systemName: "arrow.up.right.and.down.left", fallback: .resizeLeftRight)

    private static func diagonalCursor(systemName: String, fallback: NSCursor) -> NSCursor {
        guard let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return fallback
        }
        image.size = NSSize(width: 22, height: 22)
        return NSCursor(image: image, hotSpot: NSPoint(x: 11, y: 11))
    }
}

struct RetroSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? Color.black.opacity(0.55) : Color.black.opacity(0.32))
            )
            .overlay(Capsule().stroke(.white.opacity(0.20), lineWidth: 1))
    }
}

struct RetroSideButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? .green.opacity(0.95) : .white.opacity(0.82))
            .background(
                Capsule()
                    .fill(configuration.isPressed ? Color.black.opacity(0.58) : Color.black.opacity(0.30))
            )
            .overlay(Capsule().stroke(active ? .green.opacity(0.45) : .white.opacity(0.20), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
