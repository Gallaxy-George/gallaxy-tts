@preconcurrency import AVFoundation
import Foundation

final class AppleSpeechEngine: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    var speedMultiplier: Double = 1.15
    private var activeUtterance: AVSpeechUtterance?
    private var phrases: [(text: String, range: NSRange)] = []
    var captionHandler: ((String) -> Void)?
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
        activeUtterance = utterance
        phrases = SpeechCaption.phrases(in: text)
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
        activeUtterance = nil
        phrases = []
        captionHandler?("")
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        captionHandler?(phrases.first(where: { NSIntersectionRange($0.range, range).length > 0 })?.text ?? "")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        captionHandler?("")
        finishHandler?()
    }
}
