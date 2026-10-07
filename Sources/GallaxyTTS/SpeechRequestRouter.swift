import Foundation
import OSLog

private let speechLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.gallaxy.tts.local",
    category: "Speech"
)

/// UI-facing state is read and updated on the main thread. Only synthesis and
/// warmup run in the background; request identity is explicitly synchronized.
final class SpeechRequestRouter {
    static let shared = SpeechRequestRouter()

    private let workQueue = DispatchQueue(label: "app.gallaxy.tts.speech", qos: .userInitiated)
    private let warmQueue = DispatchQueue(label: "app.gallaxy.tts.speech.warm", qos: .utility)
    private let normalizer = TextNormalizer()
    private let engine: SpeechEngine
    private let defaults: UserDefaults
    private let requestIdentity = SpeechRequestIdentity()
    private var isGeneratingSpeech = false
    private var keepWarmTimer: Timer?
    private var isBackgroundWarmRunning = false
    private(set) var lastError: String?
    private(set) var currentCaption = ""
    var activityHandler: (() -> Void)?
    var captionHandler: ((String) -> Void)?
    var levelHandler: ((Double) -> Void)?

    init(engine: SpeechEngine = KokoroEngine(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        // Persisted cloud selections from older builds are deliberately ignored.
        let savedSpeed = defaults.double(forKey: "speechSpeedMultiplier")
        speechSpeedMultiplier = savedSpeed > 0 ? savedSpeed : 1.15
        engine.captionHandler = { [weak self] caption in
            self?.currentCaption = caption
            self?.captionHandler?(caption)
        }
        engine.levelHandler = { [weak self] level in self?.levelHandler?(level) }
        engine.startHandler = { [weak self] in self?.playbackChanged() }
        engine.finishHandler = { [weak self] in self?.playbackChanged() }
    }

    deinit { keepWarmTimer?.invalidate() }

    var speechSpeedMultiplier: Double {
        get { engine.speedMultiplier }
        set {
            let clamped = max(0.75, min(newValue, 1.6))
            engine.speedMultiplier = clamped
            defaults.set(clamped, forKey: "speechSpeedMultiplier")
        }
    }

    var isSpeaking: Bool { isGeneratingSpeech || (engine.isSpeaking && !engine.isPaused) }
    var isPaused: Bool { engine.isPaused }
    var statusLine: String {
        if lastError != nil { return "Kokoro unavailable" }
        if isPaused { return "Paused" }
        if isGeneratingSpeech { return "Preparing voice" }
        return engine.isSpeaking ? "Speaking" : "Ready"
    }

    func speak(_ rawText: String, source: String) {
        let token = requestIdentity.replace()
        engine.stop()
        lastError = nil
        let text = normalizer.normalize(rawText)
        isGeneratingSpeech = !text.isEmpty
        activityHandler?()
        guard !text.isEmpty else { return }
        speechLogger.info("Speech request source=\(source, privacy: .public) provider=kokoro chars=\(text.count, privacy: .public)")

        workQueue.async { [weak self] in
            guard let self, self.requestIdentity.matches(token) else { return }
            self.engine.speak(text, shouldPlay: { [weak self] in
                self?.requestIdentity.matches(token) == true
            }) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.requestIdentity.matches(token) else { return }
                    self.isGeneratingSpeech = false
                    if case .failure(let error) = result {
                        self.engine.stop()
                        // Keep actionable runtime details visible in the existing console.
                        self.lastError = error.localizedDescription
                        speechLogger.error("Kokoro failed error=\(error.localizedDescription, privacy: .private)")
                    }
                    self.activityHandler?()
                }
            }
        }
    }

    func stop() {
        _ = requestIdentity.replace()
        isGeneratingSpeech = false
        lastError = nil
        engine.stop()
        currentCaption = ""
        captionHandler?("")
        levelHandler?(0)
        activityHandler?()
    }

    @discardableResult func pause() -> Bool {
        let paused = engine.pause()
        if paused { activityHandler?() }
        return paused
    }

    @discardableResult func resume() -> Bool {
        let resumed = engine.resume()
        if resumed { activityHandler?() }
        return resumed
    }

    func warmUp() {
        startKeepWarmTimer()
        scheduleBackgroundWarm { $0.warmUp() }
    }

    func prepareAfterWake() {
        startKeepWarmTimer()
        scheduleBackgroundWarm { $0.prepareAfterWake() }
    }

    private func playbackChanged() {
        isGeneratingSpeech = false
        activityHandler?()
    }

    private func startKeepWarmTimer() {
        guard keepWarmTimer == nil else { return }
        let timer = Timer(fire: Date().addingTimeInterval(75), interval: 120, repeats: true) { [weak self] _ in
            guard let self, !self.isSpeaking, !self.isPaused else { return }
            self.scheduleBackgroundWarm { $0.keepWarm() }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        keepWarmTimer = timer
    }

    private func scheduleBackgroundWarm(_ action: @escaping (SpeechEngine) -> Void) {
        guard !isBackgroundWarmRunning else { return }
        isBackgroundWarmRunning = true
        warmQueue.async { [weak self] in
            guard let self else { return }
            action(self.engine)
            DispatchQueue.main.async { [weak self] in self?.isBackgroundWarmRunning = false }
        }
    }
}
