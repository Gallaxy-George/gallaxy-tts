import Foundation

enum ElevenLabsCredentialError: LocalizedError {
    case emptyKey
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "Enter an ElevenLabs API key first."
        case .storageUnavailable:
            return "Gallaxy TTS could not save the API key."
        }
    }
}

enum ElevenLabsCredentialStore {
    private static let directoryName = "Gallaxy TTS"
    private static let credentialFileName = "elevenlabs-api-key.txt"

    static func apiKey() -> String? {
        fileAPIKey(directoryName: directoryName)
    }

    static func hasAPIKey() -> Bool {
        guard let key = apiKey() else { return false }
        return key.isEmpty == false
    }

    static func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ElevenLabsCredentialError.emptyKey
        }

        let directoryURL = try credentialsDirectoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let fileURL = directoryURL.appendingPathComponent(credentialFileName, isDirectory: false)
        try Data(trimmed.utf8).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func deleteAPIKey() {
        if let fileURL = try? credentialsDirectoryURL(directoryName: directoryName).appendingPathComponent(credentialFileName, isDirectory: false) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func fileAPIKey(directoryName: String) -> String? {
        guard let fileURL = try? credentialsDirectoryURL(directoryName: directoryName).appendingPathComponent(credentialFileName, isDirectory: false),
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func credentialsDirectoryURL() throws -> URL {
        try credentialsDirectoryURL(directoryName: directoryName)
    }

    private static func credentialsDirectoryURL(directoryName: String) throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ElevenLabsCredentialError.storageUnavailable
        }

        return applicationSupportURL.appendingPathComponent(directoryName, isDirectory: true)
    }
}
