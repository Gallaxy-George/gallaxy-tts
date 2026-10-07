import AVFoundation
import Foundation

final class PlaybackController: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var activeFileURL: URL?
    private struct QueuedAudio {
        let url: URL
        let captions: [SpeechCaption]
        let text: String
    }
    private var queuedFileURLs: [QueuedAudio] = []
    private var captions: [SpeechCaption] = []
    private var lastCaption = ""
    var captionHandler: ((String) -> Void)?
    private var queueIsOpen = false
    private var meterTimer: Timer?
    private var previousMeterLevel = 0.0
    private var playbackRate: Float = 1.15
    var startHandler: (() -> Void)?
    var finishHandler: (() -> Void)?
    var levelHandler: ((Double) -> Void)?

    var isPlaying: Bool {
        player?.isPlaying == true
    }

    var hasQueuedAudio: Bool {
        player != nil || !queuedFileURLs.isEmpty || queueIsOpen
    }

    var isPaused: Bool {
        guard let player else { return false }
        return !player.isPlaying
    }

    func playFile(_ url: URL, captions: [SpeechCaption] = [], text: String = "") throws {
        stop()
        try startFile(QueuedAudio(url: url, captions: captions, text: text))
    }

    func beginQueue() {
        stop()
        queueIsOpen = true
    }

    func enqueueFile(_ url: URL, captions: [SpeechCaption] = [], text: String = "") throws {
        let item = QueuedAudio(url: url, captions: captions, text: text)
        if player == nil {
            try startFile(item)
        } else {
            queuedFileURLs.append(item)
        }
    }

    func endQueue() {
        queueIsOpen = false
        finishIfIdle()
    }

    private func startFile(_ item: QueuedAudio) throws {
        let url = item.url
        let nextPlayer = try AVAudioPlayer(contentsOf: url)
        nextPlayer.delegate = self
        nextPlayer.isMeteringEnabled = true
        nextPlayer.enableRate = true
        nextPlayer.rate = playbackRate
        nextPlayer.prepareToPlay()
        captions = item.captions.isEmpty
            ? SpeechCaption.estimated(text: item.text, duration: nextPlayer.duration)
            : item.captions
        player = nextPlayer
        activeFileURL = url
        guard nextPlayer.play() else {
            player = nil
            clearCaption()
            removeActiveFile()
            throw NSError(domain: "GallaxyPlayback", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio playback could not start."])
        }
        startHandler?()
        startMetering()
    }

    @discardableResult
    func pause() -> Bool {
        guard let player, player.isPlaying else { return false }
        player.pause()
        stopMetering(publishSilence: true)
        return true
    }

    @discardableResult
    func resume() -> Bool {
        guard let player, !player.isPlaying else { return false }
        let resumed = player.play()
        if resumed {
            startMetering()
        }
        return resumed
    }

    func stop() {
        player?.stop()
        player = nil
        stopMetering(publishSilence: true)
        queueIsOpen = false
        clearCaption()
        removeActiveFile()
        removeQueuedFiles()
    }

    func setRate(_ multiplier: Double) {
        let clampedRate = Float(max(0.5, min(multiplier, 2.0)))
        playbackRate = clampedRate
        guard let player else { return }
        player.enableRate = true
        player.rate = clampedRate
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        self.player = nil
        clearCaption()
        stopMetering(publishSilence: true)
        removeActiveFile()
        while !queuedFileURLs.isEmpty {
            let next = queuedFileURLs.removeFirst()
            do {
                try startFile(next)
                return
            } catch {
                try? FileManager.default.removeItem(at: next.url)
            }
        }
        finishIfIdle()
    }

    private func removeActiveFile() {
        guard let activeFileURL else { return }
        try? FileManager.default.removeItem(at: activeFileURL)
        self.activeFileURL = nil
    }

    private func removeQueuedFiles() {
        for fileURL in queuedFileURLs {
            try? FileManager.default.removeItem(at: fileURL.url)
        }
        queuedFileURLs.removeAll()
    }

    private func finishIfIdle() {
        guard player == nil, queuedFileURLs.isEmpty, !queueIsOpen else { return }
        stopMetering(publishSilence: true)
        finishHandler?()
    }

    private func startMetering() {
        stopMetering(publishSilence: false)
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.publishAudioLevel()
        }
        meterTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        publishAudioLevel()
    }

    private func stopMetering(publishSilence: Bool) {
        meterTimer?.invalidate()
        meterTimer = nil
        if publishSilence {
            previousMeterLevel = 0
            levelHandler?(0)
        }
    }

    private func publishAudioLevel() {
        guard let player, player.isPlaying else {
            levelHandler?(0)
            return
        }

        let caption = captions.last(where: { $0.start <= player.currentTime })?.text ?? ""
        if caption != lastCaption {
            lastCaption = caption
            captionHandler?(caption)
        }
        player.updateMeters()
        let channels = max(1, player.numberOfChannels)
        let averagePower = (0..<channels)
            .map { player.averagePower(forChannel: $0) }
            .reduce(Float(0), +) / Float(channels)
        let peakPower = (0..<channels)
            .map { player.peakPower(forChannel: $0) }
            .reduce(Float(0), +) / Float(channels)
        let averageLevel = normalizedMeterLevel(from: averagePower)
        let peakLevel = normalizedMeterLevel(from: peakPower)
        let transient = max(0, peakLevel - averageLevel)
        let rawLevel = min(1, averageLevel * 0.42 + peakLevel * 0.48 + transient * 0.42)
        let level = rawLevel > previousMeterLevel
            ? rawLevel
            : (previousMeterLevel * 0.24 + rawLevel * 0.76)
        previousMeterLevel = level
        levelHandler?(level)
    }

    private func clearCaption() {
        captions = []
        lastCaption = ""
        captionHandler?("")
    }

    private func normalizedMeterLevel(from decibels: Float) -> Double {
        let clampedPower = max(-58, min(0, decibels))
        let normalized = Double((clampedPower + 58) / 58)
        return pow(min(1, max(0, normalized)), 1.65)
    }
}
