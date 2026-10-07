import Foundation

private final class FakeEngine: SpeechEngine {
    var speedMultiplier = 1.0
    var finishHandler: (() -> Void)?
    var startHandler: (() -> Void)?
    var captionHandler: ((String) -> Void)?
    var levelHandler: ((Double) -> Void)?
    var isReady = true
    var isSpeaking = false
    var isPaused = false
    struct Request {
        let text: String
        let shouldPlay: () -> Bool
        let completion: (Result<Void, Error>) -> Void
    }
    private let lock = NSLock()
    private var requests: [Request] = []
    func request(_ index: Int) -> Request? {
        lock.lock(); defer { lock.unlock() }
        return requests.indices.contains(index) ? requests[index] : nil
    }
    func speak(_ text: String, shouldPlay: @escaping () -> Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock(); defer { lock.unlock() }
        requests.append(Request(text: text, shouldPlay: shouldPlay, completion: completion))
    }
    func stop() { isSpeaking = false; isPaused = false; captionHandler?("") }
    func pause() -> Bool { guard isSpeaking else { return false }; isPaused = true; return true }
    func resume() -> Bool { guard isPaused else { return false }; isPaused = false; return true }
    func warmUp() {}
    func keepWarm() {}
    func prepareAfterWake() {}
}

@main
struct AppBehaviorTests {
    static func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(condition(), "Timed out waiting for state")
    }
    static func main() {
        var trusted = true
        var prompts = 0
        let permission = AccessibilityPermission(isTrusted: { trusted }, requestAccess: { prompts += 1; return false })
        precondition(prompts == 0, "Construction must not prompt")
        precondition(permission.checkForSelection() && prompts == 0, "Trusted users must not be prompted")
        trusted = false
        precondition(!permission.checkForSelection() && prompts == 1)
        precondition(!permission.checkForSelection() && prompts == 1, "Repeated actions must not spam prompts")
        trusted = true
        precondition(permission.checkForSelection() && prompts == 1, "Granting access must take effect without relaunch")

        let suite = "app.gallaxy.tts.test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("elevenLabs", forKey: "voiceProvider")
        defaults.set(1.4, forKey: "speechSpeedMultiplier")
        let engine = FakeEngine()
        let router = SpeechRequestRouter(engine: engine, defaults: defaults)
        precondition(router.speechSpeedMultiplier == 1.4)
        router.speak(" First. ", source: "test")
        waitUntil { engine.request(0) != nil }
        let first = engine.request(0)!
        precondition(first.text == "First." && first.shouldPlay())
        router.speak("Second.", source: "test")
        waitUntil { engine.request(1) != nil }
        let second = engine.request(1)!
        precondition(!first.shouldPlay() && second.shouldPlay())
        first.completion(.failure(NSError(domain: "test", code: 1)))
        engine.isSpeaking = true
        engine.startHandler?()
        engine.captionHandler?("Second.")
        precondition(router.pause() && router.isPaused && !router.isSpeaking)
        precondition(router.currentCaption == "Second.")
        precondition(router.resume() && router.isSpeaking)
        router.speechSpeedMultiplier = 99
        precondition(engine.speedMultiplier == 1.6)
        second.completion(.failure(NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Runtime unavailable"])))
        waitUntil { router.lastError != nil }
        precondition(router.lastError == "Runtime unavailable" && !router.isSpeaking && router.currentCaption.isEmpty)
        router.speak("Third.", source: "test")
        waitUntil { engine.request(2) != nil }
        precondition(router.lastError == nil)
        router.stop()
        precondition(!engine.request(2)!.shouldPlay() && !router.isSpeaking && router.currentCaption.isEmpty)
        engine.request(2)!.completion(.success(()))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(router.statusLine == "Ready")
        print("PASS: silent permission initialization, trusted/untrusted/granted states, Kokoro-only routing, cancellation, pause/resume, speed, errors, stop")
    }
}
