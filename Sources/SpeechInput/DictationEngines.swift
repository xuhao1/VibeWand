import Foundation
import Speech

@MainActor
public final class SystemDictationEngine: DictationEngine {
    public var onPartialTranscript: ((String) -> Void)?
    public var onFailure: ((SpeechInputError) -> Void)?
    private let locale: Locale
    private let capture = MicrophoneCapture()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var result: Result<String, Error>?
    private var continuation: CheckedContinuation<String, Error>?
    private var deadline: Task<Void, Never>?
    private var generation = 0
    private let vocabulary: [String]
    public init(locale: String, vocabulary: [String] = []) { self.locale = Locale(identifier: locale); self.vocabulary = vocabulary }
    public func start() async throws {
        // Both permission prompts complete before creating a recognition task,
        // so time spent approving the microphone cannot expire that task.
        try await MicrophoneCapture.authorize()
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard authorization == .authorized else { throw SpeechInputError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw SpeechInputError.unavailable }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.contextualStrings = vocabulary
        // Prefer local recognition; Apple's online path covers other locales.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        let token = generation
        recognition = recognizer.recognitionTask(with: request) { [weak self] value, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let value { self.onPartialTranscript?(value.bestTranscription.formattedString) }
                if let value, value.isFinal {
                    let text = value.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.resolve(text.isEmpty ? .failure(SpeechInputError.noSpeech) : .success(text))
                } else if error != nil { self.resolve(.failure(SpeechInputError.unavailable)) }
            }
        }
        try await capture.start { buffer in request.append(buffer) }
    }
    public func finish() async throws -> String {
        defer { cancel() }
        _ = try capture.stop()
        request?.endAudio()
        if let result { return try result.get() }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                deadline = Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled else { return }
                    resolve(.failure(SpeechInputError.timedOut))
                }
            }
        }, onCancel: { Task { @MainActor in self.resolve(.failure(CancellationError())) } })
    }
    private func resolve(_ value: Result<String, Error>) {
        guard result == nil else { return }
        result = value
        deadline?.cancel(); deadline = nil
        if let continuation { self.continuation = nil; continuation.resume(with: value) }
    }
    public func cancel() {
        generation += 1
        deadline?.cancel(); deadline = nil
        capture.cancel(); request?.endAudio(); recognition?.cancel()
        request = nil; recognition = nil; result = nil
        if let continuation { self.continuation = nil; continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
public final class APIDictationEngine: DictationEngine {
    public var onPartialTranscript: ((String) -> Void)?
    public var onFailure: ((SpeechInputError) -> Void)?
    private let capture = MicrophoneCapture()
    private let configuration: SpeechConfiguration
    private let credentials: any SpeechCredentialStore
    private let client: any SpeechTranscribing
    private var stream: QwenRealtimeStream?
    private var feed: AsyncStream<Data>.Continuation?
    private var transportTask: Task<Void, Error>?
    private var previewTask: Task<Void, Never>?
    private var generation = 0
    private var apiKey: String?
    public init(configuration: SpeechConfiguration, credentials: any SpeechCredentialStore,
                client: any SpeechTranscribing = SpeechAPIClient()) {
        self.configuration = configuration; self.credentials = credentials; self.client = client
    }
    public func start() async throws {
        // Fail before recording if a remote destination has no credential.
        let host = try configuration.apiURL().host ?? ""
        let key = try await credentials.readAsync(account: configuration.credentialAccount)
        apiKey = key
        try Task.checkCancellation()
        if !["localhost", "127.0.0.1", "::1", "[::1]"].contains(host), key == nil {
            throw SpeechInputError.missingAPIKey
        }
        let token = generation
        let configuration = self.configuration
        if configuration.provider == .qwenRealtime {
            guard let key else { throw SpeechInputError.missingAPIKey }
            let stream = QwenRealtimeStream(); self.stream = stream
            stream.onPartial = { [weak self] text in
                guard let self, token == self.generation else { return }
                self.onPartialTranscript?(text)
            }
            stream.onFailure = { [weak self] error in
                guard let self, token == self.generation else { return }; self.onFailure?(error)
            }
            let (audio, feed) = AsyncStream<Data>.makeStream(); self.feed = feed
            try await capture.start(onPCM: { feed.yield($0) })
            transportTask = Task { [weak self] in
                do {
                    try await stream.start(configuration: configuration, apiKey: key)
                    for await chunk in audio { try await stream.append(chunk) }
                } catch {
                    guard let self, token == self.generation, !Task.isCancelled else { throw CancellationError() }
                    self.onFailure?(DictationSession.safeError(error)); throw error
                }
            }
        } else {
            try await capture.start()
            // A file-upload API has no live audio channel. Bounded snapshots
            // provide previews using only the explicitly selected provider.
            previewTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard let self, token == self.generation, !Task.isCancelled else { return }
                    do {
                        let audio = try self.capture.snapshot()
                        let text = try await self.client.transcribe(audio, configuration: self.configuration,
                            apiKey: self.apiKey)
                        guard token == self.generation, !Task.isCancelled else { return }
                        self.onPartialTranscript?(text)
                    } catch { /* Final recognition reports errors; a preview is optional. */ }
                }
            }
        }
    }
    public func finish() async throws -> String {
        let audio = try capture.stop()
        previewTask?.cancel(); previewTask = nil
        if let stream {
            feed?.finish(); feed = nil
            try await transportTask?.value
            let text = try await stream.finish()
            self.stream = nil; transportTask = nil
            return text
        }
        return try await client.transcribe(audio, configuration: configuration, apiKey: apiKey)
    }
    public func cancel() {
        generation += 1
        previewTask?.cancel(); previewTask = nil
        transportTask?.cancel(); transportTask = nil
        feed?.finish(); feed = nil; stream?.cancel(); stream = nil
        apiKey = nil
        capture.cancel()
    }
}
