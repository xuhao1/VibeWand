import AppKit
import SpeechInput
import WandAgent

/// Command mode from key-down to the last line on the overlay. It listens,
/// hands the words to the kernel, shows what is happening, asks when a key is
/// needed, and can be stopped at any point. The kernel only proposes: what the
/// overlay reports as done is read from the gateway, not from the model's last words.
@MainActor
final class CommandController {
    enum Failure: Error { case kernelMissing, modelMissing }
    let settings: CommandSettings
    let tools: CommandTools
    private let voice: VoiceInputController
    /// Starts a kernel. Tests substitute a scripted one.
    var openKernel: (() async throws -> any CommandKernel)?
    var onChange: (() -> Void)?
    private(set) var hud = CommandHUDSnapshot() { didSet { if hud != oldValue { onChange?() } } }

    private var kernel: (any CommandKernel)?
    private var opening: Task<any CommandKernel, Error>?
    private var gateway: Gateway?
    private var turn: Task<Void, Never>?
    /// Bumped by every new instruction and every stop; late results from an older one are dropped.
    private var generation = 0
    private var runningTurn: Int?
    private var answer: CheckedContinuation<Int?, Never>?
    private var instruction = ""
    private var lastMessage = ""
    /// Context the conversation occupies and what the model's holds, as the kernel last reported it.
    private(set) var usage: (used: Int, size: Int)?
    /// Instructions the conversation in the kernel has taken. 0 means the next one opens a new conversation.
    private(set) var turns = 0
    private var steps = 0
    private var timer: Timer?
    private var idle: Timer?
    private var limit: Timer?
    /// Holds the task records and the kernel's own home.
    let support: URL
    private var pruned = false

    init(settings: CommandSettings, tools: CommandTools, voice: VoiceInputController, support: URL = CommandController.applicationSupport) {
        self.settings = settings; self.tools = tools; self.voice = voice; self.support = support
        tools.ask = { [weak self] in await self?.ask($0) }
        voice.onCommandTranscript = { [weak self] in self?.heard($0) }
    }

    // MARK: The command key

    func begin() {
        guard settings.enabled else {
            show(.attention, L10n.tr("命令模式未开启，可在设置中打开", "Command mode is off. Turn it on in Settings."), for: 3); return
        }
        guard openKernel != nil || settings.usable else { show(.attention, Self.describe(Failure.modelMissing), for: 4); return }
        // Speaking again interrupts at once, before the new words are known.
        halt()
        tools.captureSource()
        voice.beginCommand()
        steps = 0
        hud = CommandHUDSnapshot(phase: .listening, status: L10n.tr("命令 · 正在听", "Command · listening"), detail: detail())
        // The kernel starts while the user is still speaking.
        warm()
    }
    func end() { if hud.phase == .listening { voice.end() } }
    func cancelCapture() {
        guard hud.phase == .listening else { return }
        voice.cancel(); hud = CommandHUDSnapshot()
    }

    /// Follows the recogniser while the key is held.
    func voiceChanged() {
        guard hud.phase == .listening else { return }
        switch voice.state {
        case .failed(let error): show(.attention, error.displayMessage, for: 3)
        // Released before recording began.
        case .idle: hud = CommandHUDSnapshot()
        case .transcribing: hud.status = L10n.tr("命令 · 识别中", "Command · transcribing")
        default: hud.text = voice.liveTranscript
        }
    }

    private func heard(_ text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hud.phase == .listening, !words.isEmpty else { hud = CommandHUDSnapshot(); return }
        run(words)
    }

    // MARK: One instruction

    func run(_ words: String) {
        // Whatever was running or being asked gives way to the new instruction.
        halt()
        let token = generation, previous = turn
        instruction = words; lastMessage = ""; steps = 0
        hud = CommandHUDSnapshot(phase: .working, status: L10n.tr("命令 · 正在理解", "Command · thinking"), text: words, detail: detail())
        limit = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.timeLimit), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, token == self.generation else { return }
                self.halt()
                self.show(.attention, L10n.tr("用时过长，已停止", "Stopped: this took too long"), for: 6)
            }
        }
        // The kernel takes one turn at a time; an interrupted one settles before the next begins.
        turn = Task { [weak self] in
            await previous?.value
            await self?.execute(words, token)
        }
    }

    private func execute(_ words: String, _ token: Int) async {
        guard token == generation else { return }
        defer { if runningTurn == token { runningTurn = nil }; armIdle() }
        var journal: TaskJournal?
        do {
            let kernel = try await ready()
            guard token == generation else { return }
            turns += 1
            let records = support.appendingPathComponent("tasks")
            if !pruned { pruned = true; TaskJournal.clear(root: records, olderThan: 14) }
            journal = try? TaskJournal(root: records)
            journal?.record("instruction", ["text": .string(words), "app": .string(tools.source?.name ?? ""),
                                            "model": .string(settings.model.model), "turn": .number(Double(turns))])
            let gateway = Gateway(host: tools, permission: settings.permission, stepLimit: settings.stepLimit, journal: journal)
            self.gateway = gateway; runningTurn = token
            let prompt = CoordinatorPrompt.task(words, frontApp: tools.source?.name ?? "", window: tools.source?.window ?? "")
            let reason = try await kernel.run(prompt, tools: { await gateway.call($0, $1) }) { [weak self, journal] event in
                journal?.note(event)
                Task { @MainActor in self?.note(event, token) }
            }
            journal?.settle()
            let ending = await gateway.ending, unverified = await gateway.unverified
            let result = outcome(ending, unverified: !unverified.isEmpty)
            journal?.record("end", ["reason": .string(reason), "finished": .bool(result.phase == .done), "said": .string(result.text),
                                    "unverified": .array(unverified.map(JSONValue.string))])
            guard token == generation else { return }
            limit?.invalidate(); limit = nil
            show(result.phase, result.text, for: result.phase == .done ? 5 : 10, detail: detail(ended: true))
            // A conversation the user wants no memory of, or one near the end of its window, is not carried on.
            if settings.historyMinutes == 0 || usage.map({ $0.used * 5 >= $0.size * 4 }) == true { shutdownKernel() }
        } catch {
            journal?.settle()
            journal?.record("end", ["reason": "failed", "finished": false, "said": .string(explain(error))])
            guard token == generation else { return }
            limit?.invalidate(); limit = nil
            // A kernel that failed is not reused.
            shutdownKernel()
            show(.attention, explain(error), for: 8)
        }
    }

    private func note(_ event: KernelEvent, _ token: Int) {
        guard token == generation else { return }
        switch event {
        case .message(let text): lastMessage += text
        case .toolStarted(_, let name):
            steps += 1
            guard hud.phase == .working else { return }
            hud.status = L10n.tr("命令 · ", "Command · ") + Self.caption(name); hud.detail = detail()
        case .usage(let used, let size):
            usage = (used, size)
            if hud.capturesControls { hud.detail = detail() }
        default: break
        }
    }

    private func outcome(_ ending: Gateway.Ending?, unverified: Bool) -> (phase: CommandHUDSnapshot.Phase, text: String) {
        switch ending {
        case .finished(let summary): return (.done, summary + (unverified ? L10n.tr("（结果未能核对）", " (result not verified)") : ""))
        case .needsUser(let reason): return (.attention, reason)
        case nil:
            // The model stopped without saying how it ended; its last words are all there is.
            let said = lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            return (.attention, said.isEmpty ? L10n.tr("没有得到结果", "No result") : String(said.prefix(160)))
        }
    }

    /// The line under a command: which model is acting, how full its context is, how far it has got and how much it asks.
    private func detail(ended: Bool = false) -> String {
        var parts = [settings.model.model]
        if let usage {
            parts.append(L10n.tr("上下文 ", "context ") + "\(Self.tokens(usage.used))/\(Self.tokens(usage.size)) · \(usage.used * 100 / usage.size)%")
        } else if turns == 0 { parts.append(L10n.tr("新对话", "new conversation")) }
        if steps > 0 { parts.append(ended ? L10n.tr("\(steps) 步", steps == 1 ? "1 step" : "\(steps) steps") : L10n.tr("第 \(steps) 步", "step \(steps)")) }
        if !ended { parts.append(settings.permission.title) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    nonisolated static func tokens(_ count: Int) -> String {
        count < 1_000 ? "\(count)" : count < 1_000_000 ? String(format: "%.1fk", Double(count) / 1_000) : String(format: "%.2fM", Double(count) / 1_000_000)
    }

    // MARK: Questions and stop

    private func ask(_ question: CommandQuestion) async -> Int? {
        guard hud.phase == .working else { return nil }
        let token = generation
        switch question {
        case .choose(let text, let options):
            hud = CommandHUDSnapshot(phase: .choosing, status: L10n.tr("命令 · 请选择", "Command · choose"), text: text, options: options, detail: detail())
        case .confirm(let text):
            hud = CommandHUDSnapshot(phase: .confirming, status: L10n.tr("命令 · 请确认", "Command · confirm"), text: text, detail: detail())
        }
        // Shorter than the kernel's own limit on a tool call, so an unanswered question ends as a refusal.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.resolve(nil) } }
        let chosen = await withCheckedContinuation { answer = $0 }
        guard token == generation else { return nil }
        hud = CommandHUDSnapshot(phase: .working, status: L10n.tr("命令 · 继续", "Command · continuing"), text: instruction, detail: detail())
        return chosen
    }
    private func resolve(_ value: Int?) {
        timer?.invalidate(); timer = nil
        answer?.resume(returning: value); answer = nil
    }
    func move(_ direction: Int) {
        guard hud.phase == .choosing else { return }
        hud.selection = min(hud.options.count - 1, max(0, hud.selection + direction))
    }
    func confirm() {
        if hud.phase == .choosing { resolve(hud.selection) } else if hud.phase == .confirming { resolve(0) }
    }

    /// Stop: nothing further reaches the desktop and the kernel's turn is interrupted.
    func stop() {
        guard hud.active else { return }
        if hud.phase == .listening { voice.cancel() }
        halt()
        show(.attention, L10n.tr("已停止", "Stopped"), for: 1.5)
    }
    private func halt() {
        generation += 1
        resolve(nil)
        if let gateway { Task { await gateway.stop() } }
        if runningTurn != nil { kernel?.cancel() }
        gateway = nil
        limit?.invalidate(); limit = nil
    }

    private func show(_ phase: CommandHUDSnapshot.Phase, _ text: String, for seconds: TimeInterval, detail: String = "") {
        hud = CommandHUDSnapshot(phase: phase, status: phase == .done ? L10n.tr("命令 · 完成", "Command · done") : L10n.tr("命令", "Command"),
                                 text: text, detail: detail)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hud = CommandHUDSnapshot() }
        }
    }

    // MARK: The kernel

    private func ready() async throws -> any CommandKernel {
        if let kernel { return kernel }
        warm()
        guard let opening else { throw Failure.kernelMissing }
        return try await opening.value
    }
    private func warm() {
        armIdle()
        guard kernel == nil, opening == nil else { return }
        let open = openKernel ?? { [weak self] in
            guard let self else { throw Failure.kernelMissing }
            return try await self.openBundledKernel()
        }
        opening = Task { [weak self] in
            defer { self?.opening = nil }
            let kernel = try await open()
            self?.kernel = kernel
            return kernel
        }
    }
    private func openBundledKernel() async throws -> any CommandKernel {
        guard let install = Self.install() else { throw Failure.kernelMissing }
        guard let route = await settings.route() else { throw Failure.modelMissing }
        // Conversations are never resumed across starts, so the previous one's log has no further use.
        let home = support.appendingPathComponent("kernel")
        try? FileManager.default.removeItem(at: home.appendingPathComponent("sessions"))
        let session = try await KernelSession.open(try install.launch(home: home, route: route, instructions: settings.instructions))
        session.onExit = { [weak self, weak session] in
            Task { @MainActor in if let session, self?.kernel === session { self?.forget() } }
        }
        return session
    }
    /// Keeps the conversation for follow-ups such as "not that one", then lets the process go.
    private func armIdle() {
        idle?.invalidate()
        idle = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(1, settings.historyMinutes) * 60), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdownKernel() }
        }
    }
    /// Ends the conversation: the next instruction starts a fresh kernel. Also called when a setting changes.
    func shutdownKernel() {
        idle?.invalidate(); idle = nil
        kernel?.shutdown(); forget()
        tools.shutdown()
    }
    private func forget() { kernel = nil; usage = nil; turns = 0 }

    /// Starts a kernel on the model as it is set and asks it for one word, so Settings can check the address,
    /// key and model together. Returns how long it took and the context the kernel reports, or what went wrong.
    func probe() async -> (ok: Bool, detail: String) {
        halt(); shutdownKernel()
        let previous = turn
        let check = Task { [weak self] () -> (ok: Bool, detail: String) in
            await previous?.value
            guard let self else { return (false, "") }
            defer { self.shutdownKernel() }
            do {
                let started = Date(), kernel = try await self.ready()
                _ = try await kernel.run("Reply with the single word: ok", tools: { _, _ in .failure("No tool is available in this check.") }) { [weak self] event in
                    Task { @MainActor in if case .usage(let used, let size) = event { self?.usage = (used, size) } }
                }
                let took = String(format: L10n.tr("模型已回答，用时 %.1f 秒", "The model answered in %.1f s"), Date().timeIntervalSince(started))
                return (true, took + (self.usage.map { L10n.tr("；内核按 ", "; the kernel takes its context as ") + Self.tokens($0.size) + L10n.tr(" 的上下文计算", "") } ?? ""))
            } catch { return (false, self.explain(error)) }
        }
        turn = Task { _ = await check.value }
        return await check.value
    }

    /// The records of recent instructions, newest first.
    func history() -> [TaskRecord] { TaskJournal.recent(root: support.appendingPathComponent("tasks")) }

    /// Removes the task records and what the kernel wrote. The profile is reinstalled on the next start.
    func clearRecords() {
        shutdownKernel()
        for name in ["tasks", "kernel"] { try? FileManager.default.removeItem(at: support.appendingPathComponent(name)) }
    }

    nonisolated static let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VibeWand")

    static func install() -> KernelInstall? {
        if let resources = Bundle.main.resourceURL, let bundled = KernelInstall(resources: resources) { return bundled }
        // A direct SwiftPM run has no bundle: take a launcher from the environment and the profile from the checkout.
        guard let launcher = ProcessInfo.processInfo.environment["VIBEWAND_KERNEL"] else { return nil }
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return KernelInstall(command: [launcher], profile: checkout.appendingPathComponent("kernel/profile"))
    }

    static func caption(_ tool: String) -> String {
        switch tool.components(separatedBy: "__").last ?? tool {
        case "list_targets": return L10n.tr("查看应用", "checking apps")
        case "find_sessions": return L10n.tr("查找会话", "finding chats")
        case "open_session": return L10n.tr("打开会话", "opening the chat")
        case "search_in_app": return L10n.tr("打开搜索", "opening search")
        case "activate_app": return L10n.tr("切换应用", "switching apps")
        case "ui_snapshot": return L10n.tr("读取界面", "reading the window")
        case "ui_type": return L10n.tr("输入文字", "typing")
        case "ui_press", "ui_key", "ui_menu": return L10n.tr("操作界面", "operating the window")
        default: return L10n.tr("处理中", "working")
        }
    }

    /// What went wrong, for the user. A model setting the kernel refused at start is named only in its log.
    private func explain(_ error: Error) -> String {
        guard let refused = error as? RPCError, refused.message.contains("no adapter registered"),
              let log = try? String(contentsOf: support.appendingPathComponent("kernel/logs/kernel.log"), encoding: .utf8),
              let line = log.split(separator: "\n").first(where: { $0.contains("$.providers.vibewand") }) else { return Self.describe(error) }
        let reason = line.replacingOccurrences(of: "$.providers.vibewand.", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        return L10n.tr("内核没有接受这套模型配置：", "The kernel refused these model settings: ") + reason.prefix(240)
    }
    static func describe(_ error: Error) -> String {
        switch error {
        case Failure.kernelMissing: return L10n.tr("此版本未包含命令内核", "This build does not include the command kernel")
        case Failure.modelMissing: return L10n.tr("请先在设置的命令模式中选好模型并保存密钥", "Choose a model and save its key under Command mode in Settings first.")
        case let error as RPCError where error != .closed: return L10n.tr("模型服务出错：", "The model service failed: ") + brief(error.message)
        default: return L10n.tr("命令内核未能完成，请重试", "The command kernel could not finish. Try again.")
        }
    }
    /// The kernel wraps what the service answered; the user needs the service's own words, and few of them.
    nonisolated static func brief(_ message: String) -> String {
        var text = message
        for prefix in ["Internal error: ", "turn failed: "] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        // "401: {"message": "…", …}" keeps its status and the message inside.
        if let brace = text.firstIndex(of: "{"), let said = JSONValue(data: Data(text[brace...].utf8)) {
            let inner = said["message"]?.string ?? said["error"]?["message"]?.string ?? said["error"]?.string
            if let inner { text = text[..<brace] + inner }
        }
        return String(text.prefix(200))
    }
}
