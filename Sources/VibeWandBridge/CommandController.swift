import AppKit
import SpeechInput
import WandAgent

/// Command mode from key-down to the last line on the overlay. It listens,
/// hands the words to the kernel, shows what is happening, asks when a key is
/// needed, and can be stopped at any point. The kernel only proposes: what the
/// overlay reports as done is read from the gateway, not from the model's last words.
@MainActor
final class CommandController {
    enum Failure: Error { case kernelMissing, modelMissing, harnessMissing, busy }
    /// How long the kernel process is kept after the last command. The conversation outlives it.
    static let rest: TimeInterval = 300
    let settings: CommandSettings
    let tools: CommandTools
    private let voice: VoiceInputController
    /// Starts a kernel, taking up the named conversation when it can. Tests substitute a scripted one.
    var openKernel: ((_ resume: String?) async throws -> any CommandKernel)?
    /// Adjusts how the kernel process is started. Live tests hand a key over in its environment.
    var prepare: ((inout KernelLaunch) -> Void)?
    var onChange: (() -> Void)?
    /// Says results and questions aloud. The app provides it; without it command mode is silent.
    var speech: SpeechOutput?
    /// The voice service's model as the command model, for when the user chose it.
    private let listener: ListeningModel
    /// The model said its answer itself during this command.
    private var modelSpoke = false
    /// Whether the running kernel was started on the model that listens.
    private var kernelListens = false
    /// A line of VibeWand's own on its way to being said in that model's voice.
    private var saying: Task<Void, Never>?
    /// Ends the listening once the words have stopped coming. A handset's release does not always arrive,
    /// and the microphone must not stay open until the next press.
    private var quiet: Timer?
    static var quiet: TimeInterval = 4
    private(set) var hud = CommandHUDSnapshot() { didSet { if hud != oldValue { onChange?() } } }

    private var kernel: (any CommandKernel)?
    private var opening: Task<any CommandKernel, Error>?
    /// A kernel that is on its way out. The next one waits for it: a conversation is held by one process at a time.
    private var closing: Task<Void, Never>?
    /// A kernel on a job of VibeWand's own rather than a command, and whether a command has since asked for its place.
    private var errand: (any CommandKernel)?
    private var errandStopped = false
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
    /// Instructions the conversation has taken. 0 means the next one opens a new conversation.
    private(set) var turns = 0
    /// The models the user's harness serves, as its last conversation listed them. Plugin mode only.
    private(set) var catalog: [KernelOptions.Model] = []
    /// What a harness said its version was, kept until its command changes on disk.
    private var versions: [URL: (stamp: Date?, version: String)] = [:]
    /// The harness's own web app, started for the user to read conversations in.
    private var viewer: Process?
    private var steps = 0
    private var timer: Timer?
    private var idle: Timer?
    private var limit: Timer?
    /// Holds the task records and VibeWand's folder for each harness.
    let support: URL
    private var pruned = false
    /// Where the kernel of the mode in force keeps its working folder and diagnostics.
    private var folder: URL { support.appendingPathComponent(settings.kernelMode.folder) }

    init(settings: CommandSettings, tools: CommandTools, voice: VoiceInputController, support: URL = CommandController.applicationSupport) {
        self.settings = settings; self.tools = tools; self.voice = voice; self.support = support
        listener = ListeningModel(service: { [voice] in try await voice.listeningService() })
        settings.listeningModel = { [voice] in voice.listeningModel }
        listener.speaks = { [weak self] in self?.speech != nil && self?.settings.speaks == true }
        listener.voice = { [settings] in settings.voice }
        listener.onSound = { [weak self] sound in
            self?.modelSpoke = true
            self?.speech?.play(sound, sampleRate: QwenRealtimeConversation.sampleRate)
        }
        tools.ask = { [weak self] in await self?.ask($0) }
        tools.voice = { [weak self] in self?.revoice($0) ?? .failure("VibeWand has quit.") }
        voice.onCommandTranscript = { [weak self] in self?.heard($0, $1) }
        // What the last run left of the conversation is shown before the next command takes it up.
        if let kept = carried { turns = kept.turns; usage = kept.usage }
        if settings.sight { InterfaceTools.warm() }
    }

    // MARK: The command key

    func begin() {
        guard settings.enabled else {
            show(.attention, L10n.tr("命令模式未开启，可在设置中打开", "Command mode is off. Turn it on in Settings."), for: 3); return
        }
        guard openKernel != nil || settings.usable else {
            show(.attention, Self.describe(settings.kernelMode == .harness ? Failure.harnessMissing : Failure.modelMissing), for: 4); return
        }
        // Speaking again interrupts at once, before the new words are known.
        halt()
        tools.captureSource()
        voice.beginCommand(listening: settings.listening)
        steps = 0
        // The kernel starts while the user is still speaking, and so does what reads a picture.
        warm()
        if settings.sight { InterfaceTools.warm() }
        hud = CommandHUDSnapshot(phase: .listening, status: L10n.tr("命令 · 正在听", "Command · listening"), detail: detail())
    }
    func end() { quiet?.invalidate(); if hud.phase == .listening { voice.end() } }
    func cancelCapture() {
        guard hud.phase == .listening else { return }
        quiet?.invalidate()
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
        default:
            guard hud.text != voice.liveTranscript else { return }
            hud.text = voice.liveTranscript
            quiet?.invalidate()
            guard !hud.text.isEmpty else { return }
            quiet = Timer.scheduledTimer(withTimeInterval: Self.quiet, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { if self?.hud.phase == .listening, self?.voice.state == .recording { self?.voice.end() } }
            }
        }
    }

    private func heard(_ text: String, _ audio: SpeechAudio?) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hud.phase == .listening, !words.isEmpty else { hud = CommandHUDSnapshot(); return }
        run(words, audio: audio)
    }

    // MARK: One instruction

    /// `audio` is the recording the words were recognised in, for a model that hears it itself.
    func run(_ words: String, audio: SpeechAudio? = nil) {
        // Whatever was running or being asked gives way to the new instruction.
        halt()
        let token = generation, previous = turn
        instruction = words; lastMessage = ""; steps = 0
        // Settles which conversation this one belongs to before the overlay names it.
        warm()
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
            await self?.execute(words, audio, token)
        }
    }

    private func execute(_ words: String, _ audio: SpeechAudio?, _ token: Int) async {
        guard token == generation else { return }
        defer { if runningTurn == token { runningTurn = nil }; listener.settle(); armIdle() }
        var journal: TaskJournal?
        do {
            let kernel = try await ready()
            guard token == generation else { return }
            // A conversation that could not be taken up again, or was never opened, starts here.
            if kernel.session == nil { turns = 0; usage = nil; settings.conversation = nil }
            turns += 1
            let records = support.appendingPathComponent("tasks")
            if !pruned { pruned = true; TaskJournal.clear(root: records, olderThan: 14) }
            journal = try? TaskJournal(root: records)
            // What was spoken is kept beside the record of what was done with it, for the user to hear again.
            let spoken = settings.recordings ? audio.flatMap { journal?.keep(recording: $0.wav) == true ? $0.duration : nil } : nil
            journal?.record("instruction", ["text": .string(words), "app": .string(tools.source?.name ?? ""),
                                            "model": .string(settings.modelName), "turn": .number(Double(turns)),
                                            "spoken": spoken.map(JSONValue.number) ?? .null])
            tools.sight = settings.sight
            let gateway = Gateway(tools: ToolCatalog.mounted(sight: settings.sight, voices: voiced), host: tools, permission: settings.permission,
                                  stepLimit: settings.stepLimit, journal: journal)
            self.gateway = gateway; runningTurn = token
            let prompt = CoordinatorPrompt.task(words, frontApp: tools.source?.name ?? "", window: tools.source?.window ?? "",
                                                recording: spoken.flatMap { seconds in journal.map { ($0.id, seconds) } })
            modelSpoke = false
            if kernelListens, let audio { listener.hear(prompt, audio) }
            let reason = try await kernel.run(prompt, tools: { await gateway.call($0, $1) }) { [weak self, journal] event in
                journal?.note(event)
                Task { @MainActor in self?.note(event, token) }
            }
            journal?.settle()
            if let opened = (kernel as? KernelSession)?.options.models, !opened.isEmpty { catalog = opened }
            let ending = await gateway.ending, unverified = await gateway.unverified
            let result = outcome(ending, unverified: !unverified.isEmpty)
            journal?.record("end", ["reason": .string(reason), "finished": .bool(result.phase == .done), "said": .string(result.text),
                                    "unverified": .array(unverified.map(JSONValue.string))])
            guard token == generation else { return }
            limit?.invalidate(); limit = nil
            show(result.phase, result.text, for: result.phase == .done ? 5 : 10, detail: detail(ended: true))
            // A model that speaks has said it already; otherwise the line is read out.
            if !modelSpoke { say(result.text) }
            // A conversation the user wants no memory of, or one near the end of its window, is not carried on.
            if settings.historyMinutes == 0 || usage.map({ $0.used * 5 >= $0.size * 4 }) == true { endConversation() }
            else if let session = kernel.session {
                settings.conversation = CommandConversation(session: session, last: Date(), turns: turns, used: usage?.used, size: usage?.size)
            }
        } catch {
            journal?.settle()
            journal?.record("end", ["reason": "failed", "finished": false, "said": .string(explain(error))])
            guard token == generation else { return }
            limit?.invalidate(); limit = nil
            // A kernel that failed is not reused, and neither is what it was doing.
            endConversation()
            show(.attention, explain(error), for: 8)
        }
    }

    private func note(_ event: KernelEvent, _ token: Int) {
        guard token == generation else { return }
        switch event {
        case .message(let text): lastMessage += text
        case .toolStarted(_, let name, _):
            steps += 1
            // The gateway counts VibeWand's own tools and tells the model to wrap up. A harness's own are only seen here.
            if !name.hasPrefix(TaskJournal.mounted), steps > settings.stepLimit {
                halt(); show(.attention, L10n.tr("步数超过上限，已停止", "Stopped: too many steps"), for: 6); return
            }
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
            // The model stopped without saying how it ended; its last words are all there is. From a model
            // that talks with the user they are an answer.
            let said = lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            return (kernelListens && !said.isEmpty ? .done : .attention, said.isEmpty ? L10n.tr("没有得到结果", "No result") : String(said.prefix(160)))
        }
    }

    /// The line under a command: which model is acting, how full its context is, how far it has got and how much it asks.
    private func detail(ended: Bool = false) -> String {
        var parts = [settings.modelName]
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
        say(hud.text)
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
        // An answered question need not be read to its end.
        if answer != nil { hush() }
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
        limit?.invalidate(); limit = nil; quiet?.invalidate()
        listener.settle(); hush()
    }
    /// What is said aloud is said in a voice of the voice service, which the user, or the model for them, may change.
    private var voiced: Bool { settings.speaks && speech != nil && !settings.voices.isEmpty }
    /// Says a line of VibeWand's own, a result or a question, in the voice the user chose. While commands go to
    /// the model that listens, that model says it, so that everything is heard in one voice. Beside a model
    /// with no voice the voice service's synthesis reads it. Without that service, or when it does not
    /// answer, the macOS voice does.
    private func say(_ line: String) {
        guard settings.speaks, let speech else { return }
        saying?.cancel()
        let listening = settings.listening, voice = settings.readerVoice
        guard listening || (!settings.voices.isEmpty && !voice.isEmpty) else { speech.say(line); return }
        saying = Task { [weak self, listener] in
            do {
                if listening {
                    try await listener.say(line) { speech.play($0, sampleRate: QwenRealtimeConversation.sampleRate) }
                } else {
                    let read = try await listener.read(line, voice: voice)
                    try Task.checkCancellation()
                    speech.play(read, sampleRate: QwenSpeechSynthesis.sampleRate)
                }
            }
            // The service did not answer: the line is still worth hearing.
            catch { if !Task.isCancelled, self != nil { speech.say(line) } }
        }
    }
    /// Says a line in the voice now chosen, for the user to hear what they picked.
    func audition() {
        hush()
        say(L10n.tr("你好，我是 VibeWand。以后就用这个声音跟你说话。", "Hello, this is VibeWand. This is the voice I will speak in."))
    }
    /// The model's way to the voice VibeWand speaks in: the voices there are, or a change to one of them.
    private func revoice(_ name: String?) -> ToolOutcome {
        let voices = settings.voices
        guard let name, !name.isEmpty else {
            return .ok(["current": .string(settings.speakingVoice), "voices": .array(voices.map { voice in
                ["voice": .string(voice.id), "name": .string(voice.name), "speaker": .string(voice.female ? "woman" : "man"),
                 "kind": .string(voice.kind.rawValue), "sounds": .string(voice.sound.zh + " / " + voice.sound.en)]
            })])
        }
        guard let voice = SpeechVoice.named(name, in: voices) else { return .failure("No such voice. Call set_voice without arguments for the list.") }
        settings.setSpeakingVoice(voice.id)
        return .ok(.string("VibeWand now speaks as \(voice.id)."))
    }
    private func hush() { saying?.cancel(); saying = nil; speech?.stop() }

    private func show(_ phase: CommandHUDSnapshot.Phase, _ text: String, for seconds: TimeInterval, detail: String = "") {
        hud = CommandHUDSnapshot(phase: phase, status: phase == .done ? L10n.tr("命令 · 完成", "Command · done") : L10n.tr("命令", "Command"),
                                 text: text, detail: detail)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hud = CommandHUDSnapshot() }
        }
    }

    // MARK: The conversation and its kernel

    /// The conversation the next command carries on, or nil when it starts a new one: nothing was kept, the user
    /// keeps none, it was kept longer ago than they asked for, or it is near the end of its model's context.
    private var carried: CommandConversation? {
        guard let kept = settings.conversation, settings.historyMinutes != 0 else { return nil }
        if settings.historyMinutes > 0, Date().timeIntervalSince(kept.last) > TimeInterval(settings.historyMinutes) * 60 { return nil }
        if let usage = kept.usage, usage.used * 5 >= usage.size * 4 { return nil }
        return kept
    }

    private func ready() async throws -> any CommandKernel {
        warm()
        if let kernel { return kernel }
        guard let opening else { throw Failure.kernelMissing }
        return try await opening.value
    }
    private func warm() {
        armIdle()
        // A job of VibeWand's own gives way to a command.
        errandStopped = true; errand?.cancel()
        let kept = carried
        // A kernel still holding a conversation that is over gives way to a fresh one, and so does one started
        // on another model than commands now go to. That one's conversation is carried on.
        if let held = kernel?.session, held != kept?.session { rest() }
        if kernel != nil, kernelListens != settings.listening { rest() }
        guard kernel == nil, opening == nil else { return }
        turns = kept?.turns ?? 0; usage = kept?.usage
        if kept == nil { settings.conversation = nil }
        let open = openKernel ?? { [weak self] resume in
            guard let self else { throw Failure.kernelMissing }
            return try await self.open(resume: resume)
        }
        opening = Task { [weak self, closing] in
            defer { self?.opening = nil }
            await closing?.value
            let kernel = try await open(kept?.session)
            self?.kernel = kernel
            return kernel
        }
    }

    /// Starts the harness of the mode in force on VibeWand's coordinator. The shipped harness and one the user
    /// installed are started the same way; the settings say where the models come from.
    private func open(resume: String?) async throws -> KernelSession {
        guard let harness = settings.harness else { throw settings.kernelMode == .harness ? Failure.harnessMissing : Failure.kernelMissing }
        // The model that listens is one more route, served by this app; either harness is started on it the same way.
        let listening = settings.listenModel
        let models: Harness.Models?
        if let listening { models = .route(try await listener.route(model: listening)) } else { models = await settings.models() }
        guard let models else { throw Failure.modelMissing }
        guard let version = await version(of: harness) else { throw Failure.harnessMissing }
        var launch = try harness.launch(version: version, allowUnverified: settings.harnessUnverified, support: folder, models: models,
                                        tools: settings.tools, permission: settings.permission, instructions: settings.instructions,
                                        sight: settings.sight, hearing: listening != nil, keeping: resume)
        prepare?(&launch)
        let session = try await KernelSession.open(launch, tools: ToolCatalog.mounted(sight: settings.sight, voices: voiced), resume: resume)
        // A harness's own tools ask through the same gateway as VibeWand's.
        session.approve = { [weak self] tool, input in
            guard let gateway = self?.gateway else { return false }
            return await gateway.approve(tool, input)
        }
        session.onExit = { [weak self, weak session] in
            Task { @MainActor in if let session, self?.kernel === session { self?.kernel = nil } }
        }
        kernelListens = listening != nil
        return session
    }
    /// A harness's version. Asking takes a moment, so the answer is kept while its command is unchanged.
    func version(of harness: Harness) async -> String? {
        let stamp = (try? harness.launcher.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let known = versions[harness.launcher], known.stamp == stamp { return known.version }
        guard let version = await harness.version() else { return nil }
        versions[harness.launcher] = (stamp, version)
        return version
    }
    /// Lets the process go once commands stop coming. The conversation stays in the runtime's store, where the
    /// next command takes it up again for as long as the user keeps conversations, and where an installed
    /// harness's own apps can open it meanwhile.
    private func armIdle() {
        idle?.invalidate()
        idle = Timer.scheduledTimer(withTimeInterval: Self.rest, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.rest() } }
    }
    /// Stops the kernel process. What it knows of the conversation is kept for the next start.
    func rest() {
        idle?.invalidate(); idle = nil
        if let kernel { closing = Task { [closing] in await closing?.value; await kernel.shutdown() } }
        kernel = nil
        tools.shutdown()
    }
    /// Ends the conversation: the next instruction opens a new one. Also called when a setting changes.
    func endConversation() {
        rest()
        settings.conversation = nil; usage = nil; turns = 0
    }

    // MARK: A job of VibeWand's own

    /// No command is under way and no kernel is kept warm for the next one.
    var resting: Bool { !hud.active && kernel == nil && opening == nil && runningTurn == nil && errand == nil }

    /// Runs a job that is not a command, the vocabulary's upkeep, in a conversation of its own: `task` under
    /// `prompt`, with `tools` and nothing else, on the model that reads. It runs on the harness of the mode in
    /// force like a command, so one the user installed lists it among its conversations. A kernel resting
    /// between commands lets go first, and a command that begins meanwhile takes the job's place: it then ends
    /// as `cancelled`. Throws `Failure.busy` while a command is under way.
    func attend(prompt: String, task: String, tools: [ToolDefinition], call: @escaping ToolSocket.Call,
                events: @escaping (KernelEvent) -> Void = { _ in }) async throws -> String {
        guard !hud.active, opening == nil, runningTurn == nil, errand == nil else { throw Failure.busy }
        rest()
        errandStopped = false
        let previous = closing
        let job = Task { [weak self] () throws -> String in
            await previous?.value
            guard let self, !self.errandStopped else { throw Failure.busy }
            let kernel = try await self.openErrand(prompt: prompt, tools: tools)
            self.errand = kernel
            defer { self.errand = nil }
            // Opened while a command was already asking: it never starts.
            guard !self.errandStopped else { await kernel.shutdown(); throw Failure.busy }
            do {
                let reason = try await kernel.run(task, tools: call, events: events)
                await kernel.shutdown()
                return reason
            } catch { await kernel.shutdown(); throw error }
        }
        // The kernel of the next command waits until this one has gone.
        closing = Task { _ = try? await job.value }
        return try await job.value
    }
    private func openErrand(prompt: String, tools: [ToolDefinition]) async throws -> any CommandKernel {
        if let openKernel { return try await openKernel(nil) }
        guard let harness = settings.harness else { throw settings.kernelMode == .harness ? Failure.harnessMissing : Failure.kernelMissing }
        // The model that reads does the job. Where commands go to the one that listens and no other is set up, that one reads too.
        var models = await settings.reading()
        if models == nil, let listening = settings.listenModel { models = .route(try await listener.route(model: listening)) }
        guard let models else { throw Failure.modelMissing }
        guard let version = await version(of: harness) else { throw Failure.harnessMissing }
        // The shipped harness keeps one conversation, the one a command may carry on: it is kept through this.
        var launch = try harness.launch(version: version, allowUnverified: settings.harnessUnverified, support: folder, models: models,
                                        prompt: prompt, keeping: settings.conversation?.session)
        prepare?(&launch)
        return try await KernelSession.open(launch, tools: tools)
    }

    /// Starts a kernel on the model as it is set and asks it for one word, so Settings can check the address,
    /// key and model together. Returns how long it took and the context the kernel reports, or what went wrong.
    func probe() async -> (ok: Bool, detail: String) {
        halt(); endConversation()
        let previous = turn
        let check = Task { [weak self] () -> (ok: Bool, detail: String) in
            await previous?.value
            guard let self else { return (false, "") }
            defer { self.endConversation() }
            do {
                let started = Date(), kernel = try await self.ready()
                // What the harness can serve is known once the conversation opens, whether or not its model then answers.
                defer { if let opened = (kernel as? KernelSession)?.options.models, !opened.isEmpty { self.catalog = opened } }
                let prompt = CoordinatorPrompt.task("connection test: reply with the single word ok", frontApp: "", window: "")
                _ = try await kernel.run(prompt, tools: { _, _ in .failure("No tool is available in this check.") }) { [weak self] event in
                    Task { @MainActor in if case .usage(let used, let size) = event { self?.usage = (used, size) } }
                }
                let took = String(format: L10n.tr("模型已回答，用时 %.1f 秒", "The model answered in %.1f s"), Date().timeIntervalSince(started))
                return (true, took + (self.usage.map { L10n.tr("；内核按 ", "; the kernel takes its context as ") + Self.tokens($0.size) + L10n.tr(" 的上下文计算", "") } ?? ""))
            } catch { return (false, self.explain(error)) }
        }
        turn = Task { _ = await check.value }
        return await check.value
    }

    /// Opens the installed harness's own web app in the browser, where every conversation it holds can be read
    /// with its whole context. It is started afresh each time: a harness that is already running lists a
    /// conversation another process wrote only after it restarts.
    func openHarnessViewer() {
        guard let harness = settings.harness(.harness) else { return }
        viewer?.terminate()
        let process = Process(), output = Pipe()
        process.executableURL = harness.launcher
        process.arguments = Array(harness.command.dropFirst()) + ["--profile", "web", "--no-open", "--port", "0"]
        var environment = ProcessInfo.processInfo.environment
        environment["DSH_HOME"] = harness.home?.path
        // Where VibeWand's view in that app finds the recordings of spoken commands.
        environment["VIBEWAND_TASKS"] = support.appendingPathComponent("tasks").path
        process.environment = environment
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        // The web app says where it listens, with the token that lets a browser in, on its first line.
        output.fileHandleForReading.readabilityHandler = { handle in
            let said = String(decoding: handle.availableData, as: UTF8.self)
            guard let address = Self.address(in: said) else { if said.isEmpty { handle.readabilityHandler = nil }; return }
            handle.readabilityHandler = nil
            NSWorkspace.shared.open(address)
        }
        viewer = (try? process.run()) != nil ? process : nil
    }
    nonisolated static func address(in text: String) -> URL? {
        text.split(whereSeparator: \.isWhitespace).lazy.filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }.compactMap { URL(string: String($0)) }.first
    }
    /// Called when the app quits.
    func shutdown() { rest(); viewer?.terminate(); viewer = nil }

    /// The records of recent instructions, newest first.
    func history() -> [TaskRecord] { TaskJournal.recent(root: support.appendingPathComponent("tasks")) }

    /// Removes the task records and what the kernels wrote here; a profile is written again at the next start.
    /// Conversations kept by the user's own harness in plugin mode are that harness's to delete.
    func clearRecords() {
        endConversation()
        for name in ["tasks", CommandKernelMode.builtIn.folder, CommandKernelMode.harness.folder] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
    }

    nonisolated static let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VibeWand")

    static func caption(_ tool: String) -> String {
        switch tool.components(separatedBy: "__").last ?? tool {
        case "list_targets": return L10n.tr("查看应用", "checking apps")
        case "find_sessions": return L10n.tr("查找会话", "finding chats")
        case "open_session": return L10n.tr("打开会话", "opening the chat")
        case "search_in_app": return L10n.tr("打开搜索", "opening search")
        case "activate_app": return L10n.tr("切换应用", "switching apps")
        case "ui_snapshot": return L10n.tr("读取界面", "reading the window")
        case "ui_screenshot": return L10n.tr("查看窗口", "looking at the window")
        case "ui_type": return L10n.tr("输入文字", "typing")
        case "ui_press", "ui_key", "ui_menu", "ui_click": return L10n.tr("操作界面", "operating the window")
        case "set_voice": return L10n.tr("换声音", "changing the voice")
        // A harness's own tools, when the user has let the model use them.
        case "bash": return L10n.tr("运行命令", "running a command")
        case "read", "read_image", "glob", "grep": return L10n.tr("读取文件", "reading files")
        case "edit", "write": return L10n.tr("修改文件", "changing files")
        case "web_search", "web_fetch": return L10n.tr("查网页", "looking it up")
        default: return L10n.tr("处理中", "working")
        }
    }

    /// What went wrong, for the user. A model setting the kernel refused at start is named only in its log.
    private func explain(_ error: Error) -> String {
        guard let refused = error as? RPCError, refused.message.contains("no adapter registered"),
              let log = try? String(contentsOf: folder.appendingPathComponent("logs/kernel.log"), encoding: .utf8),
              let line = log.split(separator: "\n").first(where: { $0.contains("$.providers.vibewand") }) else { return Self.describe(error) }
        let reason = line.replacingOccurrences(of: "$.providers.vibewand.", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        return L10n.tr("内核没有接受这套模型配置：", "The kernel refused these model settings: ") + reason.prefix(240)
    }
    static func describe(_ error: Error) -> String {
        switch error {
        case Failure.kernelMissing: return L10n.tr("此版本未包含命令内核", "This build does not include the command kernel")
        case Failure.modelMissing: return L10n.tr("请先在设置的命令模式中选好模型并保存密钥", "Choose a model and save its key under Command mode in Settings first.")
        case Failure.busy: return L10n.tr("正在执行命令，稍后再试", "A command is under way. Try again later.")
        case Failure.harnessMissing: return L10n.tr("没有找到可用的 DeepSeek Harness。请安装它，或在设置的命令模式里改用内置内核。",
                                                    "No usable DeepSeek Harness was found. Install it, or switch to the built-in kernel under Command mode in Settings.")
        case Harness.Failure.unverified(let version):
            let verified = Harness.verified.joined(separator: ", ")
            return L10n.tr("已安装的 DeepSeek Harness 是 \(version)，插件只在 \(verified) 上验证过。可在设置的命令模式里允许尝试，或改用内置内核。",
                           "The installed DeepSeek Harness is \(version); the plugin has been verified on \(verified) only. Allow trying it under Command mode in Settings, or switch to the built-in kernel.")
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
