import AppKit
import ApplicationServices
import SpeechInput
import WandAgent

/// Learns the user's own words from what they change in dictated text, once they have allowed it. After a
/// dictation it reads the text field the words went into until the user is done with it, and keeps the passage
/// as written and as left when the two differ. From time to time a model goes through what was kept, in a
/// conversation of its own on command mode's kernel, and brings the learned terms up to date.
@MainActor
final class VocabularyKeeper: ObservableObject {
    /// Off until the user turns it on: with it on, a text field is read back and sentences of theirs are kept.
    @Published private(set) var enabled: Bool
    /// How the last upkeep went, for Settings.
    @Published private(set) var status: String
    /// Corrected passages not yet learned from.
    @Published private(set) var waiting: Int
    @Published private(set) var running = false

    /// How long a field is followed after a dictation, how often it is read, and the longest text it may hold:
    /// a field holding more is a document, not a message being gone over.
    static var patience: TimeInterval = 180
    static var interval: TimeInterval = 1
    static let longestField = 20_000
    /// The upkeep runs once a day when anything waits, and after an hour once this many do.
    static let batch = 10

    private let voice: VoiceInputController
    private let command: CommandController
    private let defaults: UserDefaults
    let notebook: VocabularyNotebook
    private let target = DictationTargetAdapter()
    private let reader = DispatchQueue(label: "VibeWand.vocabulary", qos: .utility)
    /// A text field as it is read off the main thread.
    private struct Field: @unchecked Sendable { let element: AXUIElement }
    /// The dictation being followed: its field, what was written, the field's text right after, and its text now.
    private struct Follow {
        var field: Field
        var written: String, before: String, latest: String, app: String
        var until: Date
    }
    private var follow: Follow?
    /// The upkeep under way: whether the model has been shown the passages, and the line it ended with.
    private var shown = false
    private var summary: String?
    private var generation = 0
    private var poll: Timer?
    private var clock: Timer?

    init(voice: VoiceInputController, command: CommandController, defaults: UserDefaults = .standard,
         directory: URL = CommandController.applicationSupport.appendingPathComponent("vocabulary")) {
        self.voice = voice; self.command = command; self.defaults = defaults
        notebook = VocabularyNotebook(directory: directory)
        enabled = defaults.bool(forKey: "vocabularyLearning")
        status = defaults.string(forKey: "vocabularyStatus") ?? ""
        waiting = notebook.pending().count
        if enabled { schedule() }
    }

    /// Turning it off forgets the passages that were kept. The terms already learned stay until the user removes them.
    func setEnabled(_ value: Bool) {
        enabled = value; defaults.set(value, forKey: "vocabularyLearning")
        if value { schedule() } else { settle(); clock?.invalidate(); clock = nil; notebook.clear(); waiting = 0 }
    }

    /// Tells someone who has dictated a few times that the learning exists, once.
    func hint() -> String? {
        guard !enabled, !defaults.bool(forKey: "vocabularyHinted") else { return nil }
        let dictations = defaults.integer(forKey: "vocabularyDictations") + 1
        defaults.set(dictations, forKey: "vocabularyDictations")
        guard dictations >= 5 else { return nil }
        defaults.set(true, forKey: "vocabularyHinted")
        return L10n.tr("听写已完成 · 常要改同样的词？可在“语音输入”里打开词表学习", "Dictation complete · Fixing the same words often? Turn on vocabulary learning under Voice input")
    }

    // MARK: Following a dictation

    /// A dictation has been written into the focused field of the app `pid`. A terminal's text is its whole
    /// screen, and a password field is never read.
    func written(_ text: String, pid: pid_t, bundleID: String) {
        settle()
        guard enabled, text.count >= 2, ApplicationProfile.resolve(bundleID: bundleID) != .terminal else { return }
        let token = generation
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID
        // The field is read once the write has settled in it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.generation == token else { return }
            self.target.requestRefresh { [weak self] observation in
                guard let self, self.generation == token, observation.pid == pid, !observation.secureField, let editor = observation.editor else { return }
                let field = Field(element: editor)
                self.reader.async {
                    let value = Self.text(of: field)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == token, let value, value.count <= Self.longestField, value.contains(text) else { return }
                        self.follow = Follow(field: field, written: text, before: value, latest: value, app: app, until: Date().addingTimeInterval(Self.patience))
                        self.poll = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.look() } }
                    }
                }
            }
        }
    }

    private func look() {
        guard let follow else { return }
        let token = generation
        reader.async {
            let value = Self.text(of: follow.field)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token, self.follow != nil else { return }
                // A field that was emptied was sent, and one that is gone was closed: what it last held is
                // what the user made of the text.
                guard let value, !value.isEmpty, value.count <= Self.longestField else { self.settle(); return }
                self.follow?.latest = value
                if Date() >= follow.until { self.settle() }
            }
        }
    }

    /// Ends the following and keeps the passage when the user changed it. Called as the next dictation begins.
    func settle() {
        generation += 1
        poll?.invalidate(); poll = nil
        guard let follow else { return }
        self.follow = nil
        guard enabled, let revision = DictationRevision.read(written: follow.written, before: follow.before, after: follow.latest, app: follow.app) else { return }
        notebook.add(revision); waiting = notebook.pending().count
    }

    private nonisolated static func text(of field: Field) -> String? {
        AXUIElementSetMessagingTimeout(field.element, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field.element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // MARK: Upkeep

    private var lastUpkeep: Date { Date(timeIntervalSince1970: defaults.double(forKey: "vocabularyUpkeep")) }

    private func schedule() {
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.consider() } }
    }
    /// Runs the upkeep when it is due and nothing else is going on.
    private func consider() {
        guard enabled, !running, waiting > 0, command.resting, !voice.state.active else { return }
        let since = Date().timeIntervalSince(lastUpkeep)
        if since >= 86_400 || (waiting >= Self.batch && since >= 3_600) { tidy() }
    }

    /// Has a model go through the corrected passages and bring the learned terms up to date. The passages it
    /// was shown leave the notebook once it has finished; a run that was cut short leaves them for the next.
    func tidy() {
        guard enabled, !running else { return }
        let revisions = notebook.pending()
        guard !revisions.isEmpty else { report(L10n.tr("没有新的改动可学。", "No new corrections to learn from.")); return }
        running = true
        defaults.set(Date().timeIntervalSince1970, forKey: "vocabularyUpkeep")
        Task {
            defer { running = false }
            let journal = try? TaskJournal(root: command.support.appendingPathComponent("tasks"))
            journal?.record("instruction", ["text": .string(L10n.tr("整理听写词表（\(revisions.count) 段改过的听写）", "Vocabulary upkeep (\(revisions.count) corrected passage\(revisions.count == 1 ? "" : "s"))")),
                                            "app": "", "model": .string(command.settings.modelName), "turn": 1])
            shown = false; summary = nil
            do {
                let reason = try await command.attend(prompt: VocabularyPrompt.system, task: VocabularyPrompt.task(revisions: revisions.count),
                                                      tools: ToolCatalog.vocabulary, call: { [weak self] name, arguments in
                    await MainActor.run {
                        journal?.record("call", ["tool": .string(name), "arguments": arguments])
                        let outcome = self?.answer(name, arguments, revisions) ?? .failure("VibeWand has quit.")
                        journal?.record("result", ["tool": .string(name), "ok": .bool(!outcome.isError), "verified": true,
                                                   "text": .string(String(outcome.text.prefix(TaskJournal.resultLimit)))])
                        return outcome
                    }
                }, events: { journal?.note($0) })
                journal?.settle()
                journal?.record("end", ["reason": .string(reason), "finished": .bool(summary != nil), "said": .string(summary ?? "")])
                if let summary {
                    notebook.settle(Set(revisions.map(\.id))); waiting = notebook.pending().count
                    report(summary)
                } else { report(L10n.tr("这次没有整理完，下次再试。", "The upkeep did not finish. It will be tried again.")) }
            } catch {
                journal?.settle()
                journal?.record("end", ["reason": "failed", "finished": false, "said": .string(CommandController.describe(error))])
                report(CommandController.describe(error))
            }
        }
    }

    private func report(_ line: String) {
        let clock = DateFormatter(); clock.dateFormat = "MM-dd HH:mm"
        status = clock.string(from: Date()) + " · " + line
        defaults.set(status, forKey: "vocabularyStatus")
    }

    /// The keeper's three tools. Its reach ends here: the passages it is shown, and a list of short terms each
    /// of which the user themselves wrote in one of those passages.
    private func answer(_ tool: String, _ arguments: JSONValue, _ revisions: [DictationRevision]) -> ToolOutcome {
        let vocabulary = voice.configuration.effectiveVocabulary
        switch tool {
        case "read_revisions":
            shown = true
            return .ok(["revisions": .array(revisions.map { revision in
                ["id": .string(revision.id), "app": .string(revision.app), "said": .string(revision.said), "kept": .string(revision.kept),
                 "changes": .array(revision.changes.map { ["from": .string($0.from), "to": .string($0.to)] })]
            }), "vocabulary": ["theirs": .array(vocabulary.terms.map(JSONValue.string)), "learned": .array((vocabulary.learned ?? []).map(JSONValue.string)),
                               "builtin": .bool(vocabulary.computing)]])
        case "update_vocabulary":
            guard shown else { return .failure("Call read_revisions first.") }
            let asked = (arguments["add"]?.array ?? []).compactMap(\.string)
            // A term is learned only when the user wrote it: nothing a passage says can put another word on the list.
            let adding = asked.filter { term in revisions.contains { $0.kept.range(of: term, options: .caseInsensitive) != nil } }
            var changed = vocabulary
            changed.learn(adding: adding, removing: (arguments["remove"]?.array ?? []).compactMap(\.string))
            do { try voice.learn(changed) } catch { return .failure("The vocabulary could not be saved.") }
            let refused = asked.filter { !adding.contains($0) }
            return .ok(["learned": .array((changed.learned ?? []).map(JSONValue.string)),
                        "refused": .array(refused.map(JSONValue.string)),
                        "note": .string(refused.isEmpty ? "" : "Refused terms do not occur in any passage as the user left it.")])
        case "finish":
            guard shown else { return .failure("Call read_revisions first.") }
            summary = arguments["summary"]?.string ?? ""
            return .ok("Done.")
        default: return .failure("No such tool.")
        }
    }
}
