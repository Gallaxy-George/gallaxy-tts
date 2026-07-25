@preconcurrency import AVFoundation
import Foundation

final class AppleSpeechEngine: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    var speedMultiplier: Double = 1.15
    var finishHandler: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking && !synthesizer.isPaused
    }

    var isPaused: Bool {
        synthesizer.isPaused
    }

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speedMultiplier))
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    @discardableResult
    func pause() -> Bool {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return false }
        return synthesizer.pauseSpeaking(at: .immediate)
    }

    @discardableResult
    func resume() -> Bool {
        guard synthesizer.isPaused else { return false }
        return synthesizer.continueSpeaking()
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishHandler?()
    }
}
