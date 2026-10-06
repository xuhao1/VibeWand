import Foundation
import Network

/// A model VibeWand serves to its own kernel. It listens on this Mac only,
/// speaks the part of `POST …/chat/completions` a harness uses, and hands each
/// request to `answer`, which writes the reply as it is produced. A harness
/// reaches it like any other service, through a `ModelRoute`; only a caller
/// that presents `key` is answered.
public final class ModelEndpoint: @unchecked Sendable {
    /// Receives the request's JSON body and the reply to write. A reply it leaves open is closed unfinished.
    public typealias Answer = @Sendable (_ request: JSONValue, _ reply: Reply) async -> Void

    /// One reply on its way back, in the order a model produces it. Used from one task.
    public final class Reply: @unchecked Sendable {
        private let connection: NWConnection
        private let id = "chatcmpl-" + UUID().uuidString
        private var started = false, calls = 0
        fileprivate var ended = false
        fileprivate init(_ connection: NWConnection) { self.connection = connection }

        /// The next words of the answer.
        public func words(_ text: String) { chunk(["content": .string(text)]) }
        /// A tool the model wants run.
        public func call(id: String, name: String, arguments: String) {
            chunk(["tool_calls": [["index": .number(Double(calls)), "id": .string(id), "type": "function",
                                   "function": ["name": .string(name), "arguments": .string(arguments)]]]])
            calls += 1
        }
        /// The model's turn is over: for the tools it called, or because it has said its piece.
        public func end(input: Int, output: Int) {
            chunk([:], finish: calls > 0 ? "tool_calls" : "stop")
            let usage: JSONValue = ["prompt_tokens": .number(Double(input)), "completion_tokens": .number(Double(output)),
                                    "total_tokens": .number(Double(input + output))]
            write("data: " + JSONValue.object(["id": .string(id), "object": "chat.completion.chunk", "choices": [], "usage": usage]).text
                  + "\n\ndata: [DONE]\n\n", last: true)
        }
        /// The request could not be served. Once the reply has begun, all that is left is to break it off.
        public func fail(_ status: Int, _ message: String) {
            guard !started else { ended = true; connection.cancel(); return }
            let body = JSONValue.object(["error": ["message": .string(message), "type": "invalid_request_error"]]).text
            write("HTTP/1.1 \(status) Error\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body, last: true)
        }

        private func chunk(_ delta: JSONValue, finish: JSONValue = .null) {
            var text = ""
            if !started {
                started = true
                text = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            }
            write(text + "data: " + JSONValue.object(["id": .string(id), "object": "chat.completion.chunk",
                "choices": [["index": 0, "delta": delta, "finish_reason": finish]]]).text + "\n\n")
        }
        private func write(_ text: String, last: Bool = false) {
            guard !ended else { return }
            ended = last
            connection.send(content: Data(text.utf8), completion: .contentProcessed { [connection] _ in if last { connection.cancel() } })
        }
    }

    /// What a caller must present as its bearer credential.
    public let key = (0..<4).map { _ in String(UInt64.random(in: 0...UInt64.max), radix: 36) }.joined()
    public private(set) var port: UInt16 = 0
    public var baseURL: String { "http://127.0.0.1:\(port)/v1" }
    private let listener: NWListener
    private let queue = DispatchQueue(label: "vibewand.model-endpoint")
    private let answer: Answer

    public static func open(answer: @escaping Answer) async throws -> ModelEndpoint {
        let endpoint = try ModelEndpoint(answer: answer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            endpoint.listener.stateUpdateHandler = { [listener = endpoint.listener] state in
                switch state {
                case .ready: listener.stateUpdateHandler = nil; continuation.resume()
                case .failed(let error): listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            endpoint.listener.start(queue: endpoint.queue)
        }
        endpoint.port = endpoint.listener.port?.rawValue ?? 0
        return endpoint
    }
    private init(answer: @escaping Answer) throws {
        self.answer = answer
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.read(connection, Data())
        }
    }
    public func close() { listener.cancel() }

    /// Reads one request: its head, then as many bytes as the head announces.
    private func read(_ connection: NWConnection, _ received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, _, error in
            guard let self, let data, !data.isEmpty, error == nil else { connection.cancel(); return }
            let received = received + data
            guard let gap = received.range(of: Data("\r\n\r\n".utf8)) else { self.read(connection, received); return }
            let head = String(decoding: received[..<gap.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            var fields: [String: String] = [:]
            for line in head.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                fields[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let request = head[0].split(separator: " "), reply = Reply(connection)
            // Whoever does not hold the key learns nothing more, and no body of theirs is read.
            guard fields["authorization"] == "Bearer \(self.key)" else { reply.fail(401, "Unauthorized"); return }
            guard request.count > 1, request[0] == "POST", request[1].hasSuffix("/chat/completions"),
                  let length = fields["content-length"].flatMap(Int.init) else { reply.fail(404, "Only chat completions are served here."); return }
            let body = received[gap.upperBound...]
            guard body.count >= length else { self.read(connection, received); return }
            guard let payload = JSONValue(data: Data(body.prefix(length))) else { reply.fail(400, "The request is not JSON."); return }
            let task = Task { [answer = self.answer] in
                await answer(payload, reply)
                if !reply.ended { reply.fail(500, "No answer.") }
            }
            // The caller hanging up is how a request is cancelled.
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, complete, error in
                if complete || error != nil { task.cancel() }
            }
        }
    }
}
