import AVFoundation
import Foundation
import OSLog

private let kokoroLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.gallaxy.tts.local",
    category: "Kokoro"
)

enum KokoroSpeechError: LocalizedError {
    case runtimeMissing
    case processFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            return "Kokoro MLX runtime is missing."
        case .processFailed(let message):
            return message
        case .cancelled:
            return "Kokoro playback was cancelled."
        }
    }
}

final class KokoroEngine {
    private static let modelID = "mlx-community/Kokoro-82M-bf16"
    private static let voiceID = "af_bella"
    private static let languageCode = "a"

    private let playback = PlaybackController()
    private let fileManager = FileManager.default
    private let processQueue = DispatchQueue(label: "app.gallaxy.tts.kokoro.process")
    private var activeProcess: Process?
    private var workerProcess: Process?
    private var workerInput: FileHandle?
    private var workerOutput: FileHandle?
    private let workerLock = NSRecursiveLock()

    var speedMultiplier: Double = 1.15 {
        didSet {
            let multiplier = speedMultiplier
            _ = performPlaybackMutation {
                $0.setRate(multiplier)
                return true
            }
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

    var isReady: Bool {
        kokoroInvocation != nil
    }

    var isSpeaking: Bool {
        performPlaybackRead { $0.isPlaying || $0.hasQueuedAudio }
    }

    var isPaused: Bool {
        performPlaybackRead { $0.isPaused }
    }

    func warmUp() {
        do {
            let startedAt = Date()
            try withWorkerLock {
                try ensureWorkerStarted()
                try warmWorker()
            }
            kokoroLogger.info("Kokoro worker warm elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)")
        } catch {
            kokoroLogger.error("Kokoro warmup failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func keepWarm() {
        do {
            let startedAt = Date()
            try withWorkerLock {
                try ensureWorkerStarted()
                try warmWorker()
            }
            kokoroLogger.info("Kokoro keepalive finished elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)")
        } catch {
            kokoroLogger.error("Kokoro keepalive failed error=\(error.localizedDescription, privacy: .public)")
            resetWorker()
        }
    }

    func prepareAfterWake() {
        do {
            let startedAt = Date()
            try withWorkerLock {
                do {
                    try ensureWorkerStarted()
                    try warmWorker()
                } catch {
                    resetWorkerLocked()
                    try ensureWorkerStarted()
                    try warmWorker()
                }
            }
            kokoroLogger.info("Kokoro wake refresh elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)")
        } catch {
            kokoroLogger.error("Kokoro wake refresh failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func speak(
        _ text: String,
        shouldPlay: @escaping () -> Bool = { true },
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let invocation = kokoroInvocation else {
            completion(.failure(KokoroSpeechError.runtimeMissing))
            return
        }

        do {
            let outputURL = try temporaryWavURL()
            let textURL = try temporaryTextURL()
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            defer { try? fileManager.removeItem(at: textURL) }

            if workerInvocation != nil {
                do {
                    try withWorkerLock {
                        try synthesizeWithWorkerRetryingOnce(text: text, outputURL: outputURL)
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        guard shouldPlay() else {
                            try? self.fileManager.removeItem(at: outputURL)
                            completion(.failure(KokoroSpeechError.cancelled))
                            return
                        }

                        do {
                            try self.playback.playFile(outputURL)
                            completion(.success(()))
                        } catch {
                            try? self.fileManager.removeItem(at: outputURL)
                            completion(.failure(error))
                        }
                    }
                    return
                } catch {
                    kokoroLogger.error("Kokoro worker failed error=\(error.localizedDescription, privacy: .public)")
                    resetWorker()
                }
            }

            stopOneShotProcess()

            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.leadingArguments + [
                "--text-file", textURL.path,
                "--output", outputURL.path,
                "--model", Self.modelID,
                "--voice", Self.voiceID,
                "--lang-code", Self.languageCode,
                "--speed", "1.0"
            ]
            process.environment = invocation.environment

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()

            try process.run()
            setActiveProcess(process)
            kokoroLogger.info("Kokoro request started chars=\(text.count, privacy: .public) model=\(Self.modelID, privacy: .public)")

            process.waitUntilExit()
            clearActiveProcess(process)

            guard shouldPlay() else {
                try? fileManager.removeItem(at: outputURL)
                completion(.failure(KokoroSpeechError.cancelled))
                return
            }

            guard process.terminationStatus == 0 else {
                try? fileManager.removeItem(at: outputURL)
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: errorData, encoding: .utf8) ?? "Kokoro exited with status \(process.terminationStatus)."
                completion(.failure(KokoroSpeechError.processFailed(message)))
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard shouldPlay() else {
                    try? self.fileManager.removeItem(at: outputURL)
                    completion(.failure(KokoroSpeechError.cancelled))
                    return
                }

                do {
                    try self.playback.playFile(outputURL)
                    completion(.success(()))
                } catch {
                    try? self.fileManager.removeItem(at: outputURL)
                    completion(.failure(error))
                }
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
        resetWorker()
        stopOneShotProcess()
    }

    private var kokoroInvocation: KokoroInvocation? {
        if let venvPython = existingExecutableAppSupportFile("KokoroRuntime/venv/bin/python"),
           let helper = existingResource("kokoro_synth.py") {
            return KokoroInvocation(
                executableURL: venvPython,
                leadingArguments: [helper.path],
                environment: [
                    "PATH": "\(venvPython.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
                    "PYTHONNOUSERSITE": "1"
                ]
            )
        }

        if let venvPython = existingExecutableResource("KokoroRuntime/venv/bin/python"),
           let helper = existingResource("kokoro_synth.py") {
            return KokoroInvocation(
                executableURL: venvPython,
                leadingArguments: [helper.path],
                environment: [
                    "PATH": "\(venvPython.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
                    "PYTHONNOUSERSITE": "1"
                ]
            )
        }

        if let pythonPath = ProcessInfo.processInfo.environment["GALLAXY_KOKORO_PYTHON"],
           fileManager.isExecutableFile(atPath: pythonPath),
           let helper = existingResource("kokoro_synth.py") {
            return KokoroInvocation(
                executableURL: URL(fileURLWithPath: pythonPath),
                leadingArguments: [helper.path],
                environment: nil
            )
        }

        return nil
    }

    private var workerInvocation: KokoroInvocation? {
        if let venvPython = existingExecutableAppSupportFile("KokoroRuntime/venv/bin/python"),
           let worker = existingResource("kokoro_worker.py") {
            return KokoroInvocation(
                executableURL: venvPython,
                leadingArguments: [worker.path],
                environment: [
                    "PATH": "\(venvPython.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
                    "PYTHONNOUSERSITE": "1"
                ]
            )
        }

        if let venvPython = existingExecutableResource("KokoroRuntime/venv/bin/python"),
           let worker = existingResource("kokoro_worker.py") {
            return KokoroInvocation(
                executableURL: venvPython,
                leadingArguments: [worker.path],
                environment: [
                    "PATH": "\(venvPython.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
                    "PYTHONNOUSERSITE": "1"
                ]
            )
        }

        return nil
    }

    private func existingResource(_ relativePath: String) -> URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(relativePath),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func existingExecutableAppSupportFile(_ relativePath: String) -> URL? {
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = supportURL
            .appendingPathComponent("Gallaxy TTS", isDirectory: true)
            .appendingPathComponent(relativePath)
        guard fileManager.isExecutableFile(atPath: url.path) else {
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
        let directory = try temporaryDirectory()
        return directory.appendingPathComponent("kokoro-\(UUID().uuidString).wav")
    }

    private func temporaryTextURL() throws -> URL {
        let directory = try temporaryDirectory()
        return directory.appendingPathComponent("kokoro-\(UUID().uuidString).txt")
    }

    private func temporaryDirectory() throws -> URL {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("Gallaxy TTS", isDirectory: true)
            .appendingPathComponent("Kokoro", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func setActiveProcess(_ process: Process) {
        processQueue.sync {
            activeProcess = process
        }
    }

    private func clearActiveProcess(_ process: Process) {
        processQueue.sync {
            if activeProcess === process {
                activeProcess = nil
            }
        }
    }

    private func stopOneShotProcess() {
        processQueue.sync {
            guard let process = activeProcess else { return }
            if process.isRunning {
                process.terminate()
            }
            activeProcess = nil
        }
    }

    private func ensureWorkerStarted() throws {
        if let workerProcess, workerProcess.isRunning, workerInput != nil, workerOutput != nil {
            return
        }

        guard let workerInvocation else {
            throw KokoroSpeechError.runtimeMissing
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        process.executableURL = workerInvocation.executableURL
        process.arguments = workerInvocation.leadingArguments + [
            "--model", Self.modelID,
            "--voice", Self.voiceID,
            "--lang-code", Self.languageCode
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
            throw KokoroSpeechError.processFailed(message)
        }
    }

    private func synthesizeWithWorkerRetryingOnce(text: String, outputURL: URL) throws {
        do {
            try synthesizeWithWorker(text: text, outputURL: outputURL)
        } catch {
            kokoroLogger.info("Kokoro worker retrying after failed synthesis")
            resetWorker()
            try ensureWorkerStarted()
            try synthesizeWithWorker(text: text, outputURL: outputURL)
        }
    }

    private func synthesizeWithWorker(text: String, outputURL: URL) throws {
        try ensureWorkerStarted()
        guard let workerInput else {
            throw KokoroSpeechError.processFailed("Kokoro worker input is unavailable.")
        }

        let request: [String: Any] = [
            "id": UUID().uuidString,
            "text": text,
            "output_file": outputURL.path,
            "voice": Self.voiceID,
            "lang_code": Self.languageCode,
            "speed": 1.0
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        workerInput.write(requestData)
        workerInput.write(Data([10]))

        try readWorkerResponse()
    }

    private func warmWorker() throws {
        try ensureWorkerStarted()
        guard let workerInput else {
            throw KokoroSpeechError.processFailed("Kokoro worker input is unavailable.")
        }

        let request: [String: Any] = [
            "id": UUID().uuidString,
            "kind": "warm"
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        workerInput.write(requestData)
        workerInput.write(Data([10]))

        try readWorkerResponse()
    }

    private func readWorkerResponse() throws {
        let line = try readWorkerLine()
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = object["ok"] as? Bool else {
            throw KokoroSpeechError.processFailed("Invalid Kokoro worker response: \(line)")
        }

        if ok {
            return
        }

        let message = object["error"] as? String ?? "Kokoro worker failed."
        throw KokoroSpeechError.processFailed(message)
    }

    private func resetWorker() {
        workerLock.lock()
        defer { workerLock.unlock() }
        resetWorkerLocked()
    }

    private func resetWorkerLocked() {
        workerInput = nil
        workerOutput = nil
        if let workerProcess, workerProcess.isRunning {
            workerProcess.terminate()
        }
        workerProcess = nil
    }

    private func withWorkerLock<T>(_ body: () throws -> T) rethrows -> T {
        workerLock.lock()
        defer { workerLock.unlock() }
        return try body()
    }

    private func readWorkerLine() throws -> String {
        guard let workerOutput else {
            throw KokoroSpeechError.processFailed("Kokoro worker output is unavailable.")
        }

        var data = Data()
        while true {
            let nextByte = workerOutput.readData(ofLength: 1)
            if nextByte.isEmpty {
                throw KokoroSpeechError.processFailed("Kokoro worker closed unexpectedly.")
            }
            if nextByte.first == 10 {
                break
            }
            data.append(nextByte)
        }

        return String(data: data, encoding: .utf8) ?? ""
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
}

private struct KokoroInvocation {
    let executableURL: URL
    let leadingArguments: [String]
    let environment: [String: String]?
}

private func elapsedMilliseconds(since start: Date) -> Int {
    Int(Date().timeIntervalSince(start) * 1000)
}
