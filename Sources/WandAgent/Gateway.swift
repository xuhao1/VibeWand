import Foundation

/// How much the user is asked before the coordinator acts.
public enum PermissionMode: String, CaseIterable, Sendable {
    /// Every action that changes something waits for the confirm key.
    case ask
    /// Navigation and typing run; actions that send or destroy wait.
    case risky
    /// Nothing waits.
    case bypass
}

/// What the app does when a tool is called. The app's implementation runs on the main actor.
public protocol ToolHost: AnyObject {
    func perform(_ tool: String, _ arguments: JSONValue) async -> ToolOutcome
    /// Puts a call that needs the user's word on the overlay and waits for their key: every call when `every`
    /// is set, otherwise only one that would send or destroy. nil when this call needs no word.
    func confirm(_ tool: String, _ arguments: JSONValue, every: Bool) async -> Bool?
}

/// The only path from the kernel to the desktop for one instruction. It admits
/// catalogued tools, runs them one at a time, asks the user as their permission
/// mode requires and keeps the record. The kernel proposes; it cannot mark the task done.
public actor Gateway {
    public enum Ending: Equatable, Sendable { case finished(String), needsUser(String) }
    public static let stepLimit = 24

    private let tools: [String: ToolDefinition]
    private let host: ToolHost
    private let permission: PermissionMode
    private let stepLimit: Int
    private let journal: TaskJournal?
    private var steps = 0
    private var stopped = false
    private var tail: Task<ToolOutcome, Never>?
    public private(set) var ending: Ending?
    /// Actions that ran but whose result could not be read back.
    public private(set) var unverified: [String] = []

    public init(tools: [ToolDefinition] = ToolCatalog.all, host: ToolHost, permission: PermissionMode = .risky,
                stepLimit: Int = Gateway.stepLimit, journal: TaskJournal? = nil) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        self.host = host; self.permission = permission; self.stepLimit = stepLimit; self.journal = journal
    }

    /// A model may ask for several tools at once; the desktop takes one action at a time.
    public func call(_ name: String, _ arguments: JSONValue) async -> ToolOutcome {
        let previous = tail
        let task = Task { _ = await previous?.value; return await self.run(name, arguments) }
        tail = task
        return await task.value
    }

    /// The user pressed stop, or spoke a new instruction. Nothing after this reaches the desktop.
    public func stop() { stopped = true }

    private func run(_ name: String, _ arguments: JSONValue) async -> ToolOutcome {
        guard !stopped else { return .failure("The user stopped this task. Do nothing further.") }
        guard ending == nil else { return .failure("The task has already ended.") }
        guard let tool = tools[name] else { return .failure("Unknown tool: \(name).") }
        steps += 1
        guard steps <= stepLimit else { return .failure("Step limit reached. Call need_user and say how far you got.") }
        journal?.record("call", ["tool": .string(name), "arguments": arguments])
        let outcome = await perform(tool, arguments)
        if !outcome.verified { unverified.append(name) }
        // What the tool answered is what the model went on, so the record keeps it; a long listing is cut.
        journal?.record("result", ["tool": .string(name), "ok": .bool(!outcome.isError), "verified": .bool(outcome.verified),
                                   "text": .string(String(outcome.text.prefix(TaskJournal.resultLimit)))])
        return outcome
    }

    private func perform(_ tool: ToolDefinition, _ arguments: JSONValue) async -> ToolOutcome {
        switch tool.name {
        case "finish": ending = .finished(arguments["summary"]?.string ?? ""); return .ok("ok")
        case "need_user": ending = .needsUser(arguments["reason"]?.string ?? ""); return .ok("ok")
        default: break
        }
        if permission != .bypass, tool.effect != .read {
            // A submission is asked about in either asking mode, whatever the host makes of it.
            switch await host.confirm(tool.name, arguments, every: permission == .ask || tool.effect == .submit) {
            case false?:
                journal?.record("declined", ["tool": .string(tool.name)])
                return .failure("The user declined. Do not retry; call need_user or finish.")
            case true?:
                // Stop may have been pressed while the question was on screen.
                guard !stopped else { return .failure("The user stopped this task. Do nothing further.") }
                journal?.record("confirmed", ["tool": .string(tool.name)])
            case nil: break
            }
        }
        return await host.perform(tool.name, arguments)
    }
}
