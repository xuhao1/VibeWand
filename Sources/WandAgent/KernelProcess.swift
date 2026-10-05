import Foundation

/// How to start an agent runtime that speaks the Agent Client Protocol on its standard streams.
public struct KernelLaunch {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var directory: URL
    /// Receives the runtime's diagnostics. Its standard output carries only protocol frames.
    public var log: URL?
    public init(executable: URL, arguments: [String], environment: [String: String], directory: URL, log: URL? = nil) {
        self.executable = executable; self.arguments = arguments; self.environment = environment
        self.directory = directory; self.log = log
    }
}

/// A local program the kernel starts to reach a tool server.
public struct ToolRelay: Equatable {
    public var name: String
    public var command: String
    public var arguments: [String]
}

public enum KernelEvent: Equatable {
    case thought(String)
    case message(String)
    case toolStarted(id: String, name: String)
    case toolEnded(id: String, failed: Bool)
    /// Tokens the conversation occupies after the latest reply, out of what the model's context holds.
    case usage(used: Int, size: Int)

    /// Reads one `session/update` payload. Kinds VibeWand has no use for are dropped.
    static func parse(_ update: JSONValue) -> KernelEvent? {
        switch update["sessionUpdate"]?.string {
        case "agent_message_chunk": return update["content"]?["text"]?.string.map(KernelEvent.message)
        case "agent_thought_chunk": return update["content"]?["text"]?.string.map(KernelEvent.thought)
        case "tool_call":
            guard let id = update["toolCallId"]?.string else { return nil }
            return .toolStarted(id: id, name: update["title"]?.string ?? "")
        case "tool_call_update":
            guard let id = update["toolCallId"]?.string, let status = update["status"]?.string,
                  status == "completed" || status == "failed" else { return nil }
            return .toolEnded(id: id, failed: status == "failed")
        case "usage_update":
            guard let used = update["used"]?.int, let size = update["size"]?.int, size > 0 else { return nil }
            return .usage(used: used, size: size)
        default: return nil
        }
    }
}

/// What a session can be set to, as the runtime advertises it when the session opens.
public struct KernelOptions: Equatable, Sendable {
    public struct Model: Equatable, Sendable, Identifiable {
        public var provider: String, model: String
        /// The provider's and the model's display names.
        public var group: String, name: String
        public var id: String { provider + "/" + model }
    }
    /// Every model of every provider the runtime is set up with.
    public var models: [Model] = []
    /// The reasoning efforts the session's model offers. Empty when it has none to choose from.
    public var efforts: [String] = []

    public init() {}
    init(_ options: JSONValue) {
        for option in options.array ?? [] {
            let choices = option["options"]?.array ?? []
            switch option["category"]?.string {
            case "model":
                for group in choices {
                    for choice in group["options"]?.array ?? [] {
                        // The value is the route itself: a provider and a model, as a JSON pair.
                        guard let pair = choice["value"]?.string.flatMap({ JSONValue(data: Data($0.utf8)) })?.array, pair.count == 2,
                              let provider = pair[0].string, let model = pair[1].string else { continue }
                        models.append(Model(provider: provider, model: model, group: group["name"]?.string ?? provider, name: choice["name"]?.string ?? model))
                    }
                }
            case "thought_level": efforts = choices.compactMap { $0["value"]?.string }
            default: break
            }
        }
    }
}

/// One agent runtime process, driven over the Agent Client Protocol.
/// The runtime is given no file or terminal capability; its only tools are the ones mounted per session.
public final class KernelProcess {
    private let process = Process()
    private let stdin = Pipe()
    private let rpc: LineRPC
    private let lock = NSLock()
    private var listeners: [String: (KernelEvent) -> Void] = [:]
    public var pid: pid_t { process.processIdentifier }
    public var onExit: (() -> Void)?

    public init(_ launch: KernelLaunch) throws {
        // A kernel that dies mid-write must not take the app with it.
        signal(SIGPIPE, SIG_IGN)
        let stdout = Pipe()
        process.executableURL = launch.executable
        process.arguments = launch.arguments
        process.environment = launch.environment
        process.currentDirectoryURL = launch.directory
        process.standardInput = stdin
        process.standardOutput = stdout
        if let log = launch.log {
            FileManager.default.createFile(atPath: log.path, contents: nil)
            process.standardError = (try? FileHandle(forWritingTo: log)) ?? FileHandle.nullDevice
        } else { process.standardError = FileHandle.nullDevice }
        rpc = LineRPC(input: stdout.fileHandleForReading, output: stdin.fileHandleForWriting)
        rpc.onNotification = { [weak self] method, params in
            guard method == "session/update", let session = params["sessionId"]?.string,
                  let update = params["update"], let event = KernelEvent.parse(update) else { return }
            self?.listener(for: session)?(event)
        }
        process.terminationHandler = { [weak self] _ in self?.rpc.close(); self?.onExit?() }
        try process.run()
        rpc.start()
    }

    public func initialize() async throws {
        _ = try await rpc.request("initialize", [
            "protocolVersion": 1,
            "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false],
            "clientInfo": ["name": "vibewand", "version": "1"]
        ])
    }

    /// Opens a session and returns it with what can be chosen for it.
    public func openSession(directory: URL, relay: ToolRelay?) async throws -> (id: String, options: KernelOptions) {
        let servers: [JSONValue] = relay.map { [[
            "name": .string($0.name), "command": .string($0.command),
            "args": .array($0.arguments.map(JSONValue.string)), "env": []
        ]] } ?? []
        let result = try await rpc.request("session/new", ["cwd": .string(directory.path), "mcpServers": .array(servers)])
        guard let session = result["sessionId"]?.string else { throw RPCError(code: 0, message: "The kernel returned no session") }
        return (session, KernelOptions(result["configOptions"] ?? []))
    }

    public func setOption(_ id: String, to value: String, session: String) async throws {
        _ = try await rpc.request("session/set_config_option", ["sessionId": .string(session), "configId": .string(id), "value": .string(value)])
    }

    /// Runs one turn and returns the protocol's stop reason, such as `end_turn` or `cancelled`.
    public func prompt(_ text: String, session: String, events: @escaping (KernelEvent) -> Void) async throws -> String {
        setListener(events, for: session)
        defer { setListener(nil, for: session) }
        let result = try await rpc.request("session/prompt", [
            "sessionId": .string(session), "prompt": [["type": "text", "text": .string(text)]]
        ])
        return result["stopReason"]?.string ?? ""
    }

    public func cancel(session: String) { rpc.notify("session/cancel", ["sessionId": .string(session)]) }

    /// The runtime drains and exits when its input closes; it is terminated if it lingers.
    public func stop() {
        try? stdin.fileHandleForWriting.close()
        let process = self.process
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if process.isRunning { process.terminate() } }
    }

    private func listener(for session: String) -> ((KernelEvent) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return listeners[session]
    }
    private func setListener(_ listener: ((KernelEvent) -> Void)?, for session: String) {
        lock.lock(); defer { lock.unlock() }
        listeners[session] = listener
    }
}
