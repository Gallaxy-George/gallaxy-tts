import AppKit
import ApplicationServices

@main
struct AppLaunchSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let router = SpeechRequestRouter.shared
        var captions = Set<String>()
        let started = Date()
        var spoke = false
        var captured = false
        var timer: Timer?
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if !spoke, Date().timeIntervalSince(started) > 1 {
                spoke = true
                router.speak("Read along, and follow the punctuation.", source: "launch-smoke")
            }
            if !router.currentCaption.isEmpty {
                captions.insert(router.currentCaption)
                if !captured, let view = app.windows.first(where: { $0.title == "Gallaxy TTS" })?.contentView,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathExtension("png"))
                    captured = true
                }
            }
            if (captions.count >= 2 && !router.isSpeaking) || router.lastError != nil || Date().timeIntervalSince(started) > 45 {
                let success = captions.count >= 2 && captured && router.lastError == nil
                let result = "\(success ? "PASS" : "FAIL"): app launch, Kokoro worker, audio playback, \(captions.count) caption phrases, completion. Accessibility trusted: \(AXIsProcessTrusted()). Error: \(router.lastError ?? "none")\n"
                try? result.write(to: output.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
                router.stop()
                timer?.invalidate()
                app.terminate(nil)
            }
        }
        app.run()
    }
}
