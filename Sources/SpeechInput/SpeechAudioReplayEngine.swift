import Foundation

/// Explicit audio-file replay for end-to-end checks. Normal app sessions always
/// use microphone engines; this source is selected only by a diagnostic flag.
@MainActor
public final class SpeechAudioReplayEngine: DictationEngine {
    public var onPartialTranscript: ((String) -> Void)?
    public var onFailure: ((SpeechInputError) -> Void)?
    private let url: URL, configuration: SpeechConfiguration
    private let credentials: any SpeechCredentialStore
    private let stream = QwenRealtimeStream()
    private var sending: Task<Void, Error>?
    public init(url: URL, configuration: SpeechConfiguration, credentials: any SpeechCredentialStore) {
        self.url = url; self.configuration = configuration; self.credentials = credentials
    }
    public func start() async throws {
        guard configuration.provider == .qwenRealtime else { throw SpeechInputError.invalidConfiguration }
        let audio = try SpeechAudio.read(from: url)
        guard let key = try await credentials.readAsync(account: configuration.credentialAccount) else { throw SpeechInputError.missingAPIKey }
        try Task.checkCancellation()
        stream.onPartial = { [weak self] in self?.onPartialTranscript?($0) }
        try await stream.start(configuration: configuration, apiKey: key)
        sending = Task {
            for offset in stride(from: 0, to: audio.pcm.count, by: 6400) {
                try Task.checkCancellation()
                try await stream.append(audio.pcm.subdata(in: offset..<min(offset + 6400, audio.pcm.count)))
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }
    public func finish() async throws -> String { try await sending?.value; return try await stream.finish() }
    public func cancel() { sending?.cancel(); sending = nil; stream.cancel() }
}

/// Anonymous stdin credentials for an explicit diagnostic run; never saved or
/// exported, and usable only for the one destination selected for that run.
public struct EphemeralSpeechCredentials: SpeechCredentialStore {
    private let key: String, account: String
    public init(key: String, account: String) { self.key = key; self.account = account }
    public func read(account: String) throws -> String? { account == self.account ? key : nil }
    public func contains(account: String) -> Bool { account == self.account }
    public func save(_ key: String, account: String) throws { throw SpeechInputError.invalidConfiguration }
    public func remove(account: String) throws { throw SpeechInputError.invalidConfiguration }
}
