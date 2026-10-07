import Foundation

/// The router owns request state; the local engine owns synthesis and playback.
protocol SpeechEngine: AnyObject {
    var speedMultiplier: Double { get set }
    var finishHandler: (() -> Void)? { get set }
    var startHandler: (() -> Void)? { get set }
    var captionHandler: ((String) -> Void)? { get set }
    var levelHandler: ((Double) -> Void)? { get set }
    var isReady: Bool { get }
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    func speak(_ text: String, shouldPlay: @escaping () -> Bool, completion: @escaping (Result<Void, Error>) -> Void)
    func stop()
    func pause() -> Bool
    func resume() -> Bool
    func warmUp()
    func keepWarm()
    func prepareAfterWake()
}

extension KokoroEngine: SpeechEngine {}

/// Synthesis runs off the main thread. Its cancellation check must not race UI
/// actions (stop or replacement) while a WAV is being generated.
final class SpeechRequestIdentity {
    private let lock = NSLock()
    private var value = UUID()

    func replace() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        value = UUID()
        return value
    }

    func matches(_ token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == token
    }
}
