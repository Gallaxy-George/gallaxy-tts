import Foundation

final class SpeechRequestRouter {
    static let shared = SpeechRequestRouter()

    private let workQueue = DispatchQueue(label: "app.gallaxy.tts.speech", qos: .userInitiated)
    private let normalizer = TextNormalizer()
    private let piper = PiperEngine()
    private let apple = AppleSpeechEngine()
    private let elevenLabs = ElevenLabsEngine()
    private let defaults = UserDefaults.standard

    private var activeToken = UUID()
    private var isGeneratingSpeech = false
    var activityHandler: (() -> Void)?
    var levelHandler: ((Double) -> Void)?

    private init() {
        let savedSpeed = defaults.double(forKey: "speechSpeedMultiplier")
        speechSpeedMultiplier = savedSpeed > 0 ? savedSpeed : 1.15
        piper.finishHandler = { [weak self] in
            self?.speechDidFinish()
        }
        apple.finishHandler = { [weak self] in
            self?.speechDidFinish()
        }
        elevenLabs.finishHandler = { [weak self] in
            self?.speechDidFinish()
        }
        piper.levelHandler = { [weak self] level in
            self?.levelHandler?(level)
        }
        elevenLabs.levelHandler = { [weak self] level in
            self?.levelHandler?(level)
        }
    }

    var speechSpeedMultiplier: Double {
        get {
            piper.speedMultiplier
        }
        set {
            let clamped = max(0.75, min(newValue, 1.6))
            piper.speedMultiplier = clamped
            apple.speedMultiplier = clamped
            defaults.set(clamped, forKey: "speechSpeedMultiplier")
        }
    }

    func warmUp() {
        workQueue.async { [piper] in
            piper.warmUp()
        }
    }

    func speak(_ rawText: String, source: String) {
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
                        NSLog("Gallaxy TTS ElevenLabs failed from \(source): \(error.localizedDescription)")
                        self.workQueue.async {
                            guard self.activeToken == token else { return }
                            self.speakLocal(text, source: source, token: token)
                        }
                    }
                }
            default:
                self.speakLocal(text, source: source, token: token)
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
        piper.stop()
        apple.stop()
        levelHandler?(0)
    }

    @discardableResult
    func pause() -> Bool {
        let didPauseElevenLabs = elevenLabs.pause()
        let didPausePiper = piper.pause()
        let didPauseApple = apple.pause()
        return didPauseElevenLabs || didPausePiper || didPauseApple
    }

    @discardableResult
    func resume() -> Bool {
        let didResumeElevenLabs = elevenLabs.resume()
        let didResumePiper = piper.resume()
        let didResumeApple = apple.resume()
        return didResumeElevenLabs || didResumePiper || didResumeApple
    }

    var isSpeaking: Bool {
        isGeneratingSpeech || elevenLabs.isSpeaking || piper.isSpeaking || apple.isSpeaking
    }

    var isPaused: Bool {
        elevenLabs.isPaused || piper.isPaused || apple.isPaused
    }

    var statusLine: String {
        "Ready"
    }

    private func speechDidFinish() {
        isGeneratingSpeech = false
        activityHandler?()
    }

    private var voiceProvider: VoiceProviderOption {
        guard let rawValue = defaults.string(forKey: "voiceProvider"),
              let provider = VoiceProviderOption(rawValue: rawValue) else {
            return .localPiper
        }
        return provider
    }

    private func speakLocal(_ text: String, source: String, token: UUID) {
        if piper.isReady {
            piper.speak(
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
                    NSLog("Gallaxy TTS Piper failed from \(source): \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        guard self.activeToken == token else { return }
                        self.apple.speak(text)
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                guard self.activeToken == token else { return }
                self.isGeneratingSpeech = false
                self.apple.speak(text)
            }
        }
    }
}
