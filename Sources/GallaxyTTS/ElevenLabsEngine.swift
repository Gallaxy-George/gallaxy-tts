import Foundation
import OSLog

private let elevenLabsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.gallaxy.tts.local",
    category: "ElevenLabs"
)

enum ElevenLabsSpeechError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidPayload
    case missingAudio
    case requestFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "ElevenLabs API key is missing."
        case .invalidEndpoint:
            return "ElevenLabs endpoint could not be built."
        case .invalidPayload:
            return "ElevenLabs request payload could not be encoded."
        case .missingAudio:
            return "ElevenLabs did not return playable audio."
        case .requestFailed(let message):
            return message
        case .cancelled:
            return "ElevenLabs playback was cancelled."
        }
    }
}

final class ElevenLabsEngine {
    private let playback = PlaybackController()
    private let defaults = UserDefaults.standard
    private var activeTask: URLSessionDataTask?
    var speedMultiplier: Double = 1.15 {
        didSet {
            let rate = speedMultiplier
            performPlaybackMutation { $0.setRate(rate) }
        }
    }

    var finishHandler: (() -> Void)? {
        didSet {
            playback.finishHandler = finishHandler
        }
    }

    var startHandler: (() -> Void)? {
        didSet {
            playback.startHandler = startHandler
        }
    }

    var levelHandler: ((Double) -> Void)? {
        didSet {
            playback.levelHandler = levelHandler
        }
    }

    var isConfigured: Bool {
        ElevenLabsCredentialStore.hasAPIKey()
    }

    var isSpeaking: Bool {
        performPlaybackRead { $0.isPlaying || $0.hasQueuedAudio }
    }

    var isPaused: Bool {
        performPlaybackRead { $0.isPaused }
    }

    func speak(_ text: String, shouldPlay: @escaping () -> Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let apiKey = ElevenLabsCredentialStore.apiKey(), apiKey.isEmpty == false else {
            completion(.failure(ElevenLabsSpeechError.missingAPIKey))
            return
        }

        let voiceID = defaults.string(forKey: "elevenLabsVoiceID") ?? "JBFqnCBsd6RMkjVDRZzb"
        let modelID = defaults.string(forKey: "elevenLabsModelID") ?? "eleven_flash_v2_5"
        let chunks = speechChunks(from: text)
        guard !chunks.isEmpty else {
            completion(.success(()))
            return
        }

        guard let url = streamURL(voiceID: voiceID) else {
            completion(.failure(ElevenLabsSpeechError.invalidEndpoint))
            return
        }

        let requestStartedAt = Date()
        stopActiveRequest()
        elevenLabsLogger.info("ElevenLabs request started chunks=\(chunks.count, privacy: .public) chars=\(text.count, privacy: .public) model=\(modelID, privacy: .public)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.playback.beginQueue()
            self.requestChunk(
                index: 0,
                chunks: chunks,
                url: url,
                apiKey: apiKey,
                modelID: modelID,
                requestStartedAt: requestStartedAt,
                didEnqueueAudio: false,
                shouldPlay: shouldPlay,
                completion: completion
            )
        }
    }

    private func streamURL(voiceID: String) -> URL? {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream")
        components?.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        return components?.url
    }

    private func requestChunk(
        index: Int,
        chunks: [String],
        url: URL,
        apiKey: String,
        modelID: String,
        requestStartedAt: Date,
        didEnqueueAudio: Bool,
        shouldPlay: @escaping () -> Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard shouldPlay() else {
            playback.stop()
            completion(.failure(ElevenLabsSpeechError.cancelled))
            return
        }

        guard index < chunks.count else {
            activeTask = nil
            playback.endQueue()
            elevenLabsLogger.info("ElevenLabs all chunks queued elapsedMs=\(elapsedMilliseconds(since: requestStartedAt), privacy: .public)")
            completion(.success(()))
            return
        }

        let chunk = chunks[index]
        let chunkStartedAt = Date()

        let payload: [String: Any] = [
            "text": chunk,
            "model_id": modelID,
            "voice_settings": [
                "stability": 0.42,
                "similarity_boost": 0.78,
                "style": 0.18,
                "use_speaker_boost": true
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            completion(.failure(ElevenLabsSpeechError.invalidPayload))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.finishAfterChunkError(
                    error,
                    didEnqueueAudio: didEnqueueAudio,
                    completion: completion
                )
                return
            }

            guard shouldPlay() else {
                completion(.failure(ElevenLabsSpeechError.cancelled))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                let bodyMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                self.finishAfterChunkError(
                    ElevenLabsSpeechError.requestFailed(bodyMessage),
                    didEnqueueAudio: didEnqueueAudio,
                    completion: completion
                )
                return
            }

            guard let data, data.isEmpty == false else {
                self.finishAfterChunkError(
                    ElevenLabsSpeechError.missingAudio,
                    didEnqueueAudio: didEnqueueAudio,
                    completion: completion
                )
                return
            }

            do {
                let fileURL = try self.writeAudioFile(data)
                DispatchQueue.main.async {
                    guard shouldPlay() else {
                        try? FileManager.default.removeItem(at: fileURL)
                        completion(.failure(ElevenLabsSpeechError.cancelled))
                        return
                    }

                    do {
                        try self.playback.enqueueFile(fileURL)
                        elevenLabsLogger.info("ElevenLabs chunk queued index=\(index + 1, privacy: .public) total=\(chunks.count, privacy: .public) chars=\(chunk.count, privacy: .public) bytes=\(data.count, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: chunkStartedAt), privacy: .public)")
                        self.requestChunk(
                            index: index + 1,
                            chunks: chunks,
                            url: url,
                            apiKey: apiKey,
                            modelID: modelID,
                            requestStartedAt: requestStartedAt,
                            didEnqueueAudio: true,
                            shouldPlay: shouldPlay,
                            completion: completion
                        )
                    } catch {
                        try? FileManager.default.removeItem(at: fileURL)
                        self.finishAfterChunkError(
                            error,
                            didEnqueueAudio: didEnqueueAudio,
                            completion: completion
                        )
                    }
                }
            } catch {
                self.finishAfterChunkError(
                    error,
                    didEnqueueAudio: didEnqueueAudio,
                    completion: completion
                )
            }
        }

        activeTask = task
        task.resume()
    }

    private func finishAfterChunkError(
        _ error: Error,
        didEnqueueAudio: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        elevenLabsLogger.error("ElevenLabs chunk failed afterAudio=\(didEnqueueAudio, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeTask = nil
            if didEnqueueAudio {
                self.playback.endQueue()
                completion(.success(()))
            } else {
                self.playback.stop()
                completion(.failure(error))
            }
        }
    }

    private func speechChunks(from text: String) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let maxCharacters = 520
        var chunks: [String] = []
        var current = ""

        for word in words {
            if current.isEmpty {
                current = word
                continue
            }

            if current.count + word.count + 1 > maxCharacters {
                chunks.append(current)
                current = word
            } else {
                current += " " + word
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    func stop() {
        stopActiveRequest()
        performPlaybackMutation { $0.stop() }
    }

    @discardableResult
    func pause() -> Bool {
        performPlaybackRead { $0.pause() }
    }

    @discardableResult
    func resume() -> Bool {
        performPlaybackRead { $0.resume() }
    }

    private func writeAudioFile(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Gallaxy TTS", isDirectory: true)
            .appendingPathComponent("ElevenLabs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp3")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func stopActiveRequest() {
        activeTask?.cancel()
        activeTask = nil
    }

    private func performPlaybackMutation(_ block: @escaping (PlaybackController) -> Void) {
        if Thread.isMainThread {
            block(playback)
        } else {
            DispatchQueue.main.async { [playback] in
                block(playback)
            }
        }
    }

    private func performPlaybackRead<T>(_ block: @escaping (PlaybackController) -> T) -> T {
        if Thread.isMainThread {
            return block(playback)
        }

        return DispatchQueue.main.sync {
            block(playback)
        }
    }
}

private func elapsedMilliseconds(since start: Date) -> Int {
    Int(Date().timeIntervalSince(start) * 1000)
}
