import Foundation

@MainActor
public protocol DictationEngine: AnyObject {
    var onPartialTranscript: ((String) -> Void)? { get set }
    var onFailure: ((SpeechInputError) -> Void)? { get set }
    func start() async throws
    func finish() async throws -> String
    func cancel()
}
public extension DictationEngine {
    var onPartialTranscript: ((String) -> Void)? { get { nil } set {} }
    var onFailure: ((SpeechInputError) -> Void)? { get { nil } set {} }
}

public enum DictationState: Equatable {
    case idle, preparing, recording, transcribing, polishing, completed, failed(SpeechInputError)
    public var active: Bool { self == .preparing || self == .recording || self == .transcribing || self == .polishing }
}

/// Owns lifecycle and race handling; no view framework or target-app knowledge.
@MainActor
public final class DictationSession {
    public private(set) var state: DictationState = .idle { didSet { onState?(state) } }
    public var onState: ((DictationState) -> Void)?
    public var onTranscript: ((String) -> Void)?
    public var onPartialTranscript: ((String) -> Void)?
    public var onNotice: ((SpeechInputError) -> Void)?
    public private(set) var preview = ""
    public var textStyle: DictationTextStyle = .verbatim
    private var configuration = SpeechConfiguration()
    private let processor: any SpeechTextProcessing
    private let credentials: any SpeechCredentialStore
    private let factory: (SpeechConfiguration) throws -> any DictationEngine
    private var engine: (any DictationEngine)?
    private var task: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    private var generation: UInt = 0
    public init(processor: any SpeechTextProcessing = SpeechTextProcessor(),
                credentials: any SpeechCredentialStore = KeychainSpeechCredentials(),
                factory: @escaping (SpeechConfiguration) throws -> any DictationEngine) {
        self.factory = factory; self.processor = processor; self.credentials = credentials
    }

    public func begin(_ configuration: SpeechConfiguration) {
        cancel()
        self.configuration = configuration; textStyle = configuration.effectiveTextStyle
        let token = generation
        state = .preparing
        weak var callbackOwner: DictationSession?
        task = Task {
            do {
                try Task.checkCancellation()
                guard generation == token else { return }
                callbackOwner = self
                try configuration.validate()
                let engine = try factory(configuration)
                self.engine = engine
                engine.onPartialTranscript = { text in
                    guard let owner = callbackOwner, owner.generation == token, owner.state.active else { return }
                    owner.preview = text; owner.onPartialTranscript?(text)
                }
                engine.onFailure = { error in
                    guard let owner = callbackOwner, owner.generation == token, owner.state.active else { return }
                    owner.cancel(); owner.state = .failed(error)
                }
                try await engine.start()
                guard generation == token, !Task.isCancelled else { engine.cancel(); return }
                state = .recording
                limitTask = Task {
                    try? await Task.sleep(nanoseconds: 120_000_000_000)
                    guard !Task.isCancelled, generation == token, state == .recording else { return }
                    cancel(); state = .failed(.tooLong)
                }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                engine?.cancel(); engine = nil
                state = .failed(Self.safeError(error))
            }
        }
    }
    public func end() {
        // A short press released during a permission prompt must not record later.
        guard state == .recording, let engine else { if state == .preparing { cancel() }; return }
        limitTask?.cancel(); limitTask = nil
        state = .transcribing
        let token = generation
        task = Task {
            do {
                let raw = try await engine.finish()
                guard token == generation, !Task.isCancelled else { return }
                preview = raw; onPartialTranscript?(raw)
                var text = raw
                if textStyle == .polished {
                    state = .polishing
                    do {
                        guard let settings = configuration.effectivePolishing else { throw SpeechInputError.polishingUnavailable }
                        let key = try await credentials.readAsync(account: settings.credentialAccount)
                        try Task.checkCancellation()
                        text = try await processor.polish(raw, configuration: settings, apiKey: key)
                    } catch {
                        guard token == generation, !Task.isCancelled else { return }
                        onNotice?(.polishingUnavailable)
                    }
                }
                guard token == generation, !Task.isCancelled else { return }
                preview = text; onPartialTranscript?(text)
                self.engine = nil
                state = .completed; onTranscript?(text)
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                engine.cancel(); self.engine = nil
                state = .failed(Self.safeError(error))
            }
        }
    }
    public func cancel() {
        generation &+= 1
        task?.cancel(); task = nil; limitTask?.cancel(); limitTask = nil
        engine?.cancel(); engine = nil
        preview = ""; onPartialTranscript?("")
        state = .idle
    }
    public static func safeError(_ error: Error) -> SpeechInputError {
        if let error = error as? SpeechInputError { return error }
        if (error as? URLError)?.code == .timedOut { return .timedOut }
        return .protocolRejected
    }
}
