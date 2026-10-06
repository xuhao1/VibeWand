import XCTest
import SwiftUI
import ApplicationServices
import SpeechInput
import WandAgent
@testable import VibeKeyBridge

/// Command mode is exercised with a scripted kernel and tools that only talk to
/// the overlay, so nothing here touches another app.
final class CommandTests: XCTestCase {
    private struct MemoryCredentials: SpeechCredentialStore {
        func read(account: String) throws -> String? { "test-key" }
        func save(_ key: String, account: String) throws {}
        func remove(account: String) throws {}
        func contains(account: String) -> Bool { true }
    }
    /// Remembers which account each key was saved under.
    private final class KeyRing: SpeechCredentialStore, @unchecked Sendable {
        var keys: [String: String] = [:]
        func read(account: String) throws -> String? { keys[account] }
        func save(_ key: String, account: String) throws { keys[account] = key }
        func remove(account: String) throws { keys[account] = nil }
        func contains(account: String) -> Bool { keys[account] != nil }
    }
    private func isolatedDefaults() -> UserDefaults {
        let name = "VibeWand.CommandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    @MainActor private func makeRuntime(enabled: Bool = true, permission: PermissionMode = .risky, template: DeviceTemplateID = .vibeKey,
                                        previews: [String] = ["切到 Codex"],
                                        script: [(tool: String, arguments: JSONValue)] = []) throws -> (BridgeRuntime, ScriptedKernel, URL) {
        let defaults = isolatedDefaults()
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("vw-command-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: support) }
        let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults),
                                         engineFactory: { _ in TranscriptReplayEngine(previews: previews) })
        let settings = CommandSettings(defaults: defaults, credentials: MemoryCredentials())
        settings.setPermission(permission)
        let kernel = ScriptedKernel(script)
        let templates = DeviceTemplateStore(defaults: defaults)
        try templates.select(template)
        let runtime = BridgeRuntime(source: UnconfiguredHIDSource(template: template.template), templates: templates, voiceInput: voice) {
            let command = CommandController(settings: settings, tools: CommandTools(adapter: $0), voice: $1, support: support)
            command.openKernel = { _ in kernel }
            return command
        }
        if !enabled { settings.setEnabled(false) }
        return (runtime, kernel, support)
    }
    @MainActor private func wait(_ what: String, _ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), what)
    }

    // MARK: Bindings

    func testCommandKeyAppearsOnlyWhileCommandModeIsOnAndYieldsToTheUsersOwnBinding() async throws {
        try await MainActor.run {
            let (runtime, _, _) = try makeRuntime(enabled: false)
            XCTAssertEqual(runtime.configuration.action(.reading, .dial, .long), .models)
            XCTAssertEqual(runtime.configuration.action(.reading, .ok, .long), GestureAction.none)
            runtime.command.settings.setEnabled(true)
            XCTAssertEqual(runtime.configuration.action(.reading, .dial, .long), .command)
            XCTAssertEqual(runtime.configuration.action(.editing, .dial, .long), .command)
            // Holding the dial now speaks, so the model entry is a long press of OK, in an effort popover too.
            XCTAssertEqual(runtime.configuration.action(.reading, .ok, .long), .models)
            XCTAssertEqual(runtime.configuration.action(.efforts, .ok, .long), .models)
            var custom = runtime.configuration
            custom.set(.global, .dial, .long, .sessions)
            try runtime.updateConfiguration(custom)
            XCTAssertEqual(runtime.configuration.action(.reading, .dial, .long), .sessions)
            runtime.command.settings.setEnabled(false)
            XCTAssertEqual(runtime.configuration.action(.reading, .ok, .long), GestureAction.none)
        }
    }

    func testKeyboardCommandKeyDefaultsToRightCommandUntilTheUserPicksAnother() async {
        await MainActor.run {
            let defaults = isolatedDefaults()
            // Right Option is the voice key of some input methods and never arrives where they run.
            XCTAssertEqual(CommandSettings(defaults: defaults, credentials: MemoryCredentials()).hotkey, .rightCommand)
            CommandSettings(defaults: defaults, credentials: MemoryCredentials()).setHotkey(.rightOption)
            XCTAssertEqual(CommandSettings(defaults: defaults, credentials: MemoryCredentials()).hotkey, .rightOption)
        }
    }

    func testCommandModeIsOnFromTheStartButLiveOnlyOnceAModelIsSetUp() async throws {
        try await MainActor.run {
            let ring = KeyRing(), defaults = isolatedDefaults()
            let settings = CommandSettings(defaults: defaults, credentials: ring)
            XCTAssertTrue(settings.enabled)
            // Navigation and typing run at once; only what sends or destroys waits, until the user picks another mode.
            XCTAssertEqual(settings.permission, .risky)
            XCTAssertEqual(settings.model.endpoint, "deepseek")
            XCTAssertEqual(settings.model.model, "deepseek-flash")
            // No key yet: the switch is on, but nothing is live and the device's keys are left as they were.
            XCTAssertFalse(settings.usable)
            XCTAssertFalse(settings.active)
            try settings.saveKey(" sk-one ")
            XCTAssertTrue(settings.active)
            // DeepSeek's key stays under the account it had before endpoints could be chosen.
            XCTAssertEqual(ring.keys, ["deepseek-official": "sk-one"])
            settings.setEnabled(false)
            XCTAssertFalse(settings.active)
            XCTAssertFalse(CommandSettings(defaults: defaults, credentials: ring).enabled)
        }
    }

    @MainActor
    func testAKeyBelongsToItsAddressAndEachEndpointRemembersItsModel() async throws {
        let ring = KeyRing(), defaults = isolatedDefaults()
        let settings = CommandSettings(defaults: defaults, credentials: ring)
        try settings.saveKey("sk-deepseek")

        // A local server needs no key; a remote one does.
        var local = settings.configuration(for: "omlx")
        XCTAssertEqual(local.baseURL, "http://127.0.0.1:8000/v1")
        XCTAssertTrue(local.keyOptional)
        local.model = "Qwen-Local"; local.contextWindow = 32_000; local.reasoning = .off
        local.extra = #"{"compat": {"thinkingFormat": "qwen-chat-template"}}"#
        try settings.setModel(local)
        XCTAssertTrue(settings.usable)
        XCTAssertFalse(settings.keySaved)
        // The route the kernel is given carries the settings as chosen, and no key where none was saved.
        func route(_ settings: CommandSettings) async -> ModelRoute? {
            if case .route(let route)? = await settings.models() { return route } else { return nil }
        }
        let chosen = await route(settings)
        XCTAssertEqual(chosen, ModelRoute(wire: .openAIChat, baseURL: "http://127.0.0.1:8000/v1", model: "Qwen-Local", key: nil, contextWindow: 32_000,
                                          reasoning: .off, extra: ["compat": ["thinkingFormat": "qwen-chat-template"]]))
        // A model is declared to take pictures only once the user has let it see.
        settings.setSight(true)
        let seeing = await route(settings)
        XCTAssertEqual(seeing?.images, true)
        settings.setSight(false)

        var custom = settings.configuration(for: CommandEndpoint.custom)
        custom.baseURL = " https://gateway.example/openai/v1 "; custom.wire = .anthropic; custom.model = "wand-large"
        try settings.setModel(custom)
        XCTAssertEqual(settings.model.baseURL, "https://gateway.example/openai/v1")
        XCTAssertTrue(settings.usable, "an address the user described may need no key")
        try settings.saveKey("sk-gateway")
        XCTAssertEqual(ring.keys["https://gateway.example"], "sk-gateway")
        let keyed = await route(settings)
        XCTAssertEqual(keyed?.key, "sk-gateway")
        XCTAssertEqual(keyed?.wire, .anthropic)
        // Pointing the same endpoint at another host does not take the key along.
        custom.baseURL = "https://elsewhere.example/v1"
        try settings.setModel(custom)
        XCTAssertFalse(settings.keySaved)
        let moved = await route(settings)
        XCTAssertNil(moved?.key)

        // What was set is validated, and each endpoint comes back as it was left.
        custom.baseURL = "gateway.example/v1"
        XCTAssertThrowsError(try settings.setModel(custom))
        custom.baseURL = "https://gateway.example/v1"; custom.extra = "[1, 2]"
        XCTAssertThrowsError(try settings.setModel(custom))
        let reopened = CommandSettings(defaults: defaults, credentials: ring)
        XCTAssertEqual(reopened.model.baseURL, "https://elsewhere.example/v1")
        XCTAssertEqual(reopened.configuration(for: "omlx"), local)
        XCTAssertEqual(reopened.configuration(for: "deepseek").model, "deepseek-flash")
        // A remote service without its key is not usable, so nothing is handed to the kernel.
        try reopened.setModel(reopened.configuration(for: "openai"))
        XCTAssertFalse(reopened.usable)
        let none = await reopened.models()
        XCTAssertNil(none)
    }

    @MainActor
    func testPluginModeNeedsOnlyAnInstalledHarnessAndNamesTheModelThatHarnessIsSetTo() async throws {
        final class Installed { var harness: Harness? }
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("vw-harness-home-\(UUID().uuidString)")
        addTeardownBlock { try? files.removeItem(at: home) }
        try files.createDirectory(at: home.appendingPathComponent("profiles/desktop"), withIntermediateDirectories: true)
        try """
            - id: agent-default-model
              name: "@deepseek-ai/dsh-agent-default-model"
              config:
                provider: local
                model: Qwen-Local

            """.write(to: home.appendingPathComponent("profiles/desktop/cordis.patch.yml"), atomically: true, encoding: .utf8)
        let bundles = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("kernel")
        let installed = Installed(), defaults = isolatedDefaults()
        let locate: (CommandKernelMode) -> Harness? = { $0 == .harness ? installed.harness : nil }
        let settings = CommandSettings(defaults: defaults, credentials: KeyRing(), harness: locate)
        XCTAssertEqual(settings.kernelMode, .builtIn)
        XCTAssertFalse(settings.usable, "the built-in kernel has no key yet")
        settings.setKernelMode(.harness)
        XCTAssertFalse(settings.usable, "no harness is installed")
        installed.harness = Harness(command: ["/opt/harness/bin/dsh"], home: home, coordinator: bundles.appendingPathComponent("coordinator"),
                                    overlay: bundles.appendingPathComponent("overlay"))
        // The models and keys are the harness's: VibeWand needs none of its own.
        XCTAssertTrue(settings.usable)
        XCTAssertTrue(settings.active)
        XCTAssertEqual(settings.modelName, "Qwen-Local")
        var models = await settings.models()
        XCTAssertEqual(models, .harness(nil, reasoning: .automatic), "the model is the harness's own to name")
        settings.setHarnessModel(Harness.Model(provider: "deepseek-official", model: "deepseek-v4-pro"))
        settings.setHarnessReasoning(.low); settings.setHarnessUnverified(true)
        XCTAssertEqual(settings.modelName, "deepseek-v4-pro")
        models = await settings.models()
        XCTAssertEqual(models, .harness(Harness.Model(provider: "deepseek-official", model: "deepseek-v4-pro"), reasoning: .low))

        // The harness's own tools are the user's to hand over, on an installed harness only.
        XCTAssertEqual(settings.tools, .own)
        settings.setHarnessTools(.all)
        XCTAssertEqual(settings.tools, .all)
        settings.setKernelMode(.builtIn)
        XCTAssertEqual(settings.tools, .own, "the shipped harness has none of its own to add")
        settings.setKernelMode(.harness)

        let reopened = CommandSettings(defaults: defaults, credentials: KeyRing(), harness: locate)
        XCTAssertEqual(reopened.kernelMode, .harness)
        XCTAssertEqual(reopened.harnessModel, Harness.Model(provider: "deepseek-official", model: "deepseek-v4-pro"))
        XCTAssertEqual(reopened.harnessReasoning, .low)
        XCTAssertTrue(reopened.harnessUnverified)
        XCTAssertEqual(reopened.tools, .all)
        reopened.setHarnessModel(nil)
        XCTAssertEqual(reopened.modelName, "Qwen-Local")
        XCTAssertNil(CommandSettings(defaults: defaults, credentials: KeyRing(), harness: locate).harnessModel)

        // What the user is told when plugin mode cannot start names the versions on both sides.
        let refused = CommandController.describe(Harness.Failure.unverified("0.3.0"))
        XCTAssertTrue(refused.contains("0.3.0") && refused.contains(Harness.verified[0]), refused)
        XCTAssertTrue(CommandController.describe(CommandController.Failure.harnessMissing).contains("DeepSeek Harness"))
    }

    func testCommandBindingsAreNeverSavedWithTheConfiguration() throws {
        var configuration = GestureConfiguration()
        configuration.commandLayer = DeviceTemplateID.vibeKey.template.commandBindings
        let restored = try JSONDecoder().decode(GestureConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertTrue(restored.commandLayer.isEmpty)
        XCTAssertEqual(restored.action(.reading, .dial, .long), .models)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(configuration), as: UTF8.self).contains("command"))
    }

    func testControllerSpeaksOnL2AndAnswersWithItsPickerButtons() {
        var configuration = DeviceTemplateID.dualSense.template.defaultConfiguration
        XCTAssertEqual(configuration.action(.reading, .l2, .hold), GestureAction.none)
        configuration.commandLayer = DeviceTemplateID.dualSense.template.commandBindings
        XCTAssertEqual(configuration.action(.reading, .l2, .hold), .command)
        XCTAssertEqual(configuration.action(.command, .l2, .hold), .command)
        // While the coordinator asks, the device answers it as it answers a model picker.
        XCTAssertEqual(configuration.action(.command, .escape, .single), .confirmCandidate)
        XCTAssertEqual(configuration.action(.command, .ok, .single), .cancelPicker)
        XCTAssertEqual(configuration.action(.command, .left, .rotate), .previousCandidate)
        XCTAssertEqual(GestureConfiguration().action(.command, .right, .rotate), .nextCandidate)
        XCTAssertTrue(DeviceTemplateID.xiaomiRemote.template.commandBindings.isEmpty)
    }

    // MARK: One instruction

    func testFinishedInstructionIsReportedFromTheGatewayAndRecorded() async throws {
        let (runtime, kernel, support) = try await MainActor.run { try makeRuntime(script: [("finish", ["summary": "已切到 Codex"])]) }
        await MainActor.run { runtime.command.run("切到 Codex") }
        await wait("the task ends") { runtime.snapshot.command.phase == .done }
        await MainActor.run {
            XCTAssertEqual(runtime.snapshot.command.text, "已切到 Codex")
            XCTAssertFalse(runtime.snapshot.command.capturesControls)
            XCTAssertTrue(kernel.prompts[0].hasPrefix("VibeWand · 切到 Codex\n"))
        }
        let task = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: support.appendingPathComponent("tasks"), includingPropertiesForKeys: nil).first)
        let journal = try String(contentsOf: task.appendingPathComponent("journal.jsonl"), encoding: .utf8)
        XCTAssertTrue(journal.contains(#""kind":"instruction""#) && journal.contains("切到 Codex"))
        XCTAssertTrue(journal.contains(#""kind":"end""#) && journal.contains(#""finished":true"#))
        await MainActor.run { runtime.stop() }
    }

    func testEveryStepWaitsForTheConfirmKeyUnlessTheUserChoseOtherwise() async throws {
        // Typing with no app captured reaches nothing: the tool refuses once it is allowed to run.
        let typing: [(tool: String, arguments: JSONValue)] = [("ui_type", ["text": "hello from vibewand, typed where the keyboard is"]), ("finish", ["summary": "好"])]
        let (runtime, kernel, support) = try await MainActor.run { try makeRuntime(permission: .ask, script: typing) }
        await MainActor.run { runtime.command.run("输入一句话") }
        await wait("the question") { runtime.snapshot.command.phase == .confirming }
        await MainActor.run {
            XCTAssertEqual(runtime.snapshot.command.text, L10n.tr("输入「hello from vibewand, typed where the key…」？", "Type “hello from vibewand, typed where the key…”?"))
            XCTAssertTrue(runtime.snapshot.command.detail.contains(PermissionMode.ask.title))
            runtime.handle(.ok, phase: .down); runtime.handle(.ok, phase: .up)
        }
        await wait("the task ends") { runtime.snapshot.command.phase == .done }
        let task = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: support.appendingPathComponent("tasks"), includingPropertiesForKeys: nil).first)
        XCTAssertTrue(try String(contentsOf: task.appendingPathComponent("journal.jsonl"), encoding: .utf8).contains(#""kind":"confirmed""#))
        // Declining ends the step without running it.
        await MainActor.run { runtime.command.run("再输入一句") }
        await wait("the question again") { runtime.snapshot.command.phase == .confirming }
        await MainActor.run { runtime.handle(.escape, phase: .down); runtime.handle(.escape, phase: .up) }
        await wait("stopped") { runtime.snapshot.command.text == L10n.tr("已停止", "Stopped") }
        await wait("the step is answered as declined") { kernel.outcomes.contains { $0.text.contains("declined") } }
        await MainActor.run { runtime.stop() }

        for mode in [PermissionMode.risky, .bypass] {
            let (runtime, kernel, _) = try await MainActor.run { try makeRuntime(permission: mode, script: typing) }
            await MainActor.run { runtime.command.run("输入一句话") }
            await wait("the task ends without a question") { runtime.snapshot.command.phase == .done }
            await MainActor.run {
                XCTAssertTrue(kernel.outcomes[0].text.contains("no longer in front"), "\(mode): \(kernel.outcomes[0].text)")
                runtime.stop()
            }
        }
    }

    func testTheOverlayNamesTheModelAndItsContextAndAFullOneIsNotCarriedOn() async throws {
        let (runtime, kernel, _) = try await MainActor.run { try makeRuntime(script: [("list_targets", [:]), ("finish", ["summary": "好"])]) }
        await MainActor.run {
            kernel.usage = (1_200, 8_000)
            XCTAssertEqual(runtime.command.turns, 0)
            runtime.command.run("看看有哪些应用")
            XCTAssertTrue(runtime.snapshot.command.detail.contains(L10n.tr("新对话", "new conversation")), runtime.snapshot.command.detail)
        }
        await wait("the task ends") { runtime.snapshot.command.phase == .done }
        await MainActor.run {
            let detail = runtime.snapshot.command.detail
            XCTAssertTrue(detail.hasPrefix("deepseek-flash · "), detail)
            XCTAssertTrue(detail.contains("1.2k/8.0k · 15%"), detail)
            XCTAssertTrue(detail.contains(L10n.tr("2 步", "2 steps")), detail)
            XCTAssertEqual(runtime.command.usage?.used, 1_200)
            XCTAssertEqual(runtime.command.turns, 1)
            XCTAssertEqual(kernel.shutdowns, 0)
            // Past four fifths of the window, the next instruction opens a new conversation.
            kernel.usage = (6_500, 8_000)
            runtime.command.run("再看一次")
        }
        await wait("the conversation is let go") { kernel.shutdowns == 1 }
        await MainActor.run {
            XCTAssertEqual(runtime.snapshot.command.phase, .done)
            XCTAssertTrue(runtime.snapshot.command.detail.contains("81%"), runtime.snapshot.command.detail)
            XCTAssertEqual(runtime.command.turns, 0)
            XCTAssertNil(runtime.command.usage)
            // And a user who wants no memory gets a new conversation every time.
            kernel.usage = (100, 8_000)
            runtime.command.settings.setHistoryMinutes(0)
            let before = kernel.shutdowns
            runtime.command.run("第三次")
            XCTAssertGreaterThanOrEqual(kernel.shutdowns, before)
        }
        await wait("the third ends") { runtime.snapshot.command.phase == .done && runtime.command.turns == 0 }
        await MainActor.run { runtime.stop() }
        // The harness's web app says where it listens on its first line; that address is what the browser is given.
        XCTAssertEqual(CommandController.address(in: "dsh web: http://127.0.0.1:55038/?token=abc_DEF-123\n")?.absoluteString, "http://127.0.0.1:55038/?token=abc_DEF-123")
        XCTAssertNil(CommandController.address(in: "(node:1) [DEP0180] DeprecationWarning: fs.Stats constructor is deprecated.\n"))
        XCTAssertEqual(CommandController.tokens(950), "950")
        XCTAssertEqual(CommandController.tokens(262_144), "262.1k")
        XCTAssertEqual(CommandController.tokens(1_048_576), "1.05M")
    }

    /// A conversation outlives the kernel process: it is taken up again for as long as the user keeps conversations.
    func testAConversationIsCarriedAcrossKernelStartsForAsLongAsTheUserKeepsIt() async throws {
        let script: [(tool: String, arguments: JSONValue)] = [("list_targets", [:]), ("finish", ["summary": "好"])]
        let (runtime, kernel, support) = try await MainActor.run { try makeRuntime(script: script) }
        final class Starts { var asked: [String?] = []; var refuse = false; var kernels: [ScriptedKernel] = [] }
        let starts = Starts()
        await MainActor.run {
            runtime.command.settings.setHistoryMinutes(1_440)
            kernel.usage = (1_200, 8_000)
            runtime.command.run("第一条")
        }
        await wait("the first ends") { runtime.snapshot.command.phase == .done }
        await MainActor.run {
            XCTAssertEqual(runtime.command.settings.conversation?.session, "scripted")
            XCTAssertEqual(runtime.command.settings.conversation?.turns, 1)
            XCTAssertEqual(runtime.command.settings.conversation?.usage?.used, 1_200)
            // Commands stop coming and the process is let go. The conversation is not.
            runtime.command.rest()
            XCTAssertEqual(runtime.command.turns, 1)
            XCTAssertNotNil(runtime.command.settings.conversation)
            runtime.command.openKernel = { resume in
                starts.asked.append(resume)
                let next = ScriptedKernel(script, session: starts.refuse ? nil : resume)
                next.usage = (2_000, 8_000); starts.kernels.append(next)
                return next
            }
            runtime.command.run("第二条")
            // What was kept is on the overlay before the kernel is back.
            XCTAssertTrue(runtime.snapshot.command.detail.contains("1.2k/8.0k"), runtime.snapshot.command.detail)
        }
        await wait("the second ends") { runtime.snapshot.command.phase == .done }
        await MainActor.run {
            XCTAssertEqual(kernel.shutdowns, 1, "the first kernel had gone before the next one started")
            XCTAssertEqual(starts.asked, ["scripted"])
            XCTAssertEqual(runtime.command.turns, 2)
            XCTAssertEqual(runtime.command.settings.conversation?.turns, 2)
            // A third command finds the kernel still there and starts none.
            runtime.command.run("第三条")
        }
        await wait("the third ends") { runtime.snapshot.command.phase == .done && runtime.command.turns == 3 }
        let records = TaskJournal.recent(root: support.appendingPathComponent("tasks"))
        XCTAssertEqual(records.map(\.turn).sorted(), [1, 2, 3])
        await MainActor.run {
            XCTAssertEqual(starts.asked.count, 1)
            // Kept longer ago than the user asked for, it is not taken up: the next command opens a new one.
            runtime.command.rest()
            var old = runtime.command.settings.conversation!
            old.last = Date().addingTimeInterval(-2 * 86_400)
            runtime.command.settings.conversation = old
            runtime.command.run("过了两天")
            XCTAssertTrue(runtime.snapshot.command.detail.contains(L10n.tr("新对话", "new conversation")), runtime.snapshot.command.detail)
        }
        await wait("a new conversation") { runtime.snapshot.command.phase == .done }
        await MainActor.run {
            XCTAssertEqual(starts.asked, ["scripted", nil])
            XCTAssertEqual(runtime.command.turns, 1)
            XCTAssertEqual(runtime.command.settings.conversation?.session, "scripted")
        }
    }

    func testAConversationKeptForGoodIsTakenUpHoweverOldAndOneThatCannotBeGivesWayToANewOne() async throws {
        let script: [(tool: String, arguments: JSONValue)] = [("finish", ["summary": "好"])]
        let (runtime, _, _) = try await MainActor.run { try makeRuntime(script: script) }
        final class Starts { var asked: [String?] = []; var refuse = false }
        let starts = Starts()
        await MainActor.run {
            runtime.command.settings.setHistoryMinutes(-1)
            runtime.command.settings.conversation = CommandConversation(session: "long-ago", last: Date().addingTimeInterval(-400 * 86_400), turns: 41, used: 3_000, size: 8_000)
            runtime.command.openKernel = { resume in
                starts.asked.append(resume)
                return ScriptedKernel(script, session: starts.refuse ? nil : resume)
            }
            runtime.command.run("还记得吗")
        }
        await wait("the task ends") { runtime.snapshot.command.phase == .done }
        await MainActor.run {
            XCTAssertEqual(starts.asked, ["long-ago"])
            XCTAssertEqual(runtime.command.turns, 42)
            // The harness's own app has the conversation open, or it is gone: the kernel cannot take it up.
            runtime.command.rest()
            starts.refuse = true
            runtime.command.run("再来")
        }
        await wait("a new conversation") { runtime.snapshot.command.phase == .done && runtime.command.turns == 1 }
        await MainActor.run {
            XCTAssertEqual(starts.asked, ["long-ago", "long-ago"])
            XCTAssertEqual(runtime.command.settings.conversation?.session, "scripted")
            XCTAssertEqual(runtime.command.settings.conversation?.turns, 1)
            // A setting that changes ends the conversation, as before.
            runtime.command.settings.setStepLimit(12)
            XCTAssertNil(runtime.command.settings.conversation)
            XCTAssertEqual(runtime.command.turns, 0)
            runtime.stop()
        }
    }

    /// What a restart of VibeWand finds: the conversation, how far it has got and how full it is.
    @MainActor
    func testTheConversationIsKnownAgainAfterVibeWandRestartsButNotOnceItIsSpent() {
        let defaults = isolatedDefaults()
        let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults), engineFactory: { _ in TranscriptReplayEngine(previews: []) })
        func restarted() -> CommandController {
            CommandController(settings: CommandSettings(defaults: defaults, credentials: MemoryCredentials()), tools: CommandTools(adapter: AccessibilityAdapter()), voice: voice)
        }
        let settings = CommandSettings(defaults: defaults, credentials: MemoryCredentials())
        settings.conversation = CommandConversation(session: "s-1", last: Date().addingTimeInterval(-600), turns: 7, used: 2_000, size: 8_000)
        XCTAssertEqual(restarted().turns, 0, "kept five minutes by default, and ten have passed")
        settings.setHistoryMinutes(30)
        XCTAssertEqual(restarted().turns, 7)
        XCTAssertEqual(restarted().usage?.used, 2_000)
        settings.conversation?.used = 6_500
        XCTAssertEqual(restarted().turns, 0, "past four fifths of its window it is not carried on")
        settings.conversation?.used = 2_000
        settings.setHistoryMinutes(0)
        XCTAssertEqual(restarted().turns, 0)
    }

    /// The picture a model is shown carries the ids of the latest snapshot where their controls are. No window is captured here.
    func testAPictureOfAWindowIsMarkedWithTheIdsOfItsControls() throws {
        // A plain grey "window" of 300×200 points, captured at twice that.
        let size = CGSize(width: 600, height: 400)
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(CGColor(gray: 0.5, alpha: 1)); canvas.fill(CGRect(origin: .zero, size: size))
        let window = CGRect(x: 100, y: 50, width: 300, height: 200)
        let layout = InterfaceTools.Layout(title: "备忘录", frame: window, marks: [
            (id: "e1", frame: CGRect(x: 120, y: 70, width: 80, height: 30)), (id: "e12", frame: CGRect(x: 300, y: 200, width: 60, height: 24))])
        let picture = try XCTUnwrap(InterfaceTools.mark(try XCTUnwrap(canvas.makeImage()), layout: layout))
        XCTAssertEqual(picture.prefix(2), Data([0xFF, 0xD8]), "a JPEG")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: picture))
        XCTAssertEqual(bitmap.pixelsWide, 600)
        XCTAssertEqual(bitmap.pixelsHigh, 400)
        func colour(_ x: Int, _ y: Int) throws -> NSColor { try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)) }
        // The first control's tag sits at its top-left corner: (120−100, 70−50) points, twice that in pixels, counted from the top.
        let tag = try colour(43, 44)
        XCTAssertGreaterThan(tag.redComponent, 0.7, "\(tag)")
        XCTAssertLessThan(tag.greenComponent, 0.5, "\(tag)")
        // Away from any control the window is as it was.
        let plain = try colour(560, 30)
        XCTAssertEqual(plain.redComponent, plain.greenComponent, accuracy: 0.03, "\(plain)")
        XCTAssertEqual(plain.redComponent, plain.blueComponent, accuracy: 0.03, "\(plain)")
        if let path = ProcessInfo.processInfo.environment["VIBEWAND_COMMAND_OVERLAY_REVIEW"] {
            try picture.write(to: URL(fileURLWithPath: path).appendingPathComponent("marked-window.jpg"))
        }
    }

    /// A captured window is sent no larger than a model reads well, and its marks land where the controls are in what is sent.
    func testALargeWindowIsSentSmallerWithItsMarksInPlace() throws {
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 3200, height: 2000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(CGColor(gray: 0.5, alpha: 1)); canvas.fill(CGRect(x: 0, y: 0, width: 3200, height: 2000))
        let image = try XCTUnwrap(canvas.makeImage())
        XCTAssertEqual(InterfaceTools.pictureSize(image), CGSize(width: 1600, height: 1000))
        // The window is 1600×1000 points, captured at twice that: one point is one pixel of what is sent.
        let layout = InterfaceTools.Layout(title: "", frame: CGRect(x: 0, y: 30, width: 1600, height: 1000),
                                           marks: [(id: "e1", frame: CGRect(x: 800, y: 530, width: 200, height: 60))])
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(InterfaceTools.mark(image, layout: layout))))
        XCTAssertEqual(bitmap.pixelsWide, 1600)
        XCTAssertEqual(bitmap.pixelsHigh, 1000)
        // The tag's top edge, above the letters of the id: (800, 530−30) points is the same pixel of what is sent.
        let tag = try XCTUnwrap(bitmap.colorAt(x: 806, y: 501)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(tag.redComponent - tag.greenComponent, 0.3, "\(tag)")
        let plain = try XCTUnwrap(bitmap.colorAt(x: 806, y: 480)?.usingColorSpace(.sRGB))
        XCTAssertEqual(plain.redComponent, plain.greenComponent, accuracy: 0.03, "\(plain)")
    }

    /// What a window shows is read off its picture on this Mac. No window is captured here: the words are drawn.
    func testTextIsReadOffAPictureWithWhereItStands() throws {
        // 800×300 points drawn at twice that, as a display would show them.
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 1600, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(.white); canvas.fill(CGRect(x: 0, y: 0, width: 1600, height: 600))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
        func draw(_ words: String, x: CGFloat, fromTop y: CGFloat) {
            NSAttributedString(string: words, attributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black]).draw(at: CGPoint(x: x, y: 600 - y - 54))
        }
        draw("Search 搜索歌单", x: 80, fromTop: 60)
        draw("推荐", x: 80, fromTop: 360)
        draw("Play all 播放全部", x: 900, fromTop: 364)
        NSGraphicsContext.restoreGraphicsState()
        let lines = InterfaceTools.read(try XCTUnwrap(canvas.makeImage()), size: CGSize(width: 800, height: 300))
        // Read as a page is: the upper line first, then the lower row from the left.
        XCTAssertEqual(lines.count, 3, "\(lines)")
        guard lines.count == 3 else { return }
        XCTAssertTrue(lines[0].text.contains("搜索歌单") && lines[0].text.contains("Search"), lines[0].text)
        XCTAssertEqual(lines[1].text, "推荐")
        XCTAssertTrue(lines[2].text.contains("播放全部"), lines[2].text)
        // Boxes are in the picture as it is sent, 800×300, from its top left.
        XCTAssertEqual(lines[0].box.midY, 44, accuracy: 12)
        XCTAssertEqual(lines[1].box.minX, 40, accuracy: 10)
        XCTAssertEqual(lines[2].box.midY, 195, accuracy: 12)
        XCTAssertEqual(lines[2].box.minX, 450, accuracy: 12)

        // The window stood at (200, 100) on screen and was 1600×600 points: a point of the picture is twice as far in.
        let seen = WindowPicture(pid: 1, frame: CGRect(x: 200, y: 100, width: 1600, height: 600), size: CGSize(width: 800, height: 300), lines: lines)
        XCTAssertEqual(seen.screen(CGPoint(x: 400, y: 150)), CGPoint(x: 1000, y: 400))
        XCTAssertEqual(seen.text(at: CGPoint(x: lines[1].box.midX, y: lines[1].box.midY)), "推荐")
        XCTAssertNil(seen.text(at: CGPoint(x: 700, y: 20)))
        XCTAssertEqual(seen.count(of: "播放 全部"), 1)
        XCTAssertEqual(seen.count(of: "SEARCH"), 1)
        XCTAssertEqual(seen.count(of: "lofi"), 0)
        let listed = seen.listing.components(separatedBy: "\n")
        XCTAssertEqual(listed.count, 4)
        XCTAssertEqual(listed[2], "t2 \"推荐\" \(Int(lines[1].box.midX)),\(Int(lines[1].box.midY))")
        XCTAssertTrue(WindowPicture(pid: 1, frame: .zero, size: .zero, lines: []).listing.contains("no text"))
    }

    /// A row of tabs is read as one line of words. Each tab is a thing of its own to press, so words that stand
    /// apart are listed apart, while the words of a sentence stay together.
    func testWordsThatStandApartInALineAreListedApart() {
        func word(_ text: String, _ x: CGFloat, _ width: CGFloat) -> WindowPicture.Line { .init(text: text, box: CGRect(x: x, y: 130, width: width, height: 20)) }
        let tabs = InterfaceTools.apart([word("综合", 229, 32), word("单曲", 289, 32), word("歌单", 349, 32)])
        XCTAssertEqual(tabs.map(\.text), ["综合", "单曲", "歌单"])
        XCTAssertEqual(tabs[2].box.midX, 365)
        let sentence = InterfaceTools.apart([word("Why", 100, 34), word("You", 140, 30), word("Go", 176, 22), word("Away...", 204, 60)])
        XCTAssertEqual(sentence.map(\.text), ["Why You Go Away..."])
        XCTAssertEqual(sentence[0].box, CGRect(x: 100, y: 130, width: 164, height: 20))
        XCTAssertEqual(InterfaceTools.apart([]), [])
    }

    /// Lines come from the recogniser in no order a reader would follow: they are put row by row, left to right.
    func testLinesReadOffAPictureAreOrderedAsAPageIsRead() {
        func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> WindowPicture.Line { .init(text: text, box: CGRect(x: x, y: y, width: 80, height: 20)) }
        let ordered = InterfaceTools.rows([line("sidebar 2", 10, 100), line("title", 300, 12), line("sidebar 1", 10, 60), line("card", 300, 104), line("logo", 10, 8)])
        XCTAssertEqual(ordered.map(\.text), ["logo", "title", "sidebar 1", "sidebar 2", "card"])
    }

    /// A command names an app as the user calls it. The system reports the name in its own language only, so the
    /// names an app gives itself in the user's other languages are read from the app.
    func testAnAppIsKnownByItsNameInEachLanguageTheUserReads() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("wand-alias-\(UUID().uuidString.prefix(6))/NeteaseMusic.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        for (language, name) in [("en", "NetEaseMusic"), ("zh-Hans", "网易云音乐")] {
            let folder = app.appendingPathComponent("Contents/Resources/\(language).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "\"CFBundleDisplayName\" = \"\(name)\";\n\"CFBundleName\" = \"\(name)\";\n".write(to: folder.appendingPathComponent("InfoPlist.strings"), atomically: true, encoding: .utf8)
        }
        try #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.wand.alias</string></dict></plist>"#
            .write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        XCTAssertEqual(CommandTools.aliases(app, languages: ["en-CN", "zh-Hans-CN"]), ["NetEaseMusic", "网易云音乐"])
        XCTAssertEqual(CommandTools.aliases(app, languages: ["en-US"]), ["NetEaseMusic"])
        XCTAssertEqual(CommandTools.aliases(app.deletingLastPathComponent().appendingPathComponent("Missing.app")), [])
    }

    /// A window that tells accessibility nothing is not a dead end: the model is sent to its picture, or told what the user has to allow.
    func testAWindowThatPublishesNoControlsIsOneToLookAt() {
        let seeing = InterfaceTools.describe([], window: "", filter: "搜索", truncated: false, seeing: true)
        XCTAssertTrue(seeing.text.contains("ui_screenshot") && seeing.text.contains("ui_click"), seeing.text)
        XCTAssertEqual(seeing.shown, [])
        let blind = InterfaceTools.describe([], window: "", filter: nil, truncated: false).text
        XCTAssertTrue(blind.contains(CommandSettings.sightTitle) && blind.contains("need_user") && !blind.contains("ui_screenshot"), blind)
    }

    func testSettingsCanCheckTheModelAndFailuresAreSaidInTheServicesWords() async throws {
        let (runtime, kernel, _) = try await MainActor.run { try makeRuntime() }
        kernel.usage = (36, 64_000)
        let checked = await runtime.command.probe()
        XCTAssertTrue(checked.ok, checked.detail)
        XCTAssertTrue(checked.detail.contains("64.0k"), checked.detail)
        await MainActor.run {
            XCTAssertEqual(kernel.prompts.count, 1)
            XCTAssertTrue(kernel.prompts[0].hasPrefix("VibeWand · connection test: reply with the single word ok\n"), kernel.prompts[0])
            // The check leaves no conversation behind.
            XCTAssertEqual(runtime.command.turns, 0)
            XCTAssertNil(runtime.command.usage)
            runtime.command.openKernel = { _ in throw RPCError(code: -32603, message: #"Internal error: turn failed: 401: {"message":"Authentication Fails, Your api key: ****0000 is invalid","type":"authentication_error"}"#) }
        }
        let failed = await runtime.command.probe()
        XCTAssertFalse(failed.ok)
        XCTAssertTrue(failed.detail.hasSuffix("401: Authentication Fails, Your api key: ****0000 is invalid"), failed.detail)
        // A setting the kernel refused at start is named in its log, and that is what the user is told.
        let logs = await MainActor.run { runtime.command.support.appendingPathComponent("kernel/logs") }
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try """
            dsh: warning: 1 entry did not activate
            llm-pi-ai (@deepseek-ai/dsh-llm-pi-ai): ValidationError: invalid config:
              - $.providers.vibewand.compat.thinkingFormat expected "openai" | "qwen" but got "nonsense" (at providers.vibewand.compat.thinkingFormat)
            """.write(to: logs.appendingPathComponent("kernel.log"), atomically: true, encoding: .utf8)
        await MainActor.run { runtime.command.openKernel = { _ in throw RPCError(code: -32603, message: #"Internal error: no adapter registered for provider "vibewand""#) } }
        let refused = await runtime.command.probe()
        XCTAssertTrue(refused.detail.hasSuffix(#"compat.thinkingFormat expected "openai" | "qwen" but got "nonsense" (at providers.vibewand.compat.thinkingFormat)"#), refused.detail)
        XCTAssertEqual(CommandController.brief("Internal error: turn failed: Connection error."), "Connection error.")
        XCTAssertEqual(CommandController.brief(#"Internal error: no adapter registered for provider "vibewand""#), #"no adapter registered for provider "vibewand""#)
        XCTAssertEqual(CommandController.brief(#"400: {"error":{"message":"model not found"}}"#), "400: model not found")
        await MainActor.run { runtime.stop() }
    }

    func testNeedUserAndASilentEndingAreShownAsNeedingAttention() async throws {
        let (runtime, kernel, _) = try await MainActor.run { try makeRuntime(script: [("need_user", ["reason": "没有找到这个会话"])]) }
        await MainActor.run { runtime.command.run("打开昨天的会话") }
        await wait("attention") { runtime.snapshot.command.phase == .attention }
        await MainActor.run { XCTAssertEqual(runtime.snapshot.command.text, "没有找到这个会话") }
        // A model that stops without finishing has not completed anything.
        await MainActor.run { kernel.script = []; runtime.command.run("再试一次") }
        await wait("no result") { runtime.snapshot.command.text == L10n.tr("没有得到结果", "No result") }
        await MainActor.run { XCTAssertEqual(runtime.snapshot.command.phase, .attention); runtime.stop() }
    }

    func testAChoiceIsAnsweredWithTheDeviceAndNothingReachesTheAppInFront() async throws {
        let options: JSONValue = [["id": "t-1", "label": "麦克风延迟排查", "detail": "今天"], ["id": "t-2", "label": "蓝牙桥接"], ["id": "t-3", "label": "登录问题"]]
        let (runtime, kernel, _) = try await MainActor.run {
            try makeRuntime(script: [("choose", ["question": "打开哪个会话？", "options": options]), ("finish", ["summary": "好"])])
        }
        await MainActor.run { runtime.command.run("切到麦克风的会话") }
        await wait("the question") { runtime.snapshot.command.phase == .choosing }
        await MainActor.run {
            XCTAssertEqual(runtime.snapshot.command.options, ["麦克风延迟排查 · 今天", "蓝牙桥接", "登录问题"])
            XCTAssertEqual(runtime.snapshot.scope, .command)
            runtime.handle(.right, phase: .pulse); runtime.handle(.right, phase: .pulse); runtime.handle(.right, phase: .pulse)
            XCTAssertEqual(runtime.snapshot.command.selection, 2)
            runtime.handle(.left, phase: .pulse)
            XCTAssertEqual(runtime.snapshot.command.selection, 1)
            // The dictation key does not start typing into whatever is in front while a question waits.
            runtime.handle(.voice, phase: .down); runtime.handle(.voice, phase: .up)
            XCTAssertEqual(runtime.snapshot.command.phase, .choosing)
            runtime.handle(.ok, phase: .down); runtime.handle(.ok, phase: .up)
        }
        await wait("the task ends") { runtime.snapshot.command.phase == .done }
        await MainActor.run {
            XCTAssertEqual(kernel.outcomes.first?.text, #"{"chosen":"t-2"}"#)
            XCTAssertEqual(runtime.snapshot.scope, .reading)
            runtime.stop()
        }
    }

    func testStopEndsAWaitingQuestionAndLateResultsNeverReplaceIt() async throws {
        let (runtime, kernel, _) = try await MainActor.run {
            try makeRuntime(script: [("choose", ["question": "哪个？", "options": [["id": "a", "label": "甲"], ["id": "b", "label": "乙"]]]),
                                     ("finish", ["summary": "不应出现"])])
        }
        await MainActor.run { runtime.command.run("随便") }
        await wait("the question") { runtime.snapshot.command.phase == .choosing }
        await MainActor.run { runtime.handle(.escape, phase: .down); runtime.handle(.escape, phase: .up) }
        await wait("stopped") { runtime.snapshot.command.text == L10n.tr("已停止", "Stopped") }
        await wait("the question is answered as cancelled") { kernel.outcomes.count == 1 }
        try await Task.sleep(nanoseconds: 80_000_000)
        await MainActor.run {
            // The kernel's turn was interrupted: it never reached its next step, and nothing replaced the overlay's line.
            XCTAssertEqual(kernel.outcomes.map(\.text), ["cancelled"])
            XCTAssertEqual(runtime.snapshot.command.text, L10n.tr("已停止", "Stopped"))
            XCTAssertFalse(runtime.snapshot.command.capturesControls)
            runtime.stop()
        }
    }

    func testANewInstructionSupersedesTheOneBeingAsked() async throws {
        let (runtime, kernel, _) = try await MainActor.run {
            try makeRuntime(script: [("choose", ["question": "哪个？", "options": [["id": "a", "label": "甲"], ["id": "b", "label": "乙"]]])])
        }
        await MainActor.run { runtime.command.run("第一句") }
        await wait("the question") { runtime.snapshot.command.phase == .choosing }
        await MainActor.run { kernel.script = [("finish", ["summary": "第二句完成"])]; runtime.command.run("第二句") }
        await wait("the second ends") { runtime.snapshot.command.text == "第二句完成" }
        await MainActor.run { XCTAssertEqual(kernel.prompts.count, 2); runtime.stop() }
    }

    func testCommandKeyDoesNothingUntilTheModeIsTurnedOn() async throws {
        let (runtime, kernel, _) = try await MainActor.run { try makeRuntime(enabled: false) }
        await MainActor.run {
            runtime.command.begin()
            XCTAssertEqual(runtime.snapshot.command.phase, .attention)
            XCTAssertTrue(kernel.prompts.isEmpty)
            XCTAssertEqual(runtime.voiceInput.state, .idle)
            runtime.stop()
        }
    }

    func testHoldingTheDialSpeaksACommandAndTheWordsNeverReachAField() async throws {
        let (runtime, kernel, _) = try await MainActor.run { try makeRuntime(previews: ["切到 Codex"], script: [("finish", ["summary": "完成"])]) }
        final class Dictated { var texts: [String] = [] }
        let dictated = Dictated()
        await MainActor.run {
            runtime.voiceInput.onTranscript = { dictated.texts.append($0) }
            let start = ProcessInfo.processInfo.systemUptime
            runtime.handle(.dial, phase: .down)
            runtime.advanceGestures(now: start + 0.6)
            XCTAssertEqual(runtime.snapshot.command.phase, .listening)
        }
        await wait("recording") { runtime.voiceInput.state == .recording }
        await MainActor.run {
            runtime.handle(.dial, phase: .up)
            runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 1)
        }
        await wait("the task ends") { runtime.snapshot.command.phase == .done }
        await MainActor.run {
            XCTAssertTrue(kernel.prompts.first?.hasPrefix("VibeWand · 切到 Codex\n") == true)
            XCTAssertTrue(dictated.texts.isEmpty)
            runtime.stop()
        }
    }

    // MARK: Overlay and tools

    func testOverlayBarGrowsForACommandAndIsUnchangedWithoutOne() {
        let idle = VoiceHUDSnapshot()
        XCTAssertEqual(SpeechOverlayLayout.barHeight(voice: idle), 48)
        XCTAssertEqual(SpeechOverlayLayout.barHeight(voice: idle, command: CommandHUDSnapshot()), 48)
        let listening = CommandHUDSnapshot(phase: .listening)
        XCTAssertEqual(SpeechOverlayLayout.barHeight(voice: idle, command: listening), 96)
        // The line that names the model and its context has room of its own.
        XCTAssertEqual(SpeechOverlayLayout.barHeight(voice: idle, command: CommandHUDSnapshot(phase: .listening, detail: "deepseek-flash · 新对话")), 116)
        let choosing = CommandHUDSnapshot(phase: .choosing, text: "打开哪个会话？", options: ["甲", "乙", "丙", "丁"])
        XCTAssertGreaterThan(SpeechOverlayLayout.barHeight(voice: idle, command: choosing), SpeechOverlayLayout.barHeight(voice: idle, command: listening))
        XCTAssertEqual(SpeechOverlayLayout.size(template: .vibeKey, expanded: false, mode: .compact, voice: idle, command: choosing).width, 390)
        XCTAssertTrue(choosing.capturesControls)
        XCTAssertFalse(CommandHUDSnapshot(phase: .done).capturesControls)
        XCTAssertFalse(listening.capturesControls)
    }

    func testCommandStatesRenderInTheBarAtTheirLayoutSize() async throws {
        try await MainActor.run {
            let previousMode = UserDefaults.standard.string(forKey: "hudDisplayMode")
            defer { if let previousMode { UserDefaults.standard.set(previousMode, forKey: "hudDisplayMode") } else { UserDefaults.standard.removeObject(forKey: "hudDisplayMode") } }
            let overlay = OverlayController(onControl: { _, _ in XCTFail("Rendering must not send input") })
            overlay.setDisplayMode(.compact)
            let states: [(String, CommandHUDSnapshot)] = [
                ("listening", CommandHUDSnapshot(phase: .listening, status: "命令 · 正在听", text: "切到 Codex 里讨论麦克风的那个会话")),
                ("working", CommandHUDSnapshot(phase: .working, status: "命令 · 查找会话", text: "切到 Codex 里讨论麦克风的那个会话",
                    detail: "deepseek-flash · 上下文 12.4k/1.05M · 1% · 第 2 步 · 每步确认")),
                ("choosing", CommandHUDSnapshot(phase: .choosing, status: "命令 · 请选择", text: "打开哪个会话？",
                    options: ["VibeWand 麦克风延迟排查 · VibekeyPluginCodex · 10-05 14:10", "DualSense 麦克风蓝牙桥接 · 10-04 22:31", "修复登录问题 · webapp"], selection: 1)),
                ("confirming", CommandHUDSnapshot(phase: .confirming, status: "命令 · 请确认", text: "按下「删除会话」？",
                    detail: "deepseek-flash · 上下文 12.9k/1.05M · 1% · 第 3 步 · 只确认有风险的")),
                ("done", CommandHUDSnapshot(phase: .done, status: "命令 · 完成", text: "已切到 Codex 会话「VibeWand 麦克风延迟排查」"))
            ]
            for (name, command) in states {
                var snapshot = HUDSnapshot(); snapshot.connected = true; snapshot.command = command
                overlay.update(snapshot)
                let image = try XCTUnwrap(overlay.previewImage(appearance: NSAppearance(named: .aqua)))
                XCTAssertEqual(image.size, SpeechOverlayLayout.size(template: .vibeKey, expanded: false, mode: .compact, voice: snapshot.voice, command: command), name)
                // Updating never orders the panel front; only the app does that for a live command.
                XCTAssertFalse(overlay.isVisible)
                if let path = ProcessInfo.processInfo.environment["VIBEWAND_COMMAND_OVERLAY_REVIEW"] {
                    XCTAssertTrue(overlay.renderPNG(to: URL(fileURLWithPath: path).appendingPathComponent("command-\(name).png")))
                }
            }
        }
    }

    /// Optional visual evidence of the settings page and the history, from our own hidden views.
    @MainActor
    func testCommandSettingsAndHistoryRenderForReview() async throws {
        guard let path = ProcessInfo.processInfo.environment["VIBEWAND_COMMAND_SETTINGS_REVIEW"] else { throw XCTSkip("Set VIBEWAND_COMMAND_SETTINGS_REVIEW to a folder") }
        _ = NSApplication.shared
        let (runtime, kernel, support) = try makeRuntime(permission: .ask, script: [("list_targets", [:]), ("finish", ["summary": "已列出可以操作的应用"])])
        kernel.usage = (12_400, 1_048_576)
        runtime.command.run("看看有哪些应用可以操作")
        await wait("the task ends") { runtime.snapshot.command.phase == .done }
        let journal = try TaskJournal(root: support.appendingPathComponent("tasks"), now: Date().addingTimeInterval(2))
        journal.record("instruction", ["text": "切到 Codex 里讨论麦克风的那个会话", "app": "Visual Studio Code", "model": "deepseek-flash", "turn": 2])
        journal.note(.thought("用户想去 Codex 里一个关于麦克风的会话。先查会话列表，再打开最匹配的那一个。"))
        journal.note(.toolStarted(id: "1", name: "mcp__vibewand__find_sessions"))
        journal.record("call", ["tool": "find_sessions", "arguments": ["app": "codex", "query": "麦克风"]])
        journal.record("result", ["tool": "find_sessions", "ok": true, "verified": true,
                                  "text": #"{"matched":true,"sessions":[{"folder":"VibekeyPluginCodex","id":"t-101","title":"VibeWand 麦克风延迟排查","updated":"10-05 14:10"}]}"#])
        journal.note(.usage(used: 13_100, size: 1_048_576))
        journal.record("confirmed", ["tool": "open_session"])
        journal.record("call", ["tool": "open_session", "arguments": ["app": "codex", "id": "t-101"]])
        journal.record("result", ["tool": "open_session", "ok": true, "verified": false, "text": #"{"app_in_front":true,"opened":"VibeWand 麦克风延迟排查"}"#])
        journal.note(.usage(used: 13_600, size: 1_048_576))
        journal.record("end", ["reason": "end_turn", "finished": true, "said": "已切到「VibeWand 麦克风延迟排查」（结果未能核对）"])

        let overlay = OverlayController { _, _ in XCTFail("Rendering must not dispatch input") }
        let model = SettingsModel(runtime: runtime, overlay: overlay)
        let oldLanguage = L10n.shared.language
        defer { L10n.shared.language = oldLanguage; runtime.stop() }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func render(_ view: some View, _ size: NSSize, _ name: String) async throws {
            let host = NSHostingView(rootView: AnyView(view.background(Color(nsColor: .windowBackgroundColor))))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [], backing: .buffered, defer: false)
            window.contentView = host; window.appearance = NSAppearance(named: .aqua)
            try await Task.sleep(nanoseconds: 600_000_000)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name))
        }
        for (name, language) in [("zh", AppLanguage.zhHans), ("en", .english)] {
            L10n.shared.language = language
            runtime.command.settings.setKernelMode(.builtIn)
            try await render(CommandSettingsPage(model: model, settings: runtime.command.settings).id(name), NSSize(width: 1100, height: 1500), "settings-\(name).png")
            try await render(CommandHistorySheet(command: runtime.command).id(name), NSSize(width: 940, height: 620), "history-\(name).png")
            // Plugin mode, as it looks on this Mac: with the harness installed here, or saying that none is.
            runtime.command.settings.setKernelMode(.harness)
            try await render(CommandSettingsPage(model: model, settings: runtime.command.settings).id(name + "-plugin"), NSSize(width: 1100, height: 1500), "settings-plugin-\(name).png")
        }
    }

    func testCommandScopeGuidanceNamesConfirmAndStop() {
        let hints = HUDGuidance.hints(template: DeviceTemplateID.vibeKey.template, configuration: GestureConfiguration(), scope: .command, profile: .codex)
        XCTAssertEqual(hints[.ok]?.first?.caption, L10n.tr("确认", "Confirm"))
        XCTAssertEqual(hints[.escape]?.first?.caption, L10n.tr("停止", "Stop"))
        XCTAssertEqual(hints[.left]?.first?.caption, L10n.tr("上一个", "Previous"))
    }

    func testShortcutsAreReadFromPlainNamesAndRiskyOnesWait() {
        XCTAssertEqual(KeyStroke.parse("cmd+p")?.code, 35)
        XCTAssertEqual(KeyStroke.parse("cmd+p")?.flags, .maskCommand)
        XCTAssertEqual(KeyStroke.parse("Ctrl+Shift+Tab")?.flags, [.maskControl, .maskShift])
        XCTAssertEqual(KeyStroke.parse("ctrl+shift+tab")?.code, 48)
        XCTAssertEqual(KeyStroke.parse("escape")?.code, 53)
        XCTAssertEqual(KeyStroke.parse("cmd+shift+]")?.code, 30)
        XCTAssertEqual(KeyStroke.parse("f5")?.code, 96)
        XCTAssertNil(KeyStroke.parse("cmd+p+q"))
        XCTAssertNil(KeyStroke.parse("hyper+x"))
        XCTAssertNil(KeyStroke.parse("cmd"))
        // Return sends from a multi-line field; elsewhere it only confirms a list or a search.
        XCTAssertTrue(KeyStroke.parse("return")!.needsConfirmation(focusedRole: "AXTextArea"))
        XCTAssertFalse(KeyStroke.parse("return")!.needsConfirmation(focusedRole: "AXTextField"))
        XCTAssertFalse(KeyStroke.parse("enter")!.needsConfirmation(focusedRole: "AXComboBox"))
        XCTAssertTrue(KeyStroke.parse("cmd+return")!.needsConfirmation(focusedRole: "AXTextField"))
        XCTAssertTrue(KeyStroke.parse("cmd+delete")!.needsConfirmation(focusedRole: ""))
        XCTAssertTrue(KeyStroke.parse("cmd+q")!.needsConfirmation(focusedRole: ""))
        XCTAssertFalse(KeyStroke.parse("cmd+w")!.needsConfirmation(focusedRole: "AXTextArea"))
        XCTAssertFalse(KeyStroke.parse("delete")!.needsConfirmation(focusedRole: "AXTextArea"))
    }

    func testSnapshotListingKeepsIdsStableUnderAFilterAndSaysWhatWasLeftOut() {
        let element = AXUIElementCreateSystemWide()
        var controls = [
            InterfaceControl(element: element, kind: "tab", label: "Runtime.swift", state: "selected"),
            InterfaceControl(element: element, kind: "tab", label: "Gestures.swift"),
            InterfaceControl(element: element, kind: "button", label: "Run"),
            InterfaceControl(element: element, kind: "text", label: "(unnamed)", state: "has text")
        ]
        let plain = InterfaceTools.describe(controls, window: "VibeWand", filter: nil, truncated: false)
        XCTAssertEqual(plain.text, """
            window "VibeWand"
            e1 tab "Runtime.swift" selected
            e2 tab "Gestures.swift"
            e3 button "Run"
            e4 text "(unnamed)" has text
            """)
        XCTAssertEqual(plain.shown, [0, 1, 2, 3])
        XCTAssertEqual(InterfaceTools.describe(controls, window: "VibeWand", filter: "gestures", truncated: false).text,
                       "window \"VibeWand\"\ne2 tab \"Gestures.swift\"")
        XCTAssertTrue(InterfaceTools.describe(controls, window: "", filter: "nothing", truncated: true).text.contains("no control matches"))
        controls += (0..<InterfaceTools.shownLimit).map { InterfaceControl(element: element, kind: "row", label: "row \($0)") }
        let long = InterfaceTools.describe(controls, window: "", filter: nil, truncated: true).text
        XCTAssertTrue(long.contains("(4 more not shown; pass filter to narrow)"))
        XCTAssertTrue(long.contains("too large to read completely"))
    }

    /// Codex's model button opens a popover at the very end of a long window. What a press brought has to
    /// lead the next listing, or the model never sees it: that is how "set the effort to low" used to end.
    func testSnapshotLeadsWithWhatAnActionBroughtOrChanged() {
        let element = AXUIElementCreateSystemWide()
        var controls = (0..<InterfaceTools.shownLimit + 40).map { InterfaceControl(element: element, kind: "button", label: "chat \($0)") }
        controls.append(InterfaceControl(element: element, kind: "menu", label: "Select effort"))
        controls.append(InterfaceControl(element: element, kind: "item", label: "Select model"))
        controls.append(InterfaceControl(element: element, kind: "status", label: "GPT-6 Astra Extra High, 4 of 5."))
        controls.append(InterfaceControl(element: element, kind: "item", label: "Power", state: "keys: ArrowLeft ArrowRight"))
        let count = controls.count, fresh = Set(count - 4..<count)
        let listing = InterfaceTools.describe(controls, window: "ChatGPT", filter: nil, truncated: false, fresh: fresh)
        let lines = listing.text.components(separatedBy: "\n")
        XCTAssertEqual(Array(lines.prefix(7)), [
            "window \"ChatGPT\"", "new or changed since the last snapshot:",
            "e\(count - 3) menu \"Select effort\"", "e\(count - 2) item \"Select model\"",
            "e\(count - 1) status \"GPT-6 Astra Extra High, 4 of 5.\"", "e\(count) item \"Power\" keys: ArrowLeft ArrowRight",
            "as before:"
        ])
        XCTAssertEqual(lines[7], "e1 button \"chat 0\"")
        // The limit still holds, and the positions printed are the ones a picture marks.
        XCTAssertEqual(listing.shown.count, InterfaceTools.shownLimit)
        XCTAssertEqual(Array(listing.shown.prefix(5)), [count - 4, count - 3, count - 2, count - 1, 0])
        XCTAssertTrue(listing.text.contains("(44 more not shown; pass filter to narrow)"))
        // A filter narrows first; what it leaves is set apart only when part of it is new.
        XCTAssertEqual(InterfaceTools.describe(controls, window: "ChatGPT", filter: "select", truncated: false, fresh: fresh).text,
                       "window \"ChatGPT\"\ne\(count - 3) menu \"Select effort\"\ne\(count - 2) item \"Select model\"")
        // A filter also reaches what a control is known as and how it is worked.
        XCTAssertEqual(InterfaceTools.describe(controls, window: "", filter: "arrow", truncated: false).text, "window \"\"\ne\(count) item \"Power\" keys: ArrowLeft ArrowRight")
        // Another window, or a view that was replaced, is all new: it is listed plainly.
        let replaced = InterfaceTools.describe(Array(controls.suffix(4)), window: "", filter: nil, truncated: false, fresh: Set(0..<4)).text
        XCTAssertFalse(replaced.contains("new or changed"))
        // Codex names its model button after the model; the snapshot marks it with what the adapter knows it as.
        XCTAssertTrue(ApplicationProfile.codex.isModelTrigger(role: "AXPopUpButton", hint: "GPT-6 Astra Extra High"))
        XCTAssertFalse(ApplicationProfile.codex.isModelTrigger(role: "AXPopUpButton", hint: "Select effort"))
        XCTAssertFalse(ApplicationProfile.codex.isModelTrigger(role: "AXMenuItem", hint: "Select model"))
        XCTAssertEqual(KeyStroke.parse("ArrowLeft")?.code, 123)
        XCTAssertEqual(KeyStroke.parse("arrowright")?.code, 124)
    }

    func testMenuTitlesAreMatchedLooselyButNeverInvented() {
        let titles = ["New File", "Open…", "Open Recent", "Save", "", "关闭标签页"]
        XCTAssertEqual(InterfaceTools.match("Open Recent", in: titles), 2)
        XCTAssertEqual(InterfaceTools.match("open", in: titles), 1)
        XCTAssertEqual(InterfaceTools.match("Open...", in: titles), 1)
        XCTAssertEqual(InterfaceTools.match("recent", in: titles), 2)
        XCTAssertEqual(InterfaceTools.match("关闭", in: titles), 5)
        XCTAssertNil(InterfaceTools.match("Export", in: titles))
        XCTAssertNil(InterfaceTools.match("", in: titles))
    }
}
