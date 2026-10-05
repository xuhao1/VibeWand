import Foundation

public struct RPCError: Error, Equatable {
    public var code: Int
    public var message: String
    public init(code: Int, message: String) { self.code = code; self.message = message }
    public static let methodNotFound = RPCError(code: -32601, message: "Method not found")
    public static let closed = RPCError(code: -32000, message: "Connection closed")
}

/// JSON-RPC 2.0 with one message per line. The kernel (Agent Client Protocol),
/// the tool socket (MCP) and Codex's app-server all use this framing.
public final class LineRPC: @unchecked Sendable {
    public typealias Reply = (Result<JSONValue, RPCError>) -> Void
    /// Handlers run on a private queue. A request nobody handles answers "method not found".
    public var onRequest: ((String, JSONValue, @escaping Reply) -> Void)?
    public var onNotification: ((String, JSONValue) -> Void)?
    public var onClose: (() -> Void)?

    private let input: FileHandle, output: FileHandle
    private let queue = DispatchQueue(label: "vibewand.rpc")
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var nextID = 1
    private var closed = false

    public init(input: FileHandle, output: FileHandle) { self.input = input; self.output = output }

    public func start() {
        input.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.queue.async { if data.isEmpty { self.finish() } else { self.receive(data) } }
        }
    }
    public func close() { queue.async { self.finish() } }

    public func request(_ method: String, _ params: JSONValue = [:]) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.closed else { continuation.resume(throwing: RPCError.closed); return }
                let id = self.nextID; self.nextID += 1
                self.pending[id] = continuation
                self.send(["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params])
            }
        }
    }
    public func notify(_ method: String, _ params: JSONValue = [:]) {
        queue.async { self.send(["jsonrpc": "2.0", "method": .string(method), "params": params]) }
    }

    private func send(_ message: JSONValue) {
        guard !closed else { return }
        do { try output.write(contentsOf: Data((message.text + "\n").utf8)) } catch { finish() }
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            // Anything that is not a JSON object on its own line is not ours to interpret.
            if let message = JSONValue(data: line) { dispatch(message) }
        }
    }
    private func dispatch(_ message: JSONValue) {
        let id = message["id"], params = message["params"] ?? [:]
        if let method = message["method"]?.string {
            guard let id else { onNotification?(method, params); return }
            let reply: Reply = { [weak self] result in
                self?.queue.async {
                    switch result {
                    case .success(let value): self?.send(["jsonrpc": "2.0", "id": id, "result": value])
                    case .failure(let error):
                        self?.send(["jsonrpc": "2.0", "id": id,
                                    "error": ["code": .number(Double(error.code)), "message": .string(error.message)]])
                    }
                }
            }
            if let onRequest { onRequest(method, params, reply) } else { reply(.failure(.methodNotFound)) }
        } else if let key = id?.int, let continuation = pending.removeValue(forKey: key) {
            if let error = message["error"] {
                continuation.resume(throwing: RPCError(code: error["code"]?.int ?? 0, message: error["message"]?.string ?? ""))
            } else { continuation.resume(returning: message["result"] ?? .null) }
        }
    }
    private func finish() {
        guard !closed else { return }
        closed = true
        input.readabilityHandler = nil
        pending.values.forEach { $0.resume(throwing: RPCError.closed) }
        pending.removeAll()
        onClose?()
    }
}
