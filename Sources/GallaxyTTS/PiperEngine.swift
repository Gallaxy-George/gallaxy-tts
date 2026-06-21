import AVFoundation
import Foundation

final class PiperEngine {
    private let playback = PlaybackController()
    private let fileManager = FileManager.default
    private var workerProcess: Process?
    private var workerInput: FileHandle?
    private var workerOutput: FileHandle?
    var speedMultiplier: Double = 1.15
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

    var isReady: Bool {
        piperInvocation != nil && modelURL != nil && configURL != nil
    }

    var isSpeaking: Bool {
        performPlaybackRead { $0.isPlaying || $0.hasQueuedAudio }
    }

    var isPaused: Bool {
        performPlaybackRead { $0.isPaused }
    }

    func warmUp() {
        do {
            try ensureWorkerStarted()
            NSLog("Gallaxy TTS Piper worker is warm.")
        } catch {
            NSLog("Gallaxy TTS Piper worker warmup failed: \(error.localizedDescription)")
        }
    }

    func speak(
        _ text: String,
        shouldPlay: @escaping () -> Bool = { true },
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let piperInvocation, let modelURL, let configURL else {
            completion(.failure(PiperError.assetsMissing))
            return
        }

        if piperWorkerInvocation != nil {
            do {
                try speakChunksWithWorker(text: text, shouldPlay: shouldPlay, completion: completion)
                return
            } catch {
                NSLog("Gallaxy TTS Piper chunked worker path failed, falling back to one-shot helper: \(error.localizedDescription)")
            }
        }

        do {
            let outputURL = try temporaryWavURL()

            let process = Process()
            process.executableURL = piperInvocation.executableURL
            let arguments = piperInvocation.leadingArguments + [
                "--model", modelURL.path,
                "--config", configURL.path,
                "--output_file", outputURL.path,
                "--length_scale", String(format: "%.3f", lengthScale)
            ]
            process.arguments = arguments
            process.environment = piperInvocation.environment

            let input = Pipe()
            let errorPipe = Pipe()
            process.standardInput = input
            process.standardError = errorPipe

            try process.run()

            if let data = text.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
                input.fileHandleForWriting.write(Data([10]))
            }
            input.fileHandleForWriting.closeFile()

            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: errorData, encoding: .utf8) ?? "Piper exited with status \(process.terminationStatus)."
                completion(.failure(PiperError.processFailed(message)))
                return
            }

            do {
                if try playSingleFile(outputURL, shouldPlay: shouldPlay) {
                    completion(.success(()))
                } else {
                    completion(.success(()))
                }
            } catch {
                completion(.failure(error))
            }
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        DispatchQueue.main.async { [playback] in
            playback.stop()
        }
    }

    @discardableResult
    func pause() -> Bool {
        performPlaybackMutation { $0.pause() }
    }

    @discardableResult
    func resume() -> Bool {
        performPlaybackMutation { $0.resume() }
    }

    deinit {
        workerProcess?.terminate()
    }

    private func performPlaybackRead(_ read: @escaping (PlaybackController) -> Bool) -> Bool {
        if Thread.isMainThread {
            return read(playback)
        }

        var result = false
        DispatchQueue.main.sync { [playback] in
            result = read(playback)
        }
        return result
    }

    private func performPlaybackMutation(_ mutation: @escaping (PlaybackController) -> Bool) -> Bool {
        if Thread.isMainThread {
            return mutation(playback)
        }

        var result = false
        DispatchQueue.main.sync { [playback] in
            result = mutation(playback)
        }
        return result
    }

    private func performPlaybackMutationThrowing(_ mutation: @escaping (PlaybackController) throws -> Void) throws {
        if Thread.isMainThread {
            try mutation(playback)
            return
        }

        var result: Result<Void, Error> = .success(())
        DispatchQueue.main.sync { [playback] in
            do {
                try mutation(playback)
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }
        try result.get()
    }

    private var piperInvocation: PiperInvocation? {
        if let venvPython = existingExecutableResource("PiperRuntime/venv/bin/python"),
           let helper = existingResource("piper_synth.py") {
            return PiperInvocation(
                executableURL: venvPython,
                leadingArguments: [helper.path],
                environment: [
                    "PATH": "\(venvPython.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
                    "PYTHONNOUSERSITE": "1"
                ]
            )
        }

        let bundleCandidates = [
            "PiperRuntime/piper/piper",
            "PiperRuntime/piper",
            "piper/piper",
            "piper"
        ]

        for relativePath in bundleCandidates {
            if let url = existingExecutableResource(relativePath) {
                return PiperInvocation(executableURL: url, leadingArguments: [], environment: nil)
            }
        }

        let pathCandidates = [
            "/opt/homebrew/bin/piper",
            "/usr/local/bin/piper",
            "\(NSHomeDirectory())/.local/bin/piper"
        ]

        for path in pathCandidates where fileManager.isExecutableFile(atPath: path) {
            return PiperInvocation(executableURL: URL(fileURLWithPath: path), leadingArguments: [], environment: nil)
        }

        return nil
    }

    private var piperWorkerInvocation: PiperInvocation? {
        guard let venvPython = existingExecutableResource("PiperRuntime/venv/bin/python"),
              let worker = existingResource("piper_worker.py") else {
            return nil
        }
        return PiperInvocation(
            executableURL: venvPython,
            leadingArguments: [worker.path],
            environment: [
                "PATH": "\(venvPython.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
                "PYTHONNOUSERSITE": "1"
            ]
        )
    }

    private var modelURL: URL? {
        for voice in preferredVoices {
            if let url = existingResource("Models/\(voice).onnx") {
                return url
            }
        }
        return nil
    }

    private var configURL: URL? {
        guard let modelURL else { return nil }
        return existingResource("Models/\(modelURL.deletingPathExtension().lastPathComponent).onnx.json")
    }

    private var preferredVoices: [String] {
        [
            "en_GB-alan-medium",
            "en_US-lessac-medium"
        ]
    }

    private func existingResource(_ relativePath: String) -> URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(relativePath),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func existingExecutableResource(_ relativePath: String) -> URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(relativePath),
              fileManager.isExecutableFile(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func temporaryWavURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Gallaxy TTS", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(UUID().uuidString).wav")
    }

    private func speakChunksWithWorker(
        text: String,
        shouldPlay: @escaping () -> Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        let chunks = speechChunks(from: text)
        guard !chunks.isEmpty else {
            completion(.success(()))
            return
        }

        try ensureWorkerStarted()
        beginPlaybackQueue()

        var didEnqueueAudio = false
        do {
            for chunk in chunks {
                guard shouldPlay() else {
                    cancelPlaybackQueue()
                    completion(.success(()))
                    return
                }

                let outputURL = try temporaryWavURL()
                guard try synthesizeWithWorker(text: chunk, outputURL: outputURL) else {
                    try? fileManager.removeItem(at: outputURL)
                    throw PiperError.processFailed("Piper worker did not synthesize audio.")
                }

                guard try enqueuePlaybackFile(outputURL, shouldPlay: shouldPlay) else {
                    cancelPlaybackQueue()
                    completion(.success(()))
                    return
                }
                didEnqueueAudio = true
            }

            endPlaybackQueue()
            completion(.success(()))
        } catch {
            if didEnqueueAudio {
                endPlaybackQueue()
                completion(.success(()))
            } else {
                cancelPlaybackQueue()
                throw error
            }
        }
    }

    private func speechChunks(from text: String) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let maxCharacters = 280
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

    private func beginPlaybackQueue() {
        _ = performPlaybackMutation { playback in
            playback.beginQueue()
            return true
        }
    }

    private func endPlaybackQueue() {
        _ = performPlaybackMutation { playback in
            playback.endQueue()
            return true
        }
    }

    private func cancelPlaybackQueue() {
        _ = performPlaybackMutation { playback in
            playback.stop()
            return true
        }
    }

    private func enqueuePlaybackFile(_ url: URL, shouldPlay: @escaping () -> Bool) throws -> Bool {
        guard shouldPlay() else {
            try? fileManager.removeItem(at: url)
            return false
        }

        do {
            try performPlaybackMutationThrowing { playback in
                try playback.enqueueFile(url)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    private func playSingleFile(_ url: URL, shouldPlay: @escaping () -> Bool) throws -> Bool {
        guard shouldPlay() else {
            try? fileManager.removeItem(at: url)
            return false
        }

        do {
            try performPlaybackMutationThrowing { playback in
                try playback.playFile(url)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    private func ensureWorkerStarted() throws {
        if let workerProcess, workerProcess.isRunning, workerInput != nil, workerOutput != nil {
            return
        }

        guard let workerInvocation = piperWorkerInvocation, let modelURL, let configURL else {
            throw PiperError.assetsMissing
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        process.executableURL = workerInvocation.executableURL
        process.arguments = workerInvocation.leadingArguments + [
            "--model", modelURL.path,
            "--config", configURL.path
        ]
        process.environment = workerInvocation.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorPipe

        try process.run()

        workerProcess = process
        workerInput = input.fileHandleForWriting
        workerOutput = output.fileHandleForReading

        let line = try readWorkerLine()
        guard line.contains("\"ready\": true") else {
            process.terminate()
            workerProcess = nil
            workerInput = nil
            workerOutput = nil
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? line
            throw PiperError.processFailed(message)
        }
    }

    private func synthesizeWithWorker(text: String, outputURL: URL) throws -> Bool {
        guard piperWorkerInvocation != nil else { return false }

        do {
            try ensureWorkerStarted()
            guard let workerInput else { return false }

            let request: [String: Any] = [
                "id": UUID().uuidString,
                "text": text,
                "output_file": outputURL.path,
                "length_scale": lengthScale
            ]
            let requestData = try JSONSerialization.data(withJSONObject: request)
            workerInput.write(requestData)
            workerInput.write(Data([10]))

            let line = try readWorkerLine()
            guard let data = line.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = object["ok"] as? Bool else {
                throw PiperError.processFailed("Invalid Piper worker response: \(line)")
            }

            if ok {
                return true
            }

            let message = object["error"] as? String ?? "Piper worker failed."
            throw PiperError.processFailed(message)
        } catch {
            workerProcess?.terminate()
            workerProcess = nil
            workerInput = nil
            workerOutput = nil
            NSLog("Gallaxy TTS Piper worker failed, falling back to one-shot helper: \(error.localizedDescription)")
            return false
        }
    }

    private func readWorkerLine() throws -> String {
        guard let workerOutput else { throw PiperError.processFailed("Piper worker output is unavailable.") }

        var data = Data()
        while true {
            let nextByte = workerOutput.readData(ofLength: 1)
            if nextByte.isEmpty {
                throw PiperError.processFailed("Piper worker closed unexpectedly.")
            }
            if nextByte.first == 10 {
                break
            }
            data.append(nextByte)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private var lengthScale: Double {
        1.0 / max(0.5, min(speedMultiplier, 1.8))
    }
}

private struct PiperInvocation {
    let executableURL: URL
    let leadingArguments: [String]
    let environment: [String: String]?
}

enum PiperError: LocalizedError {
    case assetsMissing
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetsMissing:
            return "Piper binary or voice model is missing."
        case .processFailed(let message):
            return message
        }
    }
}
