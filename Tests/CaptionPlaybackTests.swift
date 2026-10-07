import AVFoundation
import Foundation

@main
struct CaptionPlaybackTests {
    static func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    static func wave() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caption-test-\(UUID()).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = 48000
        memset(buffer.floatChannelData![0], 0, 48000 * MemoryLayout<Float>.size)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
    static func main() throws {
        let controller = PlaybackController()
        var caption = ""
        var finished = false
        controller.captionHandler = { caption = $0 }
        controller.finishHandler = { finished = true }
        let cues = [SpeechCaption(text: "First,", start: 0), SpeechCaption(text: "second!", start: 0.6)]
        let first = try wave()
        controller.setRate(1)
        try controller.playFile(first, captions: cues)
        wait(0.2)
        precondition(caption == "First,")
        precondition(controller.pause())
        wait(0.7)
        precondition(caption == "First,", "Paused caption advanced")
        controller.setRate(2)
        precondition(controller.resume())
        wait(0.35)
        precondition(caption == "second!", "Rate change lost synchronization")
        let replacement = try wave()
        try controller.playFile(replacement, captions: [SpeechCaption(text: "New request.", start: 0)])
        precondition(caption == "New request.")
        precondition(!FileManager.default.fileExists(atPath: first.path))
        controller.stop()
        precondition(caption.isEmpty && !controller.hasQueuedAudio)
        precondition(!FileManager.default.fileExists(atPath: replacement.path))
        controller.beginQueue()
        try controller.enqueueFile(wave(), captions: cues)
        try controller.enqueueFile(wave(), captions: [SpeechCaption(text: "Queued.", start: 0)])
        controller.endQueue()
        wait(1.2)
        precondition(caption == "Queued.")
        wait(1.2)
        precondition(caption.isEmpty && finished)
        let phrases = SpeechCaption.phrases(in: "“Wait,” she said. Don't lose punctuation!")
        precondition(phrases.map(\.text).joined(separator: " ") == "“Wait,” she said. Don't lose punctuation!")
        print("PASS: playback clock, pause/resume, rate, replacement, stop, queue, completion, punctuation")
    }
}
