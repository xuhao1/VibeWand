import AppKit
import SpeechInput
import WandAgent

/// Command mode from key-down to the last line on the overlay. It listens,
/// hands the words to the kernel, shows what is happening, asks when a key is
/// needed, and can be stopped at any point. The kernel only proposes: what the
/// overlay reports as done is read from the gateway, not from the model's last words.
@MainActor
final class CommandController {
    enum Failure: Error { case kernelMissing, keyMissing }
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
    private var timer: Timer?
    private var idle: Timer?
    private var limit: Timer?
    /// One instruction may act for this long, questions included, before it is stopped.
    static let timeLimit: TimeInterval = 120
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
        guard openKernel != nil || settings.keySaved else {
            show(.attention, L10n.tr("请先在设置的命令模式中保存模型密钥", "Save a model key under Command mode in Settings first."), for: 4); return
        }
        // Speaking again interrupts at once, before the new words are known.
        halt()
        tools.captureSource()
        voice.beginCommand()
        hud = CommandHUDSnapshot(phase: .listening, status: L10n.tr("命令 · 正在听", "Command · listening"))
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
        instruction = words; lastMessage = ""
        hud = CommandHUDSnapshot(phase: .working, status: L10n.tr("命令 · 正在理解", "Command · thinking"), text: words)
        limit = Timer.scheduledTimer(withTimeInterval: Self.timeLimit, repeats: false) { [weak self] _ in
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
        do {
            let kernel = try await ready()
            guard token == generation else { return }
            let records = support.appendingPathComponent("tasks")
            if !pruned { pruned = true; TaskJournal.clear(root: records, olderThan: 14) }
            let journal = try? TaskJournal(root: records)
            journal?.record("instruction", ["text": .string(words), "app": .string(tools.source?.name ?? "")])
            let gateway = Gateway(host: tools, journal: journal)
            self.gateway = gateway; runningTurn = token
            let prompt = CoordinatorPrompt.task(words, frontApp: tools.source?.name ?? "", window: tools.source?.window ?? "")
            let reason = try await kernel.run(prompt, tools: { await gateway.call($0, $1) }) { [weak self] event in
                Task { @MainActor in self?.note(event, token) }
            }
            let ending = await gateway.ending, unverified = await gateway.unverified
            journal?.record("end", ["reason": .string(reason), "finished": .bool(ending != nil), "unverified": .array(unverified.map(JSONValue.string))])
            guard token == generation else { return }
            limit?.invalidate(); limit = nil
            conclude(ending, unverified: !unverified.isEmpty)
        } catch {
            guard token == generation else { return }
            limit?.invalidate(); limit = nil
            // A kernel that failed is not reused.
            shutdownKernel()
            show(.attention, Self.describe(error), for: 8)
        }
    }

    private func note(_ event: KernelEvent, _ token: Int) {
        guard token == generation else { return }
        switch event {
        case .message(let text): lastMessage += text
        case .toolStarted(_, let name) where hud.phase == .working:
            hud.status = L10n.tr("命令 · ", "Command · ") + Self.caption(name)
        default: break
        }
    }

    private func conclude(_ ending: Gateway.Ending?, unverified: Bool) {
        switch ending {
        case .finished(let summary):
            show(.done, summary + (unverified ? L10n.tr("（结果未能核对）", " (result not verified)") : ""), for: 5)
        case .needsUser(let reason): show(.attention, reason, for: 10)
        case nil:
            // The model stopped without saying how it ended; its last words are all there is.
            let said = lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            show(.attention, said.isEmpty ? L10n.tr("没有得到结果", "No result") : String(said.prefix(160)), for: 10)
        }
    }

    // MARK: Questions and stop

    private func ask(_ question: CommandQuestion) async -> Int? {
        guard hud.phase == .working else { return nil }
        let token = generation
        switch question {
        case .choose(let text, let options):
            hud = CommandHUDSnapshot(phase: .choosing, status: L10n.tr("命令 · 请选择", "Command · choose"), text: text, options: options)
        case .confirm(let text):
            hud = CommandHUDSnapshot(phase: .confirming, status: L10n.tr("命令 · 请确认", "Command · confirm"), text: text)
        }
        // Shorter than the kernel's own limit on a tool call, so an unanswered question ends as a refusal.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.resolve(nil) } }
        let chosen = await withCheckedContinuation { answer = $0 }
        guard token == generation else { return nil }
        hud = CommandHUDSnapshot(phase: .working, status: L10n.tr("命令 · 继续", "Command · continuing"), text: instruction)
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

    private func show(_ phase: CommandHUDSnapshot.Phase, _ text: String, for seconds: TimeInterval) {
        hud = CommandHUDSnapshot(phase: phase, status: phase == .done ? L10n.tr("命令 · 完成", "Command · done") : L10n.tr("命令", "Command"), text: text)
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
        guard let key = await settings.readKey() else { throw Failure.keyMissing }
        // Conversations are never resumed across starts, so the previous one's log has no further use.
        let home = support.appendingPathComponent("kernel")
        try? FileManager.default.removeItem(at: home.appendingPathComponent("sessions"))
        let session = try await KernelSession.open(try install.launch(home: home, apiKey: key, model: settings.model))
        session.onExit = { [weak self, weak session] in
            Task { @MainActor in if let session, self?.kernel === session { self?.kernel = nil } }
        }
        return session
    }
    /// Keeps the conversation for follow-ups such as "not that one", then lets the process go.
    private func armIdle() {
        idle?.invalidate()
        idle = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.shutdownKernel() } }
    }
    /// Also called when the key, the model or the switch changes: the next instruction starts afresh.
    func shutdownKernel() {
        idle?.invalidate(); idle = nil
        kernel?.shutdown(); kernel = nil
        tools.shutdown()
    }

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

    private static func describe(_ error: Error) -> String {
        switch error {
        case Failure.kernelMissing: return L10n.tr("此版本未包含命令内核", "This build does not include the command kernel")
        case Failure.keyMissing: return L10n.tr("请先在设置的命令模式中保存模型密钥", "Save a model key under Command mode in Settings first.")
        default: return L10n.tr("命令内核未能完成，请重试", "The command kernel could not finish. Try again.")
        }
    }
}
