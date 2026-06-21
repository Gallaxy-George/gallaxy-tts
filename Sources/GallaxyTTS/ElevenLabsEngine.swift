import Foundation

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

    var finishHandler: (() -> Void)? {
        didSet {
            playback.finishHandler = finishHandler
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
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")
        components?.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        guard let url = components?.url else {
            completion(.failure(ElevenLabsSpeechError.invalidEndpoint))
            return
        }

        let payload: [String: Any] = [
            "text": text,
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

        stopActiveRequest()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            guard shouldPlay() else {
                completion(.failure(ElevenLabsSpeechError.cancelled))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                let bodyMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                completion(.failure(ElevenLabsSpeechError.requestFailed(bodyMessage)))
                return
            }

            guard let data, data.isEmpty == false else {
                completion(.failure(ElevenLabsSpeechError.missingAudio))
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
                        try self.playback.playFile(fileURL)
                        completion(.success(()))
                    } catch {
                        try? FileManager.default.removeItem(at: fileURL)
                        completion(.failure(error))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }

        activeTask = task
        task.resume()
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
