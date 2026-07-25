import Foundation
import Security

enum ElevenLabsCredentialError: LocalizedError {
    case emptyKey
    case storageUnavailable
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "Enter an ElevenLabs API key first."
        case .storageUnavailable:
            return "Gallaxy TTS could not save the API key."
        case .keychainFailure(let status):
            return "Gallaxy TTS could not access Keychain (status \(status))."
        }
    }
}

enum ElevenLabsCredentialStore {
    private static let directoryName = "Gallaxy TTS"
    private static let credentialFileName = "elevenlabs-api-key.txt"
    private static let keychainService = "app.gallaxy.tts.elevenlabs"
    private static let keychainAccount = "api-key"

    static func apiKey() -> String? {
        if let key = keychainAPIKey() {
            return key
        }

        guard let legacyKey = fileAPIKey(directoryName: directoryName) else {
            return nil
        }

        do {
            try saveKeychainAPIKey(legacyKey)
            deleteLegacyAPIKey()
        } catch {
            // Never use a plaintext legacy credential unless it has first been
            // migrated into Keychain. Leave the file for a later migration retry.
            return nil
        }

        return legacyKey
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

        try saveKeychainAPIKey(trimmed)
        deleteLegacyAPIKey()
    }

    static func deleteAPIKey() {
        SecItemDelete(keychainBaseQuery() as CFDictionary)
        deleteLegacyAPIKey()
    }

    private static func keychainAPIKey() -> String? {
        var query = keychainBaseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func saveKeychainAPIKey(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(
            keychainBaseQuery() as CFDictionary,
            attributes as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = keychainBaseQuery()
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ElevenLabsCredentialError.keychainFailure(addStatus)
            }
        default:
            throw ElevenLabsCredentialError.keychainFailure(updateStatus)
        }
    }

    private static func keychainBaseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func deleteLegacyAPIKey() {
        guard let fileURL = try? credentialsDirectoryURL(directoryName: directoryName).appendingPathComponent(credentialFileName, isDirectory: false) else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
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
