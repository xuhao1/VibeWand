import Foundation
import SpeechInput
import WandAgent

/// What one request of the kernel asks of the model, read from its chat-completions form. A Realtime session
/// takes a conversation as spoken and written lines and keeps only the tool calls it made itself, so everything
/// but the instructions, the tools and the latest results is told as lines.
struct ModelExchange: Equatable {
    struct Line: Equatable {
        var fromModel = false
        var text: String
    }
    /// What a tool returned, under the id its call was given.
    struct Result: Equatable {
        var call: String
        var output: String
    }
    var instructions = ""
    /// Each tool as its name, description and the schema of its parameters.
    var tools: [JSONValue] = []
    /// The conversation in order. A tool call is a line too: a record of what was called and what it returned.
    var lines: [Line] = []
    /// What the request ends with when it hands back the results of the model's last calls.
    var results: [Result] = []

    /// A Realtime session drops a connection that is sent much more than this in one piece.
    static let longest = 60_000

    init(_ request: JSONValue) {
        var calls: [String: String] = [:]
        for message in request["messages"]?.array ?? [] {
            let text = Self.text(message["content"])
            switch message["role"]?.string {
            case "system", "developer": instructions += (instructions.isEmpty ? "" : "\n\n") + text
            case "assistant":
                if !text.isEmpty { lines.append(Line(fromModel: true, text: text)) }
                for call in message["tool_calls"]?.array ?? [] {
                    guard let id = call["id"]?.string, let function = call["function"] else { continue }
                    calls[id] = "\(function["name"]?.string ?? "") \(function["arguments"]?.string ?? "")"
                }
                results = []
            case "tool":
                let id = message["tool_call_id"]?.string ?? "", output = String(text.prefix(Self.longest))
                results.append(Result(call: id, output: output))
                lines.append(Line(text: "(tool record) \(calls[id] ?? "") returned: \(output)"))
            default:
                lines.append(Line(text: text)); results = []
            }
        }
        tools = (request["tools"]?.array ?? []).compactMap { $0["function"] }.map {
            ["name": $0["name"] ?? "", "description": $0["description"] ?? "", "parameters": $0["parameters"] ?? ["type": "object"]]
        }
    }
    private static func text(_ content: JSONValue?) -> String {
        content?.string ?? (content?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
    }
}

/// The voice service's Omni model as command mode's model. It hears the command itself instead of reading a
/// transcript of it, calls the tools, and says its answer. The kernel reaches it as one more model route,
/// served by this app: each request the kernel makes there is carried out in a Realtime session of the voice
/// service, with the user's recording put before the message that holds its transcript. Either harness runs
/// on it unchanged.
@MainActor
final class ListeningModel {
    /// Tokens the model was seen to take in one conversation. The service does not say what it holds.
    static let contextWindow = 120_000
    /// A session that has called tools, the calls whose results it is waiting for, and the voice it was opened in.
    private struct Live {
        var conversation: QwenRealtimeConversation
        var pending: Set<String> = []
        var voice = ""
    }
    private var live: Live?
    /// The command being run: the message the kernel sends for it, and the recording that message was recognised in.
    private var heard: (prompt: String, audio: SpeechAudio)?
    private var endpoint: ModelEndpoint?
    /// The voice service's settings and key, as they are now.
    private let service: () async throws -> (SpeechConfiguration, String)
    /// Whether the model is to speak its answers, and where the speech goes as it arrives.
    var speaks: () -> Bool = { false }
    /// The voice it speaks in, by the service's name for it. Empty leaves the model's own.
    var voice: () -> String = { QwenRealtimeConversation.voice }
    var onSound: ((Data) -> Void)?

    init(service: @escaping () async throws -> (SpeechConfiguration, String)) { self.service = service }

    /// The route a kernel is started on, to the voice service's `model`. The address is opened once and kept
    /// for as long as the app runs.
    func route(model: String) async throws -> ModelRoute {
        if endpoint == nil {
            endpoint = try await ModelEndpoint.open { [weak self] request, reply in await self?.answer(request, reply) }
        }
        return ModelRoute(wire: .openAIChat, baseURL: endpoint!.baseURL, model: model, key: endpoint!.key, contextWindow: Self.contextWindow)
    }

    /// Has the model say a line of VibeWand's own, a question or a result, in the voice it answers in. It is
    /// asked in a session of its own, so that the line is said and not acted on.
    func say(_ line: String, sound: (Data) -> Void) async throws {
        let (configuration, key) = try await service()
        try await QwenRealtimeConversation.say(line, voice: voice().isEmpty ? nil : voice(), configuration: configuration, apiKey: key, sound: sound)
    }
    /// The same line as the voice service's synthesis reads it in `voice`, for when a model with no voice of
    /// its own did the work.
    func read(_ line: String, voice: String) async throws -> Data {
        let (configuration, key) = try await service()
        return try await QwenSpeechSynthesis.read(line, voice: voice, configuration: configuration, apiKey: key)
    }

    /// Says which message of the kernel's the recording belongs to. The model hears it and reads the message.
    func hear(_ prompt: String, _ audio: SpeechAudio) { heard = (prompt, audio) }
    /// The command is over, or was stopped: nothing more of it is said, and its session is let go.
    func settle() { heard = nil; live?.conversation.close(); live = nil }

    private func answer(_ request: JSONValue, _ reply: ModelEndpoint.Reply) async {
        let exchange = ModelExchange(request)
        var session: Live?
        do {
            var held = try await self.session(for: exchange)
            session = held
            let usage = try await held.conversation.respond { event in
                switch event {
                case .words(let text): reply.words(text)
                // A command that was stopped meanwhile says nothing more, and neither does a session whose voice
                // the user has since changed: what it has to say is then said in the new one.
                case .sound(let sound): if heard != nil, held.voice == voice() { onSound?(sound) }
                case .call(let id, let name, let arguments): held.pending.insert(id); reply.call(id: id, name: name, arguments: arguments)
                }
            }
            reply.end(input: usage.input, output: usage.output)
            // With tools to wait for, the session is kept: it knows the calls it made.
            if held.pending.isEmpty { held.conversation.close() } else { live = held }
        } catch {
            // Also where a request the kernel gave up on ends: its session was closed under it.
            session?.conversation.close()
            let refused: Int?
            switch error as? SpeechInputError {
            case .missingAPIKey?: refused = 401
            case .http(let status)?: refused = status
            default: refused = nil
            }
            reply.fail(refused ?? 502, DictationSession.safeError(error).localizedDescription)
        }
    }

    /// The session to answer in: the one that made the calls whose results this request brings, or a new one
    /// that is told the conversation so far.
    private func session(for exchange: ModelExchange) async throws -> Live {
        if let held = live, !exchange.results.isEmpty, Set(exchange.results.map(\.call)) == held.pending {
            live = nil
            do {
                for result in exchange.results { try await held.conversation.answer(call: result.call, with: result.output) }
                return Live(conversation: held.conversation, voice: held.voice)
            } catch { held.conversation.close() }
        }
        live?.conversation.close(); live = nil
        let (configuration, key) = try await service()
        // The message the recording belongs to, when this request is about the command being run.
        let turn = heard.flatMap { heard in exchange.lines.lastIndex { !$0.fromModel && $0.text.contains(heard.prompt) } }
        let conversation = QwenRealtimeConversation(), voice = voice()
        do {
            let vocabulary = configuration.effectiveVocabulary.guidance
            try await conversation.open(configuration: configuration, apiKey: key,
                instructions: exchange.instructions + (vocabulary.isEmpty ? "" : "\n\n" + vocabulary),
                tools: exchange.tools.compactMap { try? JSONSerialization.jsonObject(with: Data($0.text.utf8)) as? [String: Any] },
                spoken: turn != nil && speaks(), voice: voice.isEmpty ? nil : voice)
            for (index, line) in exchange.lines.enumerated() {
                // The recording comes before its message, which keeps the recogniser's reading of it and says
                // when and where it was spoken.
                if index == turn, let heard { try await conversation.hear(heard.audio) }
                try await conversation.add(line.text, fromModel: line.fromModel)
            }
        } catch { conversation.close(); throw error }
        return Live(conversation: conversation, voice: voice)
    }
}
