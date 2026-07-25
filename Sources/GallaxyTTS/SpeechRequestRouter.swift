import Foundation
import OSLog

private let speechLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.gallaxy.tts.local",
    category: "Speech"
)

final class SpeechRequestRouter {
    static let shared = SpeechRequestRouter()

    private let workQueue = DispatchQueue(label: "app.gallaxy.tts.speech", qos: .userInitiated)
    private let warmQueue = DispatchQueue(label: "app.gallaxy.tts.speech.warm", qos: .utility)
    private let normalizer = TextNormalizer()
    private let kokoro = KokoroEngine()
    private let apple = AppleSpeechEngine()
    private let elevenLabs = ElevenLabsEngine()
    private let defaults = UserDefaults.standard

    private var activeToken = UUID()
    private var isGeneratingSpeech = false
    private var keepWarmTimer: DispatchSourceTimer?
    private var isBackgroundWarmRunning = false
    var activityHandler: (() -> Void)?
    var levelHandler: ((Double) -> Void)?

    private init() {
        let savedSpeed = defaults.double(forKey: "speechSpeedMultiplier")
        speechSpeedMultiplier = savedSpeed > 0 ? savedSpeed : 1.15
        kokoro.finishHandler = { [weak self] in
            self?.speechDidFinish()
        }
        kokoro.startHandler = { [weak self] in
            self?.speechDidStart()
        }
        apple.finishHandler = { [weak self] in
            self?.speechDidFinish()
        }
        elevenLabs.finishHandler = { [weak self] in
            self?.speechDidFinish()
        }
        elevenLabs.startHandler = { [weak self] in
            self?.speechDidStart()
        }
        kokoro.levelHandler = { [weak self] level in
            self?.levelHandler?(level)
        }
        elevenLabs.levelHandler = { [weak self] level in
            self?.levelHandler?(level)
        }
    }

    var speechSpeedMultiplier: Double {
        get {
            kokoro.speedMultiplier
        }
        set {
            let clamped = max(0.75, min(newValue, 1.6))
            kokoro.speedMultiplier = clamped
            apple.speedMultiplier = clamped
            elevenLabs.speedMultiplier = clamped
            defaults.set(clamped, forKey: "speechSpeedMultiplier")
        }
    }

    func warmUp() {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.startKeepWarmTimer()
            self.scheduleBackgroundWarm(reason: "warmup") { kokoro in
                kokoro.warmUp()
            }
        }
    }

    func prepareAfterWake() {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.startKeepWarmTimer()
            self.scheduleBackgroundWarm(reason: "wake refresh") { kokoro in
                kokoro.prepareAfterWake()
            }
        }
    }

    func voiceProviderDidChange(to provider: VoiceProviderOption) {
        guard provider == .localKokoro else { return }

        workQueue.async { [weak self] in
            guard let self else { return }
            self.startKeepWarmTimer()
            self.scheduleBackgroundWarm(reason: "local voice selected") { kokoro in
                kokoro.warmUp()
            }
        }
    }

    func speak(_ rawText: String, source: String) {
        let requestStartedAt = Date()
        let token = UUID()
        activeToken = token
        isGeneratingSpeech = true

        stopPlayback()

        let text = normalizer.normalize(rawText)
        guard !text.isEmpty else {
            isGeneratingSpeech = false
            return
        }

        let selectedProvider = voiceProvider
        speechLogger.info("Speech request source=\(source, privacy: .public) provider=\(selectedProvider.rawValue, privacy: .public) chars=\(text.count, privacy: .public)")

        workQueue.async { [weak self] in
            guard let self else { return }
            switch selectedProvider {
            case .elevenLabs where self.elevenLabs.isConfigured:
                self.elevenLabs.speak(
                    text,
                    shouldPlay: { [weak self] in
                        self?.activeToken == token
                    }
                ) { result in
                    DispatchQueue.main.async {
                        guard self.activeToken == token else { return }
                        self.isGeneratingSpeech = false
                    }

                    if case .failure(let error) = result {
                        speechLogger.error("ElevenLabs failed source=\(source, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: requestStartedAt), privacy: .public) error=\(error.localizedDescription, privacy: .private)")
                        self.workQueue.async {
                            guard self.activeToken == token else { return }
                            self.speakLocal(text, source: source, token: token, requestStartedAt: requestStartedAt)
                        }
                    } else {
                        speechLogger.info("ElevenLabs request completed source=\(source, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: requestStartedAt), privacy: .public)")
                    }
                }
            default:
                self.speakLocal(text, source: source, token: token, requestStartedAt: requestStartedAt)
            }
        }
    }

    func stop() {
        activeToken = UUID()
        isGeneratingSpeech = false
        stopPlayback()
    }

    private func stopPlayback() {
        elevenLabs.stop()
        kokoro.stop()
        apple.stop()
        levelHandler?(0)
    }

    @discardableResult
    func pause() -> Bool {
        let didPauseElevenLabs = elevenLabs.pause()
        let didPauseKokoro = kokoro.pause()
        let didPauseApple = apple.pause()
        return didPauseElevenLabs || didPauseKokoro || didPauseApple
    }

    @discardableResult
    func resume() -> Bool {
        let didResumeElevenLabs = elevenLabs.resume()
        let didResumeKokoro = kokoro.resume()
        let didResumeApple = apple.resume()
        return didResumeElevenLabs || didResumeKokoro || didResumeApple
    }

    var isSpeaking: Bool {
        isGeneratingSpeech || elevenLabs.isSpeaking || kokoro.isSpeaking || apple.isSpeaking
    }

    var isPaused: Bool {
        elevenLabs.isPaused || kokoro.isPaused || apple.isPaused
    }

    var statusLine: String {
        "Ready"
    }

    private func speechDidFinish() {
        isGeneratingSpeech = false
        activityHandler?()
    }

    private func speechDidStart() {
        isGeneratingSpeech = false
        activityHandler?()
    }

    private var voiceProvider: VoiceProviderOption {
        guard let rawValue = defaults.string(forKey: "voiceProvider"),
              let provider = VoiceProviderOption(rawValue: rawValue) else {
            return .localKokoro
        }
        return VoiceProviderOption.savedValue(provider.rawValue)
    }

    private func startKeepWarmTimer() {
        guard keepWarmTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + .seconds(75), repeating: .seconds(120), leeway: .seconds(15))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.voiceProvider == .localKokoro else { return }
            guard !self.isGeneratingSpeech, !self.kokoro.isSpeaking, !self.kokoro.isPaused else { return }

            self.scheduleBackgroundWarm(reason: "keepalive") { kokoro in
                kokoro.keepWarm()
            }
        }
        keepWarmTimer = timer
        timer.resume()
    }

    private func scheduleBackgroundWarm(reason: String, action: @escaping (KokoroEngine) -> Void) {
        guard !isBackgroundWarmRunning else {
            speechLogger.info("Speech background \(reason, privacy: .public) skipped because another warm task is running")
            return
        }

        isBackgroundWarmRunning = true
        warmQueue.async { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            action(self.kokoro)
            speechLogger.info("Speech background \(reason, privacy: .public) finished elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)")
            self.workQueue.async { [weak self] in
                self?.isBackgroundWarmRunning = false
            }
        }
    }

    private func speakLocal(_ text: String, source: String, token: UUID, requestStartedAt: Date) {
        if kokoro.isReady {
            kokoro.speak(
                text,
                shouldPlay: { [weak self] in
                    self?.activeToken == token
                }
            ) { result in
                DispatchQueue.main.async {
                    guard self.activeToken == token else { return }
                    self.isGeneratingSpeech = false
                }

                if case .failure(let error) = result {
                    speechLogger.error("Kokoro failed source=\(source, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: requestStartedAt), privacy: .public) error=\(error.localizedDescription, privacy: .private)")
                    DispatchQueue.main.async {
                        guard self.activeToken == token else { return }
                        speechLogger.info("Kokoro unavailable; using Apple speech source=\(source, privacy: .public)")
                        self.apple.speak(text)
                    }
                } else {
                    speechLogger.info("Kokoro request completed source=\(source, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: requestStartedAt), privacy: .public)")
                }
            }
        } else {
            DispatchQueue.main.async {
                guard self.activeToken == token else { return }
                self.isGeneratingSpeech = false
                speechLogger.info("Kokoro unavailable; using Apple speech source=\(source, privacy: .public)")
                self.apple.speak(text)
            }
        }
    }
}

private func elapsedMilliseconds(since start: Date) -> Int {
    Int(Date().timeIntervalSince(start) * 1000)
}
