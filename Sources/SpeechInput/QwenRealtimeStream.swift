import Foundation

/// A live audio transport, independent of microphone capture and UI. Its single
/// receive loop forwards actual ASR previews and never an assistant response.
@MainActor
public final class QwenRealtimeStream {
    public var onPartial: ((String) -> Void)?
    public var onFailure: ((SpeechInputError) -> Void)?
    private let session = URLSession(configuration: .ephemeral, delegate: SpeechRedirectPolicy(), delegateQueue: nil)
    private var socket: URLSessionWebSocketTask?
    private var receiving: Task<Void, Never>?
    private var buffer = SpeechTranscriptBuffer()
    private var final: Result<String, Error>?
    private var waiter: CheckedContinuation<String, Error>?
    private var deadline: Task<Void, Never>?
    private var generation = 0
    public init() {}
    deinit { session.invalidateAndCancel() }
    public func start(configuration: SpeechConfiguration, apiKey: String) async throws {
        cancel(); try configuration.validate()
        var request = URLRequest(url: try configuration.apiURL()); request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request); self.socket = socket; socket.resume()
        do {
            try await SpeechAPIClient.waitFor("session.created", socket: socket)
            try await SpeechAPIClient.send(SpeechAPIClient.sessionUpdate(), socket: socket)
            try await SpeechAPIClient.waitFor("session.updated", socket: socket)
        } catch { cancel(); throw error }
        let token = generation
        receiving = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let event = try await SpeechAPIClient.receive(socket)
                    guard let self, token == self.generation else { return }
                    if self.buffer.accept(event) { self.onPartial?(self.buffer.text) }
                    if event["type"] as? String == "conversation.item.input_audio_transcription.completed" {
                        let text = self.buffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.resolve(text.isEmpty ? .failure(SpeechInputError.noSpeech) : .success(text))
                    } else if event["type"] as? String == "conversation.item.input_audio_transcription.failed" {
                        throw SpeechInputError.protocolRejected
                    }
                }
            } catch {
                guard let self, token == self.generation, !Task.isCancelled else { return }
                self.resolve(.failure(error)); self.onFailure?(DictationSession.safeError(error))
            }
        }
    }
    public func append(_ pcm: Data) async throws {
        try Task.checkCancellation()
        guard let socket else { throw SpeechInputError.protocolRejected }
        try await SpeechAPIClient.send(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()], socket: socket)
    }
    public func finish() async throws -> String {
        guard let socket else { throw SpeechInputError.protocolRejected }
        defer { cancel() }
        try await SpeechAPIClient.send(["type": "input_audio_buffer.commit"], socket: socket)
        if let final { return try final.get() }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
                deadline = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.resolve(.failure(SpeechInputError.timedOut))
                }
            }
        }, onCancel: { Task { @MainActor in self.cancel() } })
    }
    private func resolve(_ value: Result<String, Error>) {
        guard final == nil else { return }
        final = value; deadline?.cancel(); deadline = nil
        if let waiter { self.waiter = nil; waiter.resume(with: value) }
    }
    public func cancel() {
        generation += 1
        receiving?.cancel(); receiving = nil; deadline?.cancel(); deadline = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        if let waiter { self.waiter = nil; waiter.resume(throwing: CancellationError()) }
        buffer = SpeechTranscriptBuffer(); final = nil
    }
}
