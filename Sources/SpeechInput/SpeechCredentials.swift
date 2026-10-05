import Foundation
import Security

public protocol SpeechCredentialStore {
    func read(account: String) throws -> String?
    func save(_ key: String, account: String) throws
    func remove(account: String) throws
    func contains(account: String) -> Bool
}
public extension SpeechCredentialStore {
    func contains(account: String) -> Bool { ((try? read(account: account)) ?? nil) != nil }
    func contains(for configuration: SpeechConfiguration) -> Bool { contains(account: configuration.credentialAccount) }
    func contains(for configuration: SpeechPolishingConfiguration) -> Bool { contains(account: configuration.credentialAccount) }
    func readAsync(account: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try self.read(account: account)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func read(for configuration: SpeechConfiguration) throws -> String? { try read(account: configuration.credentialAccount) }
    func save(_ key: String, for configuration: SpeechConfiguration) throws {
        try configuration.validate(); try save(key, account: configuration.credentialAccount)
    }
    func remove(for configuration: SpeechConfiguration) throws { try remove(account: configuration.credentialAccount) }
    func read(for configuration: SpeechPolishingConfiguration) throws -> String? { try read(account: configuration.credentialAccount) }
    func save(_ key: String, for configuration: SpeechPolishingConfiguration) throws {
        try configuration.validate(); try save(key, account: configuration.credentialAccount)
    }
    func remove(for configuration: SpeechPolishingConfiguration) throws { try remove(account: configuration.credentialAccount) }
}

public struct KeychainSpeechCredentials: SpeechCredentialStore {
    public static let service = "org.vibekey.bridge.speech-api"
    private let service: String
    public init(service: String = KeychainSpeechCredentials.service) { self.service = service }
    public func contains(account: String) -> Bool {
        var item = query(account)
        item[kSecReturnAttributes as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(item as CFDictionary, nil) == errSecSuccess
    }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    public func read(account: String) throws -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw SpeechInputError.keychain(status)
        }
        return key
    }
    public func save(_ key: String, account: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace }) else { throw SpeechInputError.missingAPIKey }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item.merge(attributes) { _, value in value }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw SpeechInputError.keychain(added) }
        } else if status != errSecSuccess { throw SpeechInputError.keychain(status) }
    }
    public func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SpeechInputError.keychain(status) }
    }
}
