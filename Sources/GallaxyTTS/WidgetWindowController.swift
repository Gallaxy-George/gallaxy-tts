import AppKit
import SwiftUI

enum VoiceProviderOption: String, CaseIterable, Identifiable {
    case localPiper = "localPiper"
    case elevenLabs = "elevenLabs"
    case geminiFlash = "geminiFlash"
    case customAPI = "customAPI"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localPiper:
            return "LOCAL PIPER"
        case .elevenLabs:
            return "ELEVENLABS"
        case .geminiFlash:
            return "GEMINI FLASH"
        case .customAPI:
            return "CUSTOM API"
        }
    }

    var detail: String {
        switch self {
        case .localPiper:
            return "free local voice"
        case .elevenLabs:
            return "cloud voice"
        case .geminiFlash:
            return "flash voice"
        case .customAPI:
            return "bring your own"
        }
    }
}

enum WidgetPlayResult {
    case selection(String)
    case clipboard(String)
    case empty
}

final class WidgetWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: GallaxyTTSWidgetViewModel

    init(router: SpeechRequestRouter, playHandler: @escaping () -> WidgetPlayResult?) {
        self.viewModel = GallaxyTTSWidgetViewModel(router: router, playHandler: playHandler)

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
    @Published var selectedVoiceProvider: VoiceProviderOption = .localPiper
    @Published var elevenLabsAPIKeyDraft = ""
    @Published var hasElevenLabsAPIKey = false
    @Published var credentialMessage = ""
    @Published var speakerLevel: Double = 0
    @Published var consoleLines = [
        "GALLAXY TTS CONSOLE",
        "> ready",
        "> select text or copy text",
        "> press play"
    ]

    weak var window: NSWindow?
    private let router: SpeechRequestRouter
    private let playHandler: () -> WidgetPlayResult?
    private let defaults = UserDefaults.standard
    private let pinnedDefaultsKey = "widgetPinned"
    private let leftDrawerDefaultsKey = "leftDrawerExpanded"
    private let rightDrawerDefaultsKey = "rightDrawerExpanded"
    private let voiceProviderDefaultsKey = "voiceProvider"
    private var hasStartedPlayback = false

    static let sideSpeakerWidth: CGFloat = 118
    static let mainDeckWidth: CGFloat = 430
    static let drawerPanelWidth: CGFloat = 238
    static let drawerPanelHeight: CGFloat = 312
    static let interSectionOverlap: CGFloat = 22
    static let widgetHeight: CGFloat = 350
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

    init(router: SpeechRequestRouter, playHandler: @escaping () -> WidgetPlayResult?) {
        self.router = router
        self.playHandler = playHandler
        self.speed = router.speechSpeedMultiplier
        self.status = router.statusLine
        self.isPinned = defaults.bool(forKey: pinnedDefaultsKey)
        self.leftDrawerExpanded = defaults.bool(forKey: leftDrawerDefaultsKey)
        self.rightDrawerExpanded = defaults.bool(forKey: rightDrawerDefaultsKey)
        if let savedProvider = defaults.string(forKey: voiceProviderDefaultsKey),
           let provider = VoiceProviderOption(rawValue: savedProvider) {
            self.selectedVoiceProvider = provider
        }
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

    func refresh() {
        speed = router.speechSpeedMultiplier
        status = router.statusLine
        isSpeaking = router.isSpeaking
        isPaused = router.isPaused
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
            "> reading selection",
            "> fallback: clipboard"
        ]
        switch playHandler() {
        case .selection(let text):
            hasStartedPlayback = true
            isPaused = false
            isSpeaking = true
            status = "Speaking"
            setSpeakingConsole(source: "selection", text: text)
        case .clipboard(let text):
            hasStartedPlayback = true
            isPaused = false
            isSpeaking = true
            status = "Speaking"
            setSpeakingConsole(source: "clipboard", text: text)
        case .empty:
            isPaused = false
            isSpeaking = false
            status = "No text found"
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> no selected text",
                "> clipboard is empty"
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

    func toggleLeftDrawer() {
        let previousWidgetWidth = widgetWidth
        leftDrawerExpanded.toggle()
        defaults.set(leftDrawerExpanded, forKey: leftDrawerDefaultsKey)
        applyDrawerWindowSize(animated: true, anchor: .right, previousWidgetWidth: previousWidgetWidth)
    }

    func toggleRightDrawer() {
        let previousWidgetWidth = widgetWidth
        rightDrawerExpanded.toggle()
        defaults.set(rightDrawerExpanded, forKey: rightDrawerDefaultsKey)
        applyDrawerWindowSize(animated: true, anchor: .left, previousWidgetWidth: previousWidgetWidth)
    }

    func selectVoiceProvider(_ provider: VoiceProviderOption) {
        selectedVoiceProvider = provider
        defaults.set(provider.rawValue, forKey: voiceProviderDefaultsKey)
        credentialMessage = ""

        if provider == .elevenLabs {
            consoleLines = [
                "GALLAXY TTS CONSOLE",
                "> voice source: ELEVENLABS",
                hasElevenLabsAPIKey ? "> api key saved" : "> checking api key"
            ]
            refreshElevenLabsCredentialState(updateConsole: true)
            return
        }

        consoleLines = [
            "GALLAXY TTS CONSOLE",
            "> voice source: \(provider.title)",
            "> ready"
        ]
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
                    "> voice source: ELEVENLABS",
                    hasKey ? "> api key saved" : "> enter api key"
                ]
            }
        }
    }

    func applyDrawerWindowSize(
        animated: Bool,
        anchor: DrawerResizeAnchor = .left,
        preserveCurrentScale: Bool = true,
        previousWidgetWidth: CGFloat? = nil
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
        if anchor == .right {
            frame.origin.x -= width - oldWidth
        }

        if let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let rightInset: CGFloat = 18
            if frame.maxX > visibleFrame.maxX - rightInset {
                frame.origin.x = max(visibleFrame.minX + rightInset, visibleFrame.maxX - width - rightInset)
            }
            if frame.minX < visibleFrame.minX + rightInset {
                frame.origin.x = visibleFrame.minX + rightInset
            }
        }

        window.setFrame(frame, display: true, animate: animated)
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
        if isSpeaking {
            return "SPEAKING"
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
        HStack(alignment: .center, spacing: -GallaxyTTSWidgetViewModel.interSectionOverlap) {
            SideSpeakerRack(
                side: .left,
                expanded: viewModel.leftDrawerExpanded,
                speakerLevel: viewModel.speakerLevel,
                panelLabel: "Voice Model Panel",
                toggleAction: viewModel.toggleLeftDrawer
            )
                .frame(
                    width: GallaxyTTSWidgetViewModel.sideSpeakerWidth,
                    height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                )
                .zIndex(0)

            if viewModel.leftDrawerExpanded {
                VoiceProviderPanel(viewModel: viewModel)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.drawerPanelWidth,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .zIndex(1)
            }

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
                                Text(String(format: "%.2fx", viewModel.speed))
                                    .font(GallaxyBrand.displayFont(size: 10, weight: .semibold))
                                    .foregroundStyle(GallaxyBrand.textMuted)
                            }

                            TerminalConsoleView(
                                lines: viewModel.consoleLines,
                                active: viewModel.isSpeaking,
                                paused: viewModel.isPaused
                            )
                                .frame(height: 112)

                            Text(viewModel.status)
                                .font(GallaxyBrand.bodyFont(size: 10, weight: .medium))
                                .foregroundStyle(GallaxyBrand.textMuted)
                                .lineLimit(1)
                        }
                        .padding(10)
                    }
                    .frame(minWidth: 230, minHeight: 184)

                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            viewModel.play()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 24, weight: .black))
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(RetroRoundButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])
                        .accessibilityLabel("Play")

                        Button {
                            viewModel.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16, weight: .black))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(RetroStopButtonStyle(active: viewModel.isPaused))
                        .accessibilityLabel("Stop")

                        RetroSpeedSlider(
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

                        Button {
                            viewModel.setPinned(!viewModel.isPinned)
                        } label: {
                            Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(RetroPinButtonStyle(active: viewModel.isPinned))
                        .accessibilityLabel(viewModel.isPinned ? "Unpin Window" : "Pin Window")
                        .help(viewModel.isPinned ? "Unpin widget" : "Pin widget above other windows")
                    }
                    .padding(.top, 2)
                }
                .padding(18)
            }
            .frame(width: GallaxyTTSWidgetViewModel.mainDeckWidth, height: 330)
            .zIndex(3)

            if viewModel.rightDrawerExpanded {
                SlideoutRackPanel(viewModel: viewModel)
                    .frame(
                        width: GallaxyTTSWidgetViewModel.drawerPanelWidth,
                        height: GallaxyTTSWidgetViewModel.drawerPanelHeight
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                    .zIndex(1)
            }

            SideSpeakerRack(
                side: .right,
                expanded: viewModel.rightDrawerExpanded,
                speakerLevel: viewModel.speakerLevel,
                panelLabel: "Side Panel",
                toggleAction: viewModel.toggleRightDrawer
            )
            .frame(
                width: GallaxyTTSWidgetViewModel.sideSpeakerWidth,
                height: GallaxyTTSWidgetViewModel.drawerPanelHeight
            )
            .zIndex(0)
        }
        .frame(width: viewModel.widgetWidth, height: GallaxyTTSWidgetViewModel.widgetHeight, alignment: .leading)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.leftDrawerExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.rightDrawerExpanded)
    }

    private func widgetScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / max(1, viewModel.widgetWidth)
        let heightScale = size.height / GallaxyTTSWidgetViewModel.widgetHeight
        return GallaxyTTSWidgetViewModel.clampedWidgetScale(min(widthScale, heightScale))
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

enum SpeakerRackSide {
    case left
    case right
}

struct SideSpeakerRack: View {
    let side: SpeakerRackSide
    var expanded = false
    var speakerLevel = 0.0
    var panelLabel = "Side Panel"
    var toggleAction: (() -> Void)?

    var body: some View {
        ZStack {
            SpeakerWingShape(side: side, verticalInsetFraction: 0.0)
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
                    SpeakerWingShape(side: side, verticalInsetFraction: 0.0)
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
                )
                .shadow(
                    color: GallaxyBrand.brandMaroonReadable.opacity(0.144 + min(0.288, speakerLevel * 0.288)),
                    radius: 6 + (speakerLevel * 8.4),
                    x: 0,
                    y: 1
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            GallaxyBrand.pageBackground.opacity(0.96),
                            GallaxyBrand.brandMaroon.opacity(0.82),
                            GallaxyBrand.brandGreen.opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(GallaxyBrand.textMain.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                Text("VOICE SOURCE")
                    .font(GallaxyBrand.displayFont(size: 10, weight: .bold))
                    .foregroundStyle(GallaxyBrand.textMain.opacity(0.86))

                Text("SELECT MODEL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(GallaxyBrand.brandMaroonReadable)

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
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    Text(provider.detail)
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .opacity(0.68)
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
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(GallaxyBrand.textMuted)
            }
            .padding(12)
        }
    }

    private var providerStatus: String {
        if viewModel.selectedVoiceProvider == .elevenLabs {
            return viewModel.hasElevenLabsAPIKey ? "ELEVENLABS READY" : "API KEY NEEDED"
        }
        return "ROUTER READY"
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
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(GallaxyBrand.textMuted)
                Spacer()
                if viewModel.credentialMessage.isEmpty == false {
                    Text(viewModel.credentialMessage)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(GallaxyBrand.brandMaroonReadable)
                }
            }

            SecureField("xi-api-key", text: $viewModel.elevenLabsAPIKeyDraft)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
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
            .foregroundStyle(active ? GallaxyBrand.textMain : GallaxyBrand.textMain.opacity(0.72))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(active ? GallaxyBrand.brandMaroonReadable.opacity(0.28) : GallaxyBrand.pageBackground.opacity(configuration.isPressed ? 0.36 : 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(active ? GallaxyBrand.textMain.opacity(0.22) : GallaxyBrand.borderSubtle, lineWidth: 1)
            )
    }
}

struct PanelCommandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(GallaxyBrand.textMain.opacity(configuration.isPressed ? 0.72 : 0.88))
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ? GallaxyBrand.brandMaroon.opacity(0.74) : GallaxyBrand.pageBackground.opacity(0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(GallaxyBrand.textMain.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SlideoutRackPanel: View {
    @ObservedObject var viewModel: GallaxyTTSWidgetViewModel

    private let bands: [CGFloat] = [0.38, 0.58, 0.46, 0.78, 0.50, 0.67, 0.42]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            GallaxyBrand.brandGreen.opacity(0.88),
                            GallaxyBrand.brandMaroon.opacity(0.82),
                            GallaxyBrand.pageBackground.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(GallaxyBrand.textMain.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("VOICE RACK")
                        .font(GallaxyBrand.displayFont(size: 10, weight: .bold))
                        .foregroundStyle(GallaxyBrand.textMain.opacity(0.86))
                    Spacer()
                    Text(viewModel.activityLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(GallaxyBrand.brandMaroonReadable)
                }

                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { index, height in
                        VStack(spacing: 5) {
                            Capsule()
                                .fill(GallaxyBrand.pageBackground.opacity(0.76))
                                .frame(width: 5, height: 62)
                                .overlay(alignment: .bottom) {
                                    Capsule()
                                        .fill(GallaxyBrand.textMain.opacity(0.78))
                                        .frame(width: 5, height: 62 * height)
                                }
                            Text("\((index + 1) * 2)")
                                .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(GallaxyBrand.textMuted)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .overlay(GallaxyBrand.borderSubtle)

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(format: "SPEED %.2fx", viewModel.speed))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GallaxyBrand.textMain.opacity(0.78))
                    Text(lastConsoleLine)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(GallaxyBrand.textMuted)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
            }
            .padding(12)
        }
    }

    private var lastConsoleLine: String {
        viewModel.consoleLines.last ?? "> ready"
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

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = rect.minY + rect.height * verticalInsetFraction
        let bottom = rect.maxY - rect.height * verticalInsetFraction
        let innerX = rect.minX + rect.width * 0.03
        let outerX = rect.maxX - rect.width * 0.02
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

struct SpeakerCone: View {
    let size: CGFloat
    var level = 0.0

    private var pulse: CGFloat {
        CGFloat(min(1, max(0, level)))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            GallaxyBrand.textMain.opacity(0.58),
                            GallaxyBrand.textMain.opacity(0.18),
                            GallaxyBrand.pageBackground.opacity(0.82)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.55
                    )
                )
                .overlay(Circle().stroke(GallaxyBrand.textMain.opacity(0.34), lineWidth: 2))
                .scaleEffect(1 + pulse * 0.025)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            GallaxyBrand.textMain.opacity(0.92),
                            GallaxyBrand.textMain.opacity(0.34),
                            GallaxyBrand.brandGreen.opacity(0.38),
                            GallaxyBrand.pageBackground.opacity(0.92)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.36),
                        startRadius: 2,
                        endRadius: size * 0.38
                    )
                )
                .frame(width: size * 0.68, height: size * 0.68)
                .overlay(Circle().stroke(.black.opacity(0.38), lineWidth: 1.5))
                .scaleEffect(1 + pulse * 0.075)
                .brightness(Double(pulse) * 0.06)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            GallaxyBrand.textMain.opacity(0.92),
                            GallaxyBrand.textMain.opacity(0.28),
                            GallaxyBrand.pageBackground.opacity(0.74)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.32),
                        startRadius: 1,
                        endRadius: size * 0.18
                    )
                )
                .frame(width: size * 0.30, height: size * 0.30)
                .scaleEffect(1 + pulse * 0.16)
                .shadow(
                    color: GallaxyBrand.textMain.opacity(0.12 + Double(pulse) * 0.30),
                    radius: 1 + Double(pulse) * 4,
                    x: 0,
                    y: 0
                )

            Circle()
                .trim(from: 0.08, to: 0.42)
                .stroke(
                    GallaxyBrand.textMain.opacity(0.42 + Double(pulse) * 0.30),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: size * 0.80, height: size * 0.80)
                .rotationEffect(.degrees(-12))
                .scaleEffect(1 + pulse * 0.035)
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
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: index == 0 ? 10.0 : 10.5, weight: index == 0 ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(foregroundColor(for: index))
                        .lineLimit(index == lines.count - 1 ? 3 : 1)
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
        if index == 0 {
            return GallaxyBrand.brandMaroonReadable
        }
        if paused {
            return GallaxyBrand.textMuted
        }
        return active ? GallaxyBrand.textMain.opacity(0.86) : GallaxyBrand.textMuted
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
            .foregroundStyle(active ? GallaxyBrand.brandMaroonReadable : GallaxyBrand.textMain.opacity(0.88))
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [GallaxyBrand.pageBackground, GallaxyBrand.brandMaroon.opacity(0.42)]
                                : [GallaxyBrand.textMain.opacity(0.18), GallaxyBrand.pageBackground.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
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
            .foregroundStyle(active ? GallaxyBrand.brandMaroonReadable : GallaxyBrand.textMuted)
            .background(
                Circle()
                    .fill(
                        active
                            ? GallaxyBrand.textMain.opacity(configuration.isPressed ? 0.11 : 0.16)
                            : GallaxyBrand.pageBackground.opacity(configuration.isPressed ? 0.78 : 0.58)
                    )
            )
            .overlay(
                Circle()
                    .stroke(active ? GallaxyBrand.brandMaroonReadable.opacity(0.52) : GallaxyBrand.borderSubtle, lineWidth: 1)
            )
            .shadow(color: active ? GallaxyBrand.brandMaroonReadable.opacity(0.24) : .clear, radius: 4, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

struct RetroRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(GallaxyBrand.textMain.opacity(0.94))
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [GallaxyBrand.brandMaroon.opacity(0.84), GallaxyBrand.pageBackground.opacity(0.82)]
                                : [GallaxyBrand.brandMaroonReadable.opacity(0.88), GallaxyBrand.brandMaroon.opacity(0.74), GallaxyBrand.pageBackground.opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
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
