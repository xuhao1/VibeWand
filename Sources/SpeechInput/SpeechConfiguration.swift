import Foundation
import CryptoKit

public enum SpeechInputMode: String, Codable, CaseIterable { case external, builtIn }
public enum SpeechProvider: String, Codable, CaseIterable { case system, qwenRealtime, transcriptionAPI }
public enum DictationTextStyle: String, Codable, CaseIterable { case verbatim, polished }
public enum SpeechPolishingProvider: String, Codable, CaseIterable { case qwenRealtime, chatCompletions }

public struct SpeechPolishingConfiguration: Codable, Equatable {
    public var provider: SpeechPolishingProvider
    public var endpoint: String
    public var model: String
    public init(provider: SpeechPolishingProvider, endpoint: String, model: String) {
        self.provider = provider; self.endpoint = endpoint; self.model = model
    }
    public func apiURL() throws -> URL {
        if provider == .qwenRealtime {
            var audio = SpeechConfiguration(); audio.provider = .qwenRealtime
            audio.endpoint = endpoint; audio.model = model
            return try audio.apiURL()
        }
        guard var parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw SpeechInputError.invalidEndpoint }
        parts.scheme = parts.scheme?.lowercased(); parts.host = host.lowercased()
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        guard parts.scheme == "https" || (local && parts.scheme == "http") else { throw SpeechInputError.invalidEndpoint }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if !parts.path.hasSuffix("/chat/completions") {
            parts.path += parts.path.isEmpty ? "/v1/chat/completions" : "/chat/completions"
        }
        guard let url = parts.url else { throw SpeechInputError.invalidEndpoint }
        return url
    }
    public func validate() throws {
        guard !model.isEmpty, model.count < 200, !model.contains(where: { $0.isNewline }), endpoint.count < 2048 else {
            throw SpeechInputError.invalidConfiguration
        }
        _ = try apiURL()
    }
    public var credentialAccount: String {
        var parts = try? URLComponents(url: apiURL(), resolvingAgainstBaseURL: false)
        parts?.query = nil
        return SHA256.hash(data: Data((parts?.string ?? endpoint).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct SpeechAPISettings: Codable, Equatable {
    public var endpoint: String
    public var model: String
}

/// Shareable preferences. Credentials have no representation in this schema.
public struct SpeechConfiguration: Codable, Equatable {
    public var version = 1
    public var mode: SpeechInputMode = .external
    public var provider: SpeechProvider = .system
    public var locale = "zh-CN"
    public var endpoint = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
    public var model = "qwen3.8-omni-flash-realtime"
    public var apiProfiles: [String: SpeechAPISettings]?
    public var textStyle: DictationTextStyle?
    public var polishing: SpeechPolishingConfiguration?
    public init() {}
    public var effectiveTextStyle: DictationTextStyle { textStyle ?? .verbatim }
    public var effectivePolishing: SpeechPolishingConfiguration? {
        if let polishing { return polishing }
        if provider == .qwenRealtime {
            return SpeechPolishingConfiguration(provider: .qwenRealtime, endpoint: endpoint, model: model)
        }
        if let saved = apiProfiles?[SpeechProvider.qwenRealtime.rawValue] {
            return SpeechPolishingConfiguration(provider: .qwenRealtime, endpoint: saved.endpoint, model: saved.model)
        }
        if provider == .system, model.contains("realtime") {
            return SpeechPolishingConfiguration(provider: .qwenRealtime, endpoint: endpoint, model: model)
        }
        return nil
    }

    public mutating func selectProvider(_ value: SpeechProvider) {
        guard value != provider else { return }
        var profiles = apiProfiles ?? [:]
        if provider != .system { profiles[provider.rawValue] = SpeechAPISettings(endpoint: endpoint, model: model) }
        provider = value
        if value != .system {
            let saved = profiles[value.rawValue] ?? (value == .qwenRealtime ?
                SpeechAPISettings(endpoint: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime", model: "qwen3.8-omni-flash-realtime") :
                SpeechAPISettings(endpoint: "https://your-service.example/v1", model: "whisper-1"))
            endpoint = saved.endpoint; model = saved.model
        }
        apiProfiles = profiles
    }

    public func apiURL() throws -> URL {
        guard var parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil, parts.query == nil else { throw SpeechInputError.invalidEndpoint }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        if provider != .transcriptionAPI {
            guard ["https", "wss"].contains(parts.scheme) || (local && ["http", "ws"].contains(parts.scheme)) else {
                throw SpeechInputError.invalidEndpoint
            }
            parts.scheme = parts.scheme == "http" || parts.scheme == "ws" ? "ws" : "wss"
            if parts.path.isEmpty || parts.path == "/" || parts.path == "/api/v1" || parts.path == "/compatible-mode/v1" {
                parts.path = "/api-ws/v1/realtime"
            }
            parts.queryItems = [URLQueryItem(name: "model", value: model)]
        } else {
            guard parts.scheme == "https" || (local && parts.scheme == "http") else { throw SpeechInputError.invalidEndpoint }
            var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.hasSuffix("audio/transcriptions") { path += path.isEmpty ? "v1/audio/transcriptions" : "/audio/transcriptions" }
            parts.path = "/" + path
        }
        guard let url = parts.url else { throw SpeechInputError.invalidEndpoint }
        return url
    }

    public func validate() throws {
        guard version == 1, !locale.isEmpty, locale.count < 80, endpoint.count < 2048,
              !model.isEmpty, model.count < 200, !model.contains(where: { $0.isNewline }) else {
            throw SpeechInputError.invalidConfiguration
        }
        // Always validate the endpoint, including when exporting system preferences.
        _ = try apiURL()
        try polishing?.validate()
        for (id, settings) in apiProfiles ?? [:] {
            guard let provider = SpeechProvider(rawValue: id), provider != .system else { throw SpeechInputError.invalidConfiguration }
            var profile = SpeechConfiguration()
            profile.provider = provider; profile.endpoint = settings.endpoint; profile.model = settings.model
            try profile.validate()
        }
    }

    public var credentialAccount: String {
        // Bind each secret to a destination. Importing another host cannot reuse it.
        var parts = try? URLComponents(url: apiURL(), resolvingAgainstBaseURL: false)
        parts?.query = nil
        let destination = parts?.string ?? endpoint
        return SHA256.hash(data: Data(destination.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public final class SpeechPreferences {
    public static let storageKey = "vibeWand.speech.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> SpeechConfiguration {
        guard let data = defaults.data(forKey: Self.storageKey),
              let value = try? JSONDecoder().decode(SpeechConfiguration.self, from: data),
              (try? value.validate()) != nil else { return SpeechConfiguration() }
        return value
    }
    public func save(_ value: SpeechConfiguration) throws {
        try value.validate()
        defaults.set(try export(value), forKey: Self.storageKey)
    }
    public func export(_ value: SpeechConfiguration) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
    public func decodeImport(_ data: Data) throws -> SpeechConfiguration {
        guard data.count <= 16384 else { throw SpeechInputError.invalidConfiguration }
        let value = try JSONDecoder().decode(SpeechConfiguration.self, from: data)
        try value.validate()
        return value
    }
}

public enum SpeechInputError: Error, Equatable, LocalizedError {
    case invalidEndpoint, invalidConfiguration, missingAPIKey, microphoneDenied, speechDenied
    case unavailable, recordingFailed, tooLong, noSpeech, emptyAudio, timedOut, protocolRejected, polishingUnavailable
    case http(Int), keychain(Int32)
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Use an HTTPS or WSS endpoint without credentials, query parameters or a fragment. Localhost also supports HTTP."
        case .invalidConfiguration: return "Invalid speech configuration."
        case .missingAPIKey: return "Save an API key for this endpoint first."
        case .microphoneDenied: return "Enable microphone access in macOS Privacy & Security."
        case .speechDenied: return "Enable speech recognition in macOS Privacy & Security."
        case .unavailable: return "System speech recognition is unavailable for this language."
        case .recordingFailed: return "The microphone could not start. Check the macOS audio input."
        case .tooLong: return "Dictation is limited to two minutes. Release and start a new recording."
        case .noSpeech: return "No speech was recognized."
        case .emptyAudio: return "Hold the button longer before releasing."
        case .timedOut: return "Speech recognition timed out."
        case .protocolRejected: return "The service rejected the speech request. Check its protocol, model and credentials."
        case .polishingUnavailable: return "Text polishing is unavailable; the original transcript has been kept. Configure a polishing service and its key."
        case .http(let code): return "Speech service returned HTTP \(code). Check the endpoint, model and credentials."
        case .keychain(let code): return "Keychain operation failed (\(code))."
        }
    }
}
