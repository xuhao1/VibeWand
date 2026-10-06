import Foundation

/// The Omni model as a party to a conversation rather than a transcriber. In one
/// Realtime session it hears a recording or reads a line, calls the tools it
/// was told of, and answers in words it also speaks. Whoever holds the session
/// runs those tools and hands back what they returned. Independent of
/// microphone capture, playback and UI.
@MainActor
public final class QwenRealtimeConversation {
    public enum Event: Equatable {
        /// The next words of the answer.
        case words(String)
        /// The same answer as speech: mono 16-bit PCM at `sampleRate`.
        case sound(Data)
        /// A tool the model wants run. Its result is handed back under `id`.
        case call(id: String, name: String, arguments: String)
    }
    public static let sampleRate = 24_000.0

    private let session = URLSession(configuration: .ephemeral, delegate: SpeechRedirectPolicy(), delegateQueue: nil)
    private var socket: URLSessionWebSocketTask?
    public init() {}
    deinit { session.invalidateAndCancel() }

    /// What the session is set to: the rules it keeps, the functions it may call, each a name, a description
    /// and the JSON Schema of its parameters, and whether it speaks its answers or only writes them. `voice`
    /// names the voice it speaks in; nil leaves the model's own.
    public nonisolated static func sessionUpdate(instructions: String, tools: [[String: Any]], spoken: Bool, voice: String? = nil) -> [String: Any] {
        var session: [String: Any] = [
            "modalities": spoken ? ["text", "audio"] : ["text"], "turn_detection": NSNull(), "instructions": instructions,
            "tools": tools.map { $0.merging(["type": "function"]) { given, _ in given } }
        ]
        if spoken, let voice { session["voice"] = voice }
        return ["type": "session.update", "session": session]
    }

    public func open(configuration: SpeechConfiguration, apiKey: String, instructions: String, tools: [[String: Any]], spoken: Bool,
                     voice: String? = nil) async throws {
        close(); try configuration.validate()
        var request = URLRequest(url: try configuration.apiURL()); request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request); self.socket = socket; socket.resume()
        do {
            try await cancellable(socket) {
                try await SpeechAPIClient.waitFor("session.created", socket: socket)
                try await SpeechAPIClient.send(Self.sessionUpdate(instructions: instructions, tools: tools, spoken: spoken, voice: voice), socket: socket)
                try await SpeechAPIClient.waitFor("session.updated", socket: socket)
            }
        } catch {
            // A key the service refused is told apart from a service that could not be reached: asking again will not help.
            if let status = (socket.response as? HTTPURLResponse)?.statusCode, status == 401 || status == 403 { throw SpeechInputError.http(status) }
            throw error
        }
    }
    /// A task that is cancelled while it waits on the session stops waiting: the session is closed under it.
    private func cancellable<Value>(_ socket: URLSessionWebSocketTask, _ work: () async throws -> Value) async throws -> Value {
        try await withTaskCancellationHandler(operation: work, onCancel: { socket.cancel(with: .goingAway, reason: nil) })
    }

    /// The user's turn, as they spoke it.
    public func hear(_ audio: SpeechAudio) async throws {
        for offset in stride(from: 0, to: audio.pcm.count, by: 16_000) {
            try await send(["type": "input_audio_buffer.append",
                            "audio": audio.pcm.subdata(in: offset..<min(offset + 16_000, audio.pcm.count)).base64EncodedString()])
        }
        try await send(["type": "input_audio_buffer.commit"])
    }
    /// A line of the conversation in writing: the user's, or one the model said earlier.
    public func add(_ text: String, fromModel: Bool = false) async throws {
        try await send(["type": "conversation.item.create", "item": ["type": "message", "role": fromModel ? "assistant" : "user",
            "content": [["type": fromModel ? "text" : "input_text", "text": text]]]])
    }
    /// What a tool the model called returned.
    public func answer(call id: String, with output: String) async throws {
        try await send(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": id, "output": output]])
    }

    /// Has the model take its turn and reports it as it comes. Returns the tokens the conversation now holds
    /// and the ones this turn produced.
    public func respond(_ event: (Event) -> Void) async throws -> (input: Int, output: Int) {
        guard let socket else { throw SpeechInputError.protocolRejected }
        try await send(["type": "response.create"])
        return try await cancellable(socket) {
            while true {
                let message = try await SpeechAPIClient.receive(socket)
                switch message["type"] as? String {
                case "response.audio_transcript.delta", "response.text.delta", "response.output_audio_transcript.delta", "response.output_text.delta":
                    if let words = message["delta"] as? String, !words.isEmpty { event(.words(words)) }
                case "response.audio.delta", "response.output_audio.delta":
                    if let sound = (message["delta"] as? String).flatMap({ Data(base64Encoded: $0) }) { event(.sound(sound)) }
                case "response.function_call_arguments.done":
                    guard let id = message["call_id"] as? String, let name = message["name"] as? String else { throw SpeechInputError.protocolRejected }
                    event(.call(id: id, name: name, arguments: message["arguments"] as? String ?? "{}"))
                case "response.done":
                    let response = message["response"] as? [String: Any]
                    guard response?["status"] as? String == "completed" else { throw SpeechInputError.protocolRejected }
                    let usage = response?["usage"] as? [String: Any]
                    return (usage?["input_tokens"] as? Int ?? 0, usage?["output_tokens"] as? Int ?? 0)
                default: break
                }
            }
        }
    }

    public func close() { socket?.cancel(with: .normalClosure, reason: nil); socket = nil }

    private func send(_ event: [String: Any]) async throws {
        guard let socket else { throw SpeechInputError.protocolRejected }
        try await SpeechAPIClient.send(event, socket: socket)
    }
}
