import AppKit
import AU05Device
import SpeechInput
import WandAgent

/// Film mode, for recording the promotional video and nothing else: `--film <script.json>` runs the production
/// runtime on a scripted device, a replayed recogniser and a kernel that only names its steps, with preferences
/// and task records of its own, so the overlay can be filmed without a hand on a device or a voice at a
/// microphone. Run it with `--demo`, where nothing is sent to another app; `promo/README.md` says how.

/// A device that is always connected and presses what the script says.
@MainActor
final class FilmSource: HIDEventSource {
    private(set) var connection: AU05Connection = .stopped
    var onConnection: ((AU05Connection) -> Void)?
    var onEvent: ((AU05Event) -> Void)?
    private var sequence: UInt64 = 0
    func start() { connection = .ready; onConnection?(connection) }
    func stop() { connection = .stopped; onConnection?(connection) }
    func send(_ control: AU05Control, _ phase: AU05Phase) {
        sequence += 1
        onEvent?(AU05Event(control: control, phase: phase, sequence: sequence, uptime: ProcessInfo.processInfo.systemUptime))
    }
}

/// A kernel that only says what it would be doing. It names tools at the pace it is given and calls none but `finish`.
final class FilmKernel: CommandKernel, @unchecked Sendable {
    struct Beat: Decodable { var after: Double; var tool: String }
    var beats: [Beat] = []
    var summary = ""
    var session: String?
    private var cancelled = false
    func run(_ prompt: String, tools: @escaping ToolSocket.Call, events: @escaping (KernelEvent) -> Void) async throws -> String {
        cancelled = false; session = session ?? "film"
        for (index, beat) in beats.enumerated() where !cancelled {
            try? await Task.sleep(nanoseconds: UInt64(beat.after * 1_000_000_000))
            events(.toolStarted(id: "\(index)", name: TaskJournal.mounted + beat.tool))
            events(.usage(used: 2100 + index * 640, size: 262_144))
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        if !cancelled { _ = await tools("finish", ["summary": .string(summary)]) }
        return cancelled ? "cancelled" : "end_turn"
    }
    func cancel() { cancelled = true }
    func shutdown() async { session = nil }
}

@MainActor
final class FilmDirector {
    struct Step: Decodable {
        var at: Double
        /// A control held for `hold` seconds.
        var press: String?
        var hold: Double?
        /// The dial: "left" or "right", `count` detents, one every `every` seconds.
        var turn: String?
        var count: Int?
        var every: Double?
        var template: String?
        /// What the recogniser reports, one preview every half second, the next time it listens.
        var say: [String]?
        /// Holds the command key for as long as the previews take.
        var command: Bool?
        /// The steps the kernel names for the next command, and what it reports at the end.
        var simulate: [FilmKernel.Beat]?
        var summary: String?
        /// Waits here until the command in hand has ended, at most this many seconds.
        var settle: Double?
        var expanded: Bool?
        var note: String?
        var quit: Bool?
    }
    /// No key is on file and none is looked for: the Keychain is left alone.
    private struct NoKeys: SpeechCredentialStore {
        func read(account: String) throws -> String? { nil }
        func save(_ key: String, account: String) throws {}
        func remove(account: String) throws {}
        func contains(account: String) -> Bool { false }
    }
    private final class Words: @unchecked Sendable { var previews = [""] }

    private let steps: [Step]
    private let log: URL
    private let source = FilmSource()
    private let words = Words()
    private let kernel = FilmKernel()
    private let support: URL
    private let suite = "org.vibewand.film." + UUID().uuidString
    private var lines: [String] = []
    private var lastHUD = CommandHUDSnapshot()
    private var lastSpeech = ""
    private var watcher: Timer?
    var onExpanded: ((Bool) -> Void)?

    init(script: URL) throws {
        steps = try JSONDecoder().decode([Step].self, from: Data(contentsOf: script)).sorted { $0.at < $1.at }
        log = script.deletingPathExtension().appendingPathExtension("log.jsonl")
        support = FileManager.default.temporaryDirectory.appendingPathComponent("vibewand-film-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    func makeRuntime() -> BridgeRuntime {
        let defaults = UserDefaults(suiteName: suite)!
        var speech = SpeechConfiguration()
        speech.mode = .builtIn; speech.textStyle = .verbatim
        try? SpeechPreferences(defaults: defaults).save(speech)
        let words = words, support = support, source = source, kernel = kernel
        let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults),
                                         engineFactory: { _ in TranscriptReplayEngine(previews: words.previews) })
        let settings = CommandSettings(defaults: defaults, credentials: NoKeys())
        return BridgeRuntime(source: source, templates: DeviceTemplateStore(defaults: defaults), sourceFactory: { _, _ in source }, voiceInput: voice) {
            let command = CommandController(settings: settings, tools: CommandTools(adapter: $0), voice: $1, support: support)
            command.openKernel = { _ in kernel }
            return command
        }
    }

    func start(_ runtime: BridgeRuntime) {
        let began = Date()
        note("start", ["steps": steps.count])
        watcher = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch(runtime) }
        }
        Task { @MainActor in
            for step in steps {
                let wait = step.at - Date().timeIntervalSince(began)
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                await perform(step, runtime)
            }
        }
    }

    private func perform(_ step: Step, _ runtime: BridgeRuntime) async {
        if let text = step.note { note("note", ["text": text]) }
        if let previews = step.say, !previews.isEmpty { words.previews = previews }
        if let beats = step.simulate { kernel.beats = beats; kernel.summary = step.summary ?? "" }
        if let expanded = step.expanded { onExpanded?(expanded); note("expanded", ["value": expanded]) }
        if let id = step.template, let template = DeviceTemplateID(rawValue: id) {
            try? runtime.selectTemplate(template); note("template", ["id": id])
        }
        if let name = step.press, let control = AU05Control(rawValue: name) {
            let hold = step.hold ?? 0.08
            note("down", ["control": name]); source.send(control, .down)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                self.source.send(control, .up); self.note("up", ["control": name])
            }
        }
        if let direction = step.turn, let control = AU05Control(rawValue: direction) {
            let count = step.count ?? 1, every = step.every ?? 0.06
            note("turn", ["direction": direction, "count": count, "every": every])
            Task { @MainActor in
                for _ in 0..<count {
                    self.source.send(control, .pulse)
                    try? await Task.sleep(nanoseconds: UInt64(every * 1_000_000_000))
                }
            }
        }
        if step.command == true {
            note("command", ["words": words.previews.last ?? ""])
            runtime.command.begin()
            // The last preview must be in before the key comes up; a busy Mac delivers it late.
            let listen = Double(words.previews.count) * 0.5 + 0.6
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(listen * 1_000_000_000))
                runtime.command.end(); self.note("released", [:])
            }
        }
        if let limit = step.settle {
            let deadline = Date().addingTimeInterval(limit)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            while Date() < deadline, [.listening, .working].contains(runtime.command.hud.phase) {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            note("settled", ["phase": "\(runtime.command.hud.phase)"])
        }
        if step.quit == true {
            note("quit", [:])
            watcher?.invalidate()
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: support)
            NSApp.terminate(nil)
        }
    }

    /// Every change of the command overlay and of the dictation text, with the time it happened, for the edit.
    private func watch(_ runtime: BridgeRuntime) {
        let hud = runtime.command.hud
        if hud != lastHUD {
            lastHUD = hud
            note("hud", ["phase": "\(hud.phase)", "status": hud.status, "text": hud.text, "detail": hud.detail, "options": hud.options])
        }
        let speech = "\(runtime.voiceInput.state)|\(runtime.voiceInput.liveTranscript)"
        if speech != lastSpeech { lastSpeech = speech; note("speech", ["state": "\(runtime.voiceInput.state)", "text": runtime.voiceInput.liveTranscript]) }
    }

    private func note(_ event: String, _ fields: [String: Any]) {
        var row = fields
        row["event"] = event; row["t"] = Date().timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)
    }
}
