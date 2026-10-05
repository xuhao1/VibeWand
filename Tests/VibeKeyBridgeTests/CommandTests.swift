import XCTest
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
    private func isolatedDefaults() -> UserDefaults {
        let name = "VibeWand.CommandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    @MainActor private func makeRuntime(enabled: Bool = true, template: DeviceTemplateID = .vibeKey, previews: [String] = ["切到 Codex"],
                                        script: [(tool: String, arguments: JSONValue)] = []) throws -> (BridgeRuntime, ScriptedKernel, URL) {
        let defaults = isolatedDefaults()
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("vw-command-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: support) }
        let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults),
                                         engineFactory: { _ in TranscriptReplayEngine(previews: previews) })
        let settings = CommandSettings(defaults: defaults, credentials: MemoryCredentials())
        let kernel = ScriptedKernel(script)
        let templates = DeviceTemplateStore(defaults: defaults)
        try templates.select(template)
        let runtime = BridgeRuntime(source: UnconfiguredHIDSource(template: template.template), templates: templates, voiceInput: voice) {
            let command = CommandController(settings: settings, tools: CommandTools(adapter: $0), voice: $1, support: support)
            command.openKernel = { kernel }
            return command
        }
        if enabled { settings.setEnabled(true) }
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
            XCTAssertTrue(kernel.prompts[0].hasSuffix("Command: 切到 Codex"))
        }
        let task = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: support.appendingPathComponent("tasks"), includingPropertiesForKeys: nil).first)
        let journal = try String(contentsOf: task.appendingPathComponent("journal.jsonl"), encoding: .utf8)
        XCTAssertTrue(journal.contains(#""kind":"instruction""#) && journal.contains("切到 Codex"))
        XCTAssertTrue(journal.contains(#""kind":"end""#) && journal.contains(#""finished":true"#))
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
            XCTAssertTrue(kernel.prompts.first?.hasSuffix("Command: 切到 Codex") == true)
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
                ("working", CommandHUDSnapshot(phase: .working, status: "命令 · 查找会话", text: "切到 Codex 里讨论麦克风的那个会话")),
                ("choosing", CommandHUDSnapshot(phase: .choosing, status: "命令 · 请选择", text: "打开哪个会话？",
                    options: ["VibeWand 麦克风延迟排查 · VibekeyPluginCodex · 10-05 14:10", "DualSense 麦克风蓝牙桥接 · 10-04 22:31", "修复登录问题 · webapp"], selection: 1)),
                ("confirming", CommandHUDSnapshot(phase: .confirming, status: "命令 · 请确认", text: "按下「删除会话」？")),
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
        XCTAssertEqual(InterfaceTools.describe(controls, window: "VibeWand", filter: nil, truncated: false), """
            window "VibeWand"
            e1 tab "Runtime.swift" selected
            e2 tab "Gestures.swift"
            e3 button "Run"
            e4 text "(unnamed)" has text
            """)
        XCTAssertEqual(InterfaceTools.describe(controls, window: "VibeWand", filter: "gestures", truncated: false),
                       "window \"VibeWand\"\ne2 tab \"Gestures.swift\"")
        XCTAssertTrue(InterfaceTools.describe(controls, window: "", filter: "nothing", truncated: true).contains("no control matches"))
        controls += (0..<InterfaceTools.shownLimit).map { InterfaceControl(element: element, kind: "row", label: "row \($0)") }
        let long = InterfaceTools.describe(controls, window: "", filter: nil, truncated: true)
        XCTAssertTrue(long.contains("(4 more not shown; pass filter to narrow)"))
        XCTAssertTrue(long.contains("too large to read completely"))
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
