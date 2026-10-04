import Foundation

/// Deterministic delivery checks use no microphone, provider or credential.
@MainActor
public final class TranscriptReplayEngine: DictationEngine {
    public var onPartialTranscript: ((String) -> Void)?
    public var onFailure: ((SpeechInputError) -> Void)?
    private let previews: [String]
    private var task: Task<Void, Never>?
    public init(previews: [String]) { self.previews = previews }
    public func start() async throws {
        task = Task { [weak self] in
            guard let self else { return }
            for text in previews {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }; onPartialTranscript?(text)
            }
        }
    }
    public func finish() async throws -> String { await task?.value; return previews.last ?? "" }
    public func cancel() { task?.cancel(); task = nil }
}
