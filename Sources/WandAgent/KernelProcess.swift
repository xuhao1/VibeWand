import Foundation

/// How to start an agent runtime that speaks the Agent Client Protocol on its standard streams.
public struct KernelLaunch {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var directory: URL
    /// Receives the runtime's diagnostics. Its standard output carries only protocol frames.
    public var log: URL?
    /// A reasoning effort asked for by name. It is set on a conversation whose model offers it and left alone otherwise.
    public var effort: String?
    public init(executable: URL, arguments: [String], environment: [String: String], directory: URL, log: URL? = nil, effort: String? = nil) {
        self.executable = executable; self.arguments = arguments; self.environment = environment
        self.directory = directory; self.log = log; self.effort = effort
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
    /// `input` is what the tool was called with, as the runtime reports it.
    case toolStarted(id: String, name: String, input: JSONValue = .null)
    /// `text` is what the tool answered, pictures left out.
    case toolEnded(id: String, failed: Bool, text: String = "")
    /// Tokens the conversation occupies after the latest reply, out of what the model's context holds.
    case usage(used: Int, size: Int)

    /// Reads one `session/update` payload. Kinds VibeWand has no use for are dropped.
    static func parse(_ update: JSONValue) -> KernelEvent? {
        switch update["sessionUpdate"]?.string {
        case "agent_message_chunk": return update["content"]?["text"]?.string.map(KernelEvent.message)
        case "agent_thought_chunk": return update["content"]?["text"]?.string.map(KernelEvent.thought)
        case "tool_call":
            guard let id = update["toolCallId"]?.string else { return nil }
            return .toolStarted(id: id, name: update["title"]?.string ?? "", input: update["rawInput"] ?? .null)
        case "tool_call_update":
            guard let id = update["toolCallId"]?.string, let status = update["status"]?.string,
                  status == "completed" || status == "failed" else { return nil }
            let said = (update["content"]?.array ?? []).compactMap { $0["content"]?["text"]?.string }
            return .toolEnded(id: id, failed: status == "failed", text: said.joined(separator: "\n"))
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
/// The runtime is given no file or terminal capability of the client's; the tools mounted per session are VibeWand's.
public final class KernelProcess {
    private let process = Process()
    private let stdin = Pipe()
    private let rpc: LineRPC
    private let lock = NSLock()
    private var listeners: [String: (KernelEvent) -> Void] = [:]
    public var pid: pid_t { process.processIdentifier }
    public var onExit: (() -> Void)?
    /// A runtime that has tools of its own asks before one of their calls goes beyond its sandbox: the session
    /// and the call's id, answered with whether to allow it this once. With nobody to ask, the runtime is told
    /// so and fails the call closed.
    public var onPermission: ((_ session: String, _ call: String) async -> Bool)?

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
        rpc.onRequest = { [weak self] method, params, reply in
            guard method == "session/request_permission", let ask = self?.onPermission, let session = params["sessionId"]?.string,
                  let call = params["toolCall"]?["toolCallId"]?.string else { reply(.failure(.methodNotFound)); return }
            Task {
                let wanted = await ask(session, call) ? "allow_once" : "reject_once"
                let option = (params["options"]?.array ?? []).first { $0["kind"]?.string == wanted }?["optionId"]
                reply(.success(["outcome": option.map { ["outcome": "selected", "optionId": $0] } ?? ["outcome": "cancelled"]]))
            }
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
        let result = try await rpc.request("session/new", ["cwd": .string(directory.path), "mcpServers": Self.servers(relay)])
        guard let session = result["sessionId"]?.string else { throw RPCError(code: 0, message: "The kernel returned no session") }
        return (session, KernelOptions(result["configOptions"] ?? []))
    }

    /// Takes up a session an earlier process left in the runtime's store, with its whole conversation.
    /// Fails when the session is gone or another process, such as the runtime's own app, has it open.
    public func resumeSession(_ session: String, directory: URL, relay: ToolRelay?) async throws -> KernelOptions {
        let result = try await rpc.request("session/resume", ["sessionId": .string(session), "cwd": .string(directory.path), "mcpServers": Self.servers(relay)])
        return KernelOptions(result["configOptions"] ?? [])
    }

    private static func servers(_ relay: ToolRelay?) -> JSONValue {
        .array(relay.map { [[
            "name": .string($0.name), "command": .string($0.command),
            "args": .array($0.arguments.map(JSONValue.string)), "env": []
        ]] } ?? [])
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

    /// Asks the runtime to close a session, which is what has it write the conversation out in full: with tools
    /// mounted, a runtime that is only told to exit does not get that far before it has to be stopped. Waits for
    /// the answer, though not for long.
    public func closeSession(_ session: String) async {
        let answered = Locked(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let settle: @Sendable () -> Void = { answered.update { if !$0 { $0 = true; continuation.resume() } } }
            Task { _ = try? await self.rpc.request("session/close", ["sessionId": .string(session)]); settle() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: settle)
        }
    }

    /// The runtime drains and exits when its input closes; it is terminated if it lingers. `done` runs once it has gone.
    public func stop(then done: @escaping () -> Void = {}) {
        let process = self.process, exit = process.terminationHandler, told = Locked(false)
        // The process may go between being given the handler and being asked whether it runs.
        let once = { told.update { if !$0 { $0 = true; done() } } }
        process.terminationHandler = { exit?($0); once() }
        guard process.isRunning else { return once() }
        try? stdin.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if process.isRunning { process.terminate() } }
    }
    /// Stops the runtime and returns once it has gone.
    public func exit() async { await withCheckedContinuation { continuation in stop { continuation.resume() } } }

    private func listener(for session: String) -> ((KernelEvent) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return listeners[session]
    }
    private func setListener(_ listener: ((KernelEvent) -> Void)?, for session: String) {
        lock.lock(); defer { lock.unlock() }
        listeners[session] = listener
    }
}
