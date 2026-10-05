import Foundation

/// The coordinator's reasoning loop behind a narrow seam: it is handed an
/// instruction and a way to call tools, and reports why it stopped.
public protocol CommandKernel: AnyObject {
    /// Runs one instruction to the end of its turn and returns the stop reason,
    /// `end_turn` or `cancelled`. Tool calls arrive through `tools` while it runs.
    func run(_ prompt: String, tools: @escaping ToolSocket.Call, events: @escaping (KernelEvent) -> Void) async throws -> String
    func cancel()
    func shutdown()
}

/// A running kernel process holding one conversation, with the tools mounted.
/// Later instructions continue the same conversation, so "the next one" has something to refer to.
public final class KernelSession: CommandKernel {
    private let kernel: KernelProcess
    private let socket: ToolSocket
    private let session: String
    private let current: CallBox
    /// The process went away; the session cannot be used again.
    public var onExit: (() -> Void)? {
        get { kernel.onExit }
        set { kernel.onExit = newValue }
    }

    public static func open(_ launch: KernelLaunch, tools: [ToolDefinition] = ToolCatalog.all) async throws -> KernelSession {
        let current = CallBox()
        let path = NSTemporaryDirectory() + "vibewand-\(getpid())-\(UInt16.random(in: 0...UInt16.max)).sock"
        let socket = try ToolSocket(path: path, tools: tools) { name, arguments in
            guard let call = current.value else { return .failure("No task is running.") }
            return await call(name, arguments)
        }
        do {
            let kernel = try KernelProcess(launch)
            socket.admits = { ProcessTree.descends($0, from: kernel.pid) }
            do {
                try await kernel.initialize()
                let session = try await kernel.openSession(directory: launch.directory, relay: socket.relay)
                return KernelSession(kernel: kernel, socket: socket, session: session, current: current)
            } catch { kernel.stop(); throw error }
        } catch { socket.close(); throw error }
    }

    private init(kernel: KernelProcess, socket: ToolSocket, session: String, current: CallBox) {
        self.kernel = kernel; self.socket = socket; self.session = session; self.current = current
    }

    public func run(_ prompt: String, tools: @escaping ToolSocket.Call, events: @escaping (KernelEvent) -> Void) async throws -> String {
        current.value = tools
        defer { current.value = nil }
        return try await kernel.prompt(prompt, session: session, events: events)
    }
    public func cancel() { kernel.cancel(session: session) }
    public func shutdown() { kernel.stop(); socket.close() }
}

private final class CallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ToolSocket.Call?
    var value: ToolSocket.Call? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

/// Replays a fixed list of tool calls. `swift test` drives the gateway and the
/// app's command flow with it; no model and no process is involved.
public final class ScriptedKernel: CommandKernel {
    public var script: [(tool: String, arguments: JSONValue)]
    public private(set) var prompts: [String] = []
    public private(set) var outcomes: [ToolOutcome] = []
    private var cancelled = false

    public init(_ script: [(tool: String, arguments: JSONValue)] = []) { self.script = script }

    public func run(_ prompt: String, tools: @escaping ToolSocket.Call, events: @escaping (KernelEvent) -> Void) async throws -> String {
        prompts.append(prompt); cancelled = false
        for (index, step) in script.enumerated() where !cancelled {
            events(.toolStarted(id: "\(index)", name: step.tool))
            let outcome = await tools(step.tool, step.arguments)
            outcomes.append(outcome)
            events(.toolEnded(id: "\(index)", failed: outcome.isError))
        }
        return cancelled ? "cancelled" : "end_turn"
    }
    public func cancel() { cancelled = true }
    public func shutdown() {}
}
