import Foundation

/// The coordinator's reasoning loop behind a narrow seam: it is handed an
/// instruction and a way to call tools, and reports why it stopped.
public protocol CommandKernel: AnyObject {
    /// The runtime's name for the conversation, once it has been opened or taken up again.
    var session: String? { get }
    /// Runs one instruction to the end of its turn and returns the stop reason,
    /// `end_turn` or `cancelled`. Tool calls arrive through `tools` while it runs.
    func run(_ prompt: String, tools: @escaping ToolSocket.Call, events: @escaping (KernelEvent) -> Void) async throws -> String
    func cancel()
    /// Ends the kernel and returns once it has gone, leaving the conversation in its store for a later one to take up.
    func shutdown() async
}

/// A running kernel process holding one conversation, with the tools mounted.
/// Later instructions continue the same conversation, so "the next one" has something to refer to.
/// A new conversation is opened by the first instruction: a kernel warmed by a key press that led to
/// nothing leaves no empty conversation in the runtime's store.
public final class KernelSession: CommandKernel {
    private let kernel: KernelProcess
    private let socket: ToolSocket
    private let directory: URL
    private let effort: String?
    private let current: Locked<ToolSocket.Call?>
    /// The runtime's own tool calls that have started, by id: what a request for the user's word is about.
    private let calls = Locked<[String: (name: String, input: JSONValue)]>([:])
    public private(set) var session: String?
    /// The models the runtime can serve and the reasoning efforts this conversation's model offers, known once it has opened.
    public private(set) var options = KernelOptions()
    /// Asked before a tool of the runtime's own goes beyond its sandbox. Nobody to ask means no.
    public var approve: ((_ tool: String, _ input: JSONValue) async -> Bool)?
    /// The process went away; the session cannot be used again.
    public var onExit: (() -> Void)? {
        get { kernel.onExit }
        set { kernel.onExit = newValue }
    }

    /// `resume` names a conversation an earlier process left in the runtime's store. When it cannot be taken up,
    /// because the runtime's own app has it open or it is gone, `session` stays nil and the first instruction opens a new one.
    public static func open(_ launch: KernelLaunch, tools: [ToolDefinition] = ToolCatalog.all, resume: String? = nil) async throws -> KernelSession {
        let current = Locked<ToolSocket.Call?>(nil)
        let path = NSTemporaryDirectory() + "vibewand-\(getpid())-\(UInt16.random(in: 0...UInt16.max)).sock"
        let socket = try ToolSocket(path: path, tools: tools) { name, arguments in
            guard let call = current.value else { return .failure("No task is running.") }
            return await call(name, arguments)
        }
        do {
            let kernel = try KernelProcess(launch)
            socket.admits = { ProcessTree.descends($0, from: kernel.pid) }
            do {
                // A runtime that starts but never answers is stopped, which fails the request it left waiting.
                let patience = Task { try await Task.sleep(nanoseconds: 20_000_000_000); kernel.stop() }
                defer { patience.cancel() }
                try await kernel.initialize()
                let opened = KernelSession(kernel: kernel, socket: socket, directory: launch.directory, effort: launch.effort, current: current)
                if let resume, let options = try? await kernel.resumeSession(resume, directory: launch.directory, relay: socket.relay) {
                    opened.session = resume; opened.options = options
                }
                return opened
            } catch { kernel.stop(); throw error }
        } catch { socket.close(); throw error }
    }

    private init(kernel: KernelProcess, socket: ToolSocket, directory: URL, effort: String?, current: Locked<ToolSocket.Call?>) {
        self.kernel = kernel; self.socket = socket; self.directory = directory; self.effort = effort; self.current = current
        kernel.onPermission = { [weak self] _, call in
            guard let self, let approve = self.approve, let asked = self.calls.value[call] else { return false }
            return await approve(asked.name, asked.input)
        }
    }

    public func run(_ prompt: String, tools: @escaping ToolSocket.Call, events: @escaping (KernelEvent) -> Void) async throws -> String {
        current.value = tools
        defer { current.value = nil; calls.value = [:] }
        return try await kernel.prompt(prompt, session: try await opened()) { [calls] event in
            if case .toolStarted(let id, let name, let input) = event { calls.update { $0[id] = (name, input) } }
            events(event)
        }
    }
    private func opened() async throws -> String {
        if let session { return session }
        let fresh = try await kernel.openSession(directory: directory, relay: socket.relay)
        if let effort, fresh.options.efforts.contains(effort) { try await kernel.setOption("reasoning_effort", to: effort, session: fresh.id) }
        session = fresh.id; options = fresh.options
        return fresh.id
    }
    public func cancel() { if let session { kernel.cancel(session: session) } }
    /// Has the runtime write the conversation out and let go of it, and returns once the process has gone. The
    /// tools stay reachable until then.
    public func shutdown() async {
        if let session { await kernel.closeSession(session) }
        await kernel.exit()
        socket.close()
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
    func update(_ change: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; change(&stored) }
}

/// Replays a fixed list of tool calls. `swift test` drives the gateway and the
/// app's command flow with it; no model and no process is involved.
public final class ScriptedKernel: CommandKernel {
    public var script: [(tool: String, arguments: JSONValue)]
    /// Reported once the script has run, as a real kernel says how full its context is after a reply.
    public var usage: (used: Int, size: Int)?
    public private(set) var prompts: [String] = []
    public private(set) var outcomes: [ToolOutcome] = []
    public private(set) var shutdowns = 0
    /// Set by the first instruction, as a real kernel opens its conversation then; or given, for one taken up again.
    public var session: String?
    private var cancelled = false

    public init(_ script: [(tool: String, arguments: JSONValue)] = [], session: String? = nil) { self.script = script; self.session = session }

    public func run(_ prompt: String, tools: @escaping ToolSocket.Call, events: @escaping (KernelEvent) -> Void) async throws -> String {
        prompts.append(prompt); cancelled = false
        if session == nil { session = "scripted" }
        for (index, step) in script.enumerated() where !cancelled {
            // A kernel names a tool by the server that mounted it.
            events(.toolStarted(id: "\(index)", name: TaskJournal.mounted + step.tool, input: step.arguments))
            let outcome = await tools(step.tool, step.arguments)
            outcomes.append(outcome)
            events(.toolEnded(id: "\(index)", failed: outcome.isError))
        }
        if let usage, !cancelled { events(.usage(used: usage.used, size: usage.size)) }
        return cancelled ? "cancelled" : "end_turn"
    }
    public func cancel() { cancelled = true }
    /// The process is gone, and with it its hold on the conversation.
    public func shutdown() async { shutdowns += 1; session = nil }
}
