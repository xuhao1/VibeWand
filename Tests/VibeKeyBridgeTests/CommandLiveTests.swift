import AppKit
import ApplicationServices
import CoreAudio
import XCTest
import AU05Device
import SpeechInput
import WandAgent
@testable import VibeKeyBridge

/// Opt-in live acceptance of command mode: the production runtime, controller
/// and tools with a real kernel and model, acting on real apps in windows the
/// test opens for itself. Spoken words are replayed as transcripts.
/// VIBEWAND_COMMAND_LIVE lists the scenarios; ordinary unit tests skip them all.
final class CommandLiveTests: XCTestCase {
    private static let environment = ProcessInfo.processInfo.environment

    private static func stopped(_ message: String) -> NSError {
        NSError(domain: "VibeWand.CommandAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func enabled(_ scenario: String) throws {
        let listed = (environment["VIBEWAND_COMMAND_LIVE"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard listed.contains(scenario) else { throw XCTSkip("Requires explicitly enabled live command acceptance: \(scenario)") }
        guard AXIsProcessTrusted() else { throw stopped("The test process lacks Accessibility access") }
    }
    private static func key() throws -> String {
        guard let key = environment["DEEPSEEK_VIBEWAND_DEV"], !key.isEmpty else { throw stopped("Set DEEPSEEK_VIBEWAND_DEV to a key") }
        return key
    }

    /// The DeepSeek Harness installed on this Mac, given a home inside the test's own folder so that the user's is
    /// never touched. Its "desktop" profile has one model row of the kind the harness's apps write.
    private static func installed(in support: URL) throws -> Harness {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = URL(fileURLWithPath: environment["VIBEWAND_HARNESS_APP"] ?? "/Applications/DeepSeek Harness.app")
        let home = support.appendingPathComponent("dsh")
        guard let harness = Harness.installed(desktopApp: app, bundles: repository.appendingPathComponent("kernel"), home: home) else {
            throw stopped("DeepSeek Harness is not installed; plugin mode has nothing to run on")
        }
        let desktop = home.appendingPathComponent("profiles/desktop")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try """
            - id: llm-pi-ai
              name: "@deepseek-ai/dsh-llm-pi-ai"
              config:
                providers:
                  wand-test:
                    api: openai-completions
                    baseURL: https://api.deepseek.com
                    apiKeyEnv: WAND_TEST_API_KEY
                    models:
                      - id: deepseek-flash
                        name: deepseek-flash
                        input: [text, image]
            - id: agent-default-model
              name: "@deepseek-ai/dsh-agent-default-model"
              config:
                provider: wand-test
                model: deepseek-flash

            """.write(to: desktop.appendingPathComponent("cordis.patch.yml"), atomically: true, encoding: .utf8)
        return harness
    }

    // MARK: Reading the desktop

    private static func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }
    private static func frame(_ node: AXUIElement) -> CGRect? {
        guard let position = attribute(node, kAXPositionAttribute), let size = attribute(node, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }
    private static func first(_ role: String, in root: AXUIElement) -> AXUIElement? {
        var queue = [root], index = 0
        while index < queue.count, index < 600 {
            let node = queue[index]; index += 1
            if attribute(node, kAXRoleAttribute) as? String == role { return node }
            queue += attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return nil
    }
    private static func frontBundle() -> String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }
    /// One line of the acceptance record, written at once so that a run can be followed while it happens.
    private static func report(_ line: String) { print("Command acceptance:", line); fflush(stdout) }

    /// A window the test opened. Its state is read back to check each step;
    /// another window or app taking the keyboard ends the run.
    private struct Window {
        let app: NSRunningApplication
        let element: AXUIElement

        /// The app's window with that title, when it is there now.
        static func current(_ bundleID: String, titled marker: String) -> Window? {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
            let windows = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
            return windows.first { (attribute($0, kAXTitleAttribute) as? String ?? "").contains(marker) }.map { Window(app: app, element: $0) }
        }
        static func find(_ bundleID: String, titled marker: String, seconds: Double = 20) async throws -> Window {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if let window = current(bundleID, titled: marker) { return window }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            throw stopped("No \(bundleID) window titled \(marker) is visible to accessibility")
        }
        var title: String { attribute(element, kAXTitleAttribute) as? String ?? "" }
        var owned: Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  let focused = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else { return false }
            return CFEqual(focused, element)
        }
        /// The text of the document this window shows.
        var text: String { first("AXTextArea", in: element).flatMap { attribute($0, kAXValueAttribute) as? String } ?? "" }
        var selected: Int {
            guard let area = first("AXTextArea", in: element), let value = attribute(area, kAXSelectedTextRangeAttribute) else { return 0 }
            var range = CFRange()
            return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range.length : 0
        }
        /// The words that are selected in the document.
        var selection: String { first("AXTextArea", in: element).flatMap { attribute($0, kAXSelectedTextAttribute) as? String } ?? "" }
        func close() {
            guard let button = attribute(element, kAXCloseButtonAttribute) else { return }
            _ = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    // MARK: The bench

    private final class Words: @unchecked Sendable { var text = "" }
    /// Holds the test's key in memory, where the app would read it from the Keychain. nil says a key is on file
    /// without holding one, for runs in which no model is called.
    private struct KeyInMemory: SpeechCredentialStore {
        var key: String?
        func read(account: String) throws -> String? { key }
        func save(_ key: String, account: String) throws {}
        func remove(account: String) throws {}
        func contains(account: String) -> Bool { true }
    }
    private struct Spoken {
        var hud: CommandHUDSnapshot
        /// The tools the gateway ran, in order, and those among them that failed.
        var calls: [String], failed: [String]
        var questions: [String]
    }

    /// The production runtime with everything outside it replaced by something
    /// inert: no device, no microphone, its own preferences and records.
    @MainActor private final class Bench {
        let runtime: BridgeRuntime
        private let words: Words
        private let support: URL
        private let suite: String
        /// The harness this bench runs on in plugin mode, with its home inside the bench's folder.
        let plugin: Harness?
        /// The layout the keyboard listens for when it is the device. A test changes it as the settings would.
        final class Keys { var layout: KeyboardLayout; init(_ layout: KeyboardLayout) { self.layout = layout } }
        let keys: Keys?
        private var previous: NSRunningApplication?

        /// The kernel is started the way the app starts it, on the shipped harness or, with `harness`, as a plugin
        /// of the DeepSeek Harness installed on this Mac. Only the test's key is handed over: `keyless` leaves it out.
        /// With `keyboard` the device is the keyboard itself, listening for that layout's combinations.
        init(scripted: ScriptedKernel? = nil, permission: PermissionMode = .risky, harness: Bool = false, keyless: Bool = false,
             tools: Harness.Tools = .own, sight: Bool = false, history: Int? = nil, keyboard: KeyboardLayout? = nil) throws {
            let words = Words(), suite = "VibeWand.CommandLive.\(UUID().uuidString)"
            let support = FileManager.default.temporaryDirectory.appendingPathComponent("vw-command-live-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            guard let defaults = UserDefaults(suiteName: suite) else { throw stopped("No preferences for the test") }
            // Dictation is VibeWand's own here, so that a held combination is heard by the replayed recogniser
            // and no key is pressed on the user's behalf for another program's dictation.
            if keyboard != nil {
                var speech = SpeechConfiguration()
                speech.mode = .builtIn
                try SpeechPreferences(defaults: defaults).save(speech)
            }
            let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults),
                                             engineFactory: { _ in TranscriptReplayEngine(previews: [words.text]) })
            let key = scripted == nil && !keyless ? try CommandLiveTests.key() : nil
            let plugin = harness ? try CommandLiveTests.installed(in: support) : nil
            let settings = CommandSettings(defaults: defaults, credentials: KeyInMemory(key: key), harness: { $0 == .harness ? plugin : CommandSettings.locate($0) })
            settings.setPermission(permission)
            if harness { settings.setKernelMode(.harness); settings.setHarnessTools(tools) }
            if sight { settings.setSight(true) }
            if let history { settings.setHistoryMinutes(history) }
            // DeepSeek's service over the protocol most endpoints speak; the model and its thinking can be set for a run.
            var model = settings.model
            model.model = environment["VIBEWAND_COMMAND_LIVE_MODEL"] ?? model.model
            model.reasoning = environment["VIBEWAND_COMMAND_LIVE_REASONING"].flatMap(ModelRoute.Reasoning.init(rawValue:)) ?? .automatic
            try settings.setModel(model)
            let templates = DeviceTemplateStore(defaults: defaults)
            var device: any HIDEventSource = UnconfiguredHIDSource(template: templates.selectedTemplate)
            let keys = keyboard.map(Keys.init)
            if let keys {
                _ = try templates.select(.keyboard)
                let source = KeyboardInputSource()
                source.layout = { keys.layout }
                device = source
            }
            runtime = BridgeRuntime(source: device, templates: templates,
                                    sourceFactory: { _, id in UnconfiguredHIDSource(template: id.template) }, voiceInput: voice) {
                let command = CommandController(settings: settings, tools: CommandTools(adapter: $0), voice: $1, support: support)
                if let scripted { command.openKernel = { _ in scripted } }
                // In use an installed harness finds its keys in its own home. Here the key is handed over in the environment and written nowhere.
                if let key { command.prepare = { $0.environment["WAND_TEST_API_KEY"] = key } }
                return command
            }
            self.words = words; self.support = support; self.suite = suite; self.plugin = plugin; self.keys = keys
            runtime.start(demo: false)
        }

        func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func wait(_ stage: String, seconds: Double = 8, until matches: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(seconds)
            while !matches() {
                guard Date() < deadline else { throw stopped("Timed out: \(stage)") }
                try await pause(0.1)
            }
            report(stage)
        }
        /// The screen is taken only once the person at the Mac has paused, and given back by `leave`.
        func idle() async throws {
            try await wait("keyboard and mouse idle", seconds: 600) {
                CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!) > 4
            }
            if previous == nil { previous = NSWorkspace.shared.frontmostApplication }
        }
        func enter(_ window: Window) async throws {
            _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            window.app.activate(options: [])
            try await wait("test window focused", seconds: 6) { window.owned }
        }
        /// Leaves the result on screen for whoever is watching before the windows close.
        func hold() async throws { try await pause(Double(environment["VIBEWAND_COMMAND_LIVE_HOLD"] ?? "") ?? 0) }
        func leave() {
            runtime.stop()
            previous?.activate(options: [])
            // What each instruction did, step by step, for whoever is working out why a run went as it did.
            if let records = environment["VIBEWAND_COMMAND_LIVE_RECORDS"] {
                try? FileManager.default.copyItem(at: support.appendingPathComponent("tasks"), to: URL(fileURLWithPath: records))
            }
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: support)
        }

        /// What the recogniser will report for the next press of the command key.
        func willHear(_ text: String) { words.text = text }

        /// Holds the command key, speaks `text`, and follows the instruction to its end.
        /// A question is answered with the option `answer` returns, or with stop.
        func say(_ text: String, answer: (CommandHUDSnapshot) -> Int? = { _ in nil }) async throws -> Spoken {
            let tasks = support.appendingPathComponent("tasks")
            let before = Set((try? FileManager.default.contentsOfDirectory(atPath: tasks.path)) ?? [])
            willHear(text)
            runtime.command.begin()
            try await wait("recording") { self.runtime.voiceInput.state == .recording }
            runtime.command.end()
            var questions: [String] = [], hud = runtime.command.hud
            let deadline = Date().addingTimeInterval(150)
            while hud.phase != .done, hud.phase != .attention {
                guard Date() < deadline, hud.phase != .idle else { throw stopped("“\(text)” was not carried to an end") }
                if hud.phase == .choosing || hud.phase == .confirming {
                    let asked = hud
                    questions.append(asked.text)
                    if let choice = answer(asked) {
                        for _ in 0..<choice { runtime.command.move(1) }
                        runtime.command.confirm()
                    } else { runtime.command.stop() }
                    try await wait("the answer taken") { self.runtime.command.hud.phase != asked.phase }
                }
                try await pause(0.05)
                hud = runtime.command.hud
            }
            var calls: [String] = [], failed: [String] = []
            let after = (try? FileManager.default.contentsOfDirectory(atPath: tasks.path)) ?? []
            for name in after.sorted() where !before.contains(name) {
                let journal = (try? String(contentsOf: tasks.appendingPathComponent(name).appendingPathComponent("journal.jsonl"), encoding: .utf8)) ?? ""
                for line in journal.split(separator: "\n") {
                    guard let entry = JSONValue(data: Data(line.utf8)), let tool = entry["tool"]?.string else { continue }
                    if entry["kind"]?.string == "call" { calls.append(tool) }
                    if entry["kind"]?.string == "result", entry["ok"]?.bool == false { failed.append(tool) }
                }
            }
            report("“\(text)” → \(calls.joined(separator: " ")) → \(hud.phase): \(hud.text)"
                + (failed.isEmpty ? "" : " (failed: \(failed.joined(separator: " ")))")
                + (questions.isEmpty ? "" : " (asked: \(questions.joined(separator: " | ")))"))
            return Spoken(hud: hud, calls: calls, failed: failed, questions: questions)
        }
    }

    /// A plain-text document in a TextEdit window of its own: where the user "is" when a command is spoken.
    @MainActor
    private func document(_ bench: Bench, _ contents: String = "first line\n") async throws -> (window: Window, file: URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wand-acceptance-\(UUID().uuidString.prefix(6)).txt")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty
        addTeardownBlock {
            // TextEdit saves a changed document as its window closes. The file goes only once the window has:
            // removed sooner, the save fails and a sheet keeps the window, and TextEdit, open.
            for _ in 0..<50 where Window.current("com.apple.TextEdit", titled: file.lastPathComponent) != nil {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            try? FileManager.default.removeItem(at: file)
            guard launched, let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else { return }
            // Gone before the next run looks, or that run would take it for the user's own and leave its successor open.
            app.terminate()
            for _ in 0..<30 where !app.isTerminated { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        try await bench.idle()
        let textEdit = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit"))
        _ = try await NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        let window = try await Window.find("com.apple.TextEdit", titled: file.lastPathComponent)
        try await bench.enter(window)
        return (window, file)
    }

    // MARK: Scenarios

    /// A native window: typing, a key that needs confirmation, a menu item, and switching apps by a spoken name.
    @MainActor
    func testLiveNativeWindowAndAppSwitching() async throws {
        try Self.enabled("textedit")
        let bench = try Bench()
        defer { bench.leave() }
        let (window, _) = try await document(bench)
        defer { window.close() }

        var spoken = try await bench.say("输入 hello from vibewand")
        XCTAssertEqual(spoken.hud.phase, .done)
        XCTAssertTrue(spoken.calls.contains("ui_type"), "\(spoken.calls)")
        try await bench.wait("the words in the document") { window.text.contains("hello from vibewand") }

        // Return in a multi-line field could send a message, so it waits for the user every time.
        var lines = window.text.components(separatedBy: "\n").count
        spoken = try await bench.say("按一下回车键") { _ in 0 }
        XCTAssertEqual(spoken.questions.count, 1, "Return was not put to the user")
        try await bench.wait("the confirmed Return typed") { window.text.components(separatedBy: "\n").count == lines + 1 }
        lines += 1
        spoken = try await bench.say("再按一次回车键")
        XCTAssertEqual(spoken.questions.count, 1, "Return was not put to the user")
        XCTAssertEqual(spoken.hud.phase, .attention)
        try await bench.pause(1)
        XCTAssertEqual(window.text.components(separatedBy: "\n").count, lines, "A refused Return was typed")

        spoken = try await bench.say("用菜单把全部文字选中")
        XCTAssertTrue(spoken.calls.contains("ui_menu"), "\(spoken.calls)")
        try await bench.wait("everything selected") { window.selected == (window.text as NSString).length && window.selected > 0 }

        // The spoken name is Chinese; the app on disk is called Calculator.
        let calculator = "com.apple.calculator"
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: calculator).isEmpty
        defer { if launched { NSRunningApplication.runningApplications(withBundleIdentifier: calculator).first?.terminate() } }
        spoken = try await bench.say("打开计算器")
        XCTAssertEqual(spoken.hud.phase, .done)
        try await bench.wait("Calculator in front") { Self.frontBundle() == calculator }
        spoken = try await bench.say("切回文本编辑")
        try await bench.wait("the document back in front") { window.owned }
        try await bench.hold()
    }

    /// One instruction of your choosing, spoken from a document of the test's own. A choice is answered with its
    /// first option and a confirmation is refused, so nothing is sent or deleted.
    @MainActor
    func testLiveSpokenInstruction() async throws {
        try Self.enabled("say")
        let words = try XCTUnwrap(Self.environment["VIBEWAND_COMMAND_LIVE_SAY"], "Set VIBEWAND_COMMAND_LIVE_SAY to the instruction")
        let bench = try Bench()
        defer { bench.leave() }
        let (window, _) = try await document(bench)
        defer { window.close() }
        let spoken = try await bench.say(words) { $0.phase == .choosing ? 0 : nil }
        XCTAssertNotEqual(spoken.hud.phase, .idle)
        try await bench.hold()
    }

    /// Settings' “save and test”: a real kernel answers one word and reports the context it works with. No app is touched.
    @MainActor
    func testLiveModelCheck() async throws {
        let listed = (Self.environment["VIBEWAND_COMMAND_LIVE"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard listed.contains("probe") else { throw XCTSkip("Requires explicitly enabled live command acceptance: probe") }
        let bench = try Bench()
        defer { bench.leave() }
        let checked = await bench.runtime.command.probe()
        Self.report("model check → \(checked.ok): \(checked.detail)")
        XCTAssertTrue(checked.ok, checked.detail)
        XCTAssertTrue(checked.detail.contains("262.1k"), checked.detail)
        XCTAssertEqual(bench.runtime.command.turns, 0)
    }

    /// Plugin mode as the app starts it, on the DeepSeek Harness installed on this Mac with a home of the test's
    /// own. No key is given, so the model cannot answer; everything before that is the app's own path: asking the
    /// harness its version, writing the profile, loading the bundle and opening a conversation.
    @MainActor
    func testLivePluginModeStartsOnTheInstalledHarness() async throws {
        let listed = (Self.environment["VIBEWAND_COMMAND_LIVE"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard listed.contains("plugin-start") else { throw XCTSkip("Requires explicitly enabled live command acceptance: plugin-start") }
        let bench = try Bench(harness: true, keyless: true)
        defer { bench.leave() }
        let home = try XCTUnwrap(bench.plugin?.home)
        XCTAssertTrue(bench.runtime.command.settings.active)
        let checked = await bench.runtime.command.probe()
        Self.report("plugin mode start → \(checked.ok): \(checked.detail)")
        XCTAssertFalse(checked.ok)
        XCTAssertTrue(checked.detail.contains("WAND_TEST_API_KEY"), "the harness got as far as asking for the model's key: \(checked.detail)")
        // The conversation opened, so the harness said what it serves: the profile's own route beside its DeepSeek one.
        let served = bench.runtime.command.catalog.map(\.id)
        Self.report("the harness serves \(served)")
        XCTAssertTrue(served.contains("wand-test/deepseek-flash") && served.contains { $0.hasPrefix("deepseek-official/") }, "\(served)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("profiles/vibewand/package.json").path))
        XCTAssertEqual(bench.runtime.command.settings.modelName, "deepseek-flash")
    }

    /// Plugin mode against a real window: the installed harness runs the coordinator and the same tools act.
    @MainActor
    func testLivePluginModeOperatesARealWindow() async throws {
        try Self.enabled("plugin")
        let bench = try Bench(harness: true)
        defer { bench.leave() }
        let home = try XCTUnwrap(bench.plugin?.home)
        let (window, _) = try await document(bench)
        defer { window.close() }

        var spoken = try await bench.say("输入 hello from the harness")
        XCTAssertEqual(spoken.hud.phase, .done)
        XCTAssertTrue(spoken.calls.contains("ui_type"), "\(spoken.calls)")
        try await bench.wait("the words in the document") { window.text.contains("hello from the harness") }
        Self.report("overlay detail: \(spoken.hud.detail)")
        XCTAssertTrue(spoken.hud.detail.hasPrefix("deepseek-flash") && spoken.hud.detail.contains("%"), spoken.hud.detail)

        let calculator = "com.apple.calculator"
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: calculator).isEmpty
        defer { if launched { NSRunningApplication.runningApplications(withBundleIdentifier: calculator).first?.terminate() } }
        spoken = try await bench.say("打开计算器")
        try await bench.wait("Calculator in front") { Self.frontBundle() == calculator }
        spoken = try await bench.say("切回文本编辑")
        try await bench.wait("the document back in front") { window.owned }

        // The three commands are one conversation, kept in the harness's own store under the folder named VibeWand.
        let store = home.appendingPathComponent("sessions")
        let folders = try FileManager.default.contentsOfDirectory(atPath: store.path)
        XCTAssertEqual(folders.count, 1, "\(folders)")
        XCTAssertTrue(folders[0].hasSuffix("-harness-VibeWand--"), folders[0])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.appendingPathComponent(folders[0]).path).count, 1)
        try await bench.hold()
    }

    /// A conversation outlives its kernel: the process is let go, and the next command takes the same conversation up.
    @MainActor
    func testLiveConversationIsTakenUpAfterTheKernelRests() async throws {
        try Self.enabled("resume")
        let bench = try Bench(history: 1_440)
        defer { bench.leave() }
        let (window, _) = try await document(bench)
        defer { window.close() }
        var spoken = try await bench.say("输入 wand-alpha-7")
        XCTAssertEqual(spoken.hud.phase, .done)
        try await bench.wait("the word in the document") { window.text.contains("wand-alpha-7") }
        let kept = try XCTUnwrap(bench.runtime.command.settings.conversation?.session)
        // Commands stop coming: the kernel process goes, the conversation stays in its store.
        bench.runtime.command.rest()
        try await bench.pause(3)
        guard window.owned else { throw Self.stopped("The test window lost the keyboard; run stopped") }
        spoken = try await bench.say("把我上一条让你输入的那个词，原样再输入一遍")
        try await bench.wait("the word typed a second time") { window.text.components(separatedBy: "wand-alpha-7").count == 3 }
        XCTAssertEqual(bench.runtime.command.settings.conversation?.session, kept, "the second command opened a new conversation")
        XCTAssertEqual(bench.runtime.command.turns, 2)
        Self.report("overlay detail after the conversation was taken up: \(spoken.hud.detail)")
        try await bench.hold()
    }

    /// Seeing turned on: the model asks for a picture of the window being operated and reads what only shows there.
    /// The picture is of the document this test opened and of nothing else.
    @MainActor
    func testLiveModelReadsTheWindowFromItsPicture() async throws {
        try Self.enabled("sight")
        guard CGPreflightScreenCaptureAccess() else { throw Self.stopped("The test process may not record the screen") }
        let bench = try Bench(sight: true)
        defer { bench.leave() }
        // The controls of a document window name no text: what the document says is only in the picture.
        let (window, _) = try await document(bench, "the wand sees ZQ47 here\n")
        defer { window.close() }
        let spoken = try await bench.say("看一眼这个窗口，文档里写的那个四位编号是什么？只告诉我编号")
        XCTAssertTrue(spoken.calls.contains("ui_screenshot"), "\(spoken.calls)")
        XCTAssertEqual(spoken.hud.phase, .done)
        XCTAssertTrue(spoken.hud.text.uppercased().contains("ZQ47"), spoken.hud.text)
        // What the model was shown is kept beside the record, as it was sent.
        let record = try XCTUnwrap(bench.runtime.command.history().first)
        let shown = try XCTUnwrap(record.lines.first { $0["image"] != nil }?["image"]?.string)
        let picture = try XCTUnwrap(NSImage(contentsOf: record.directory.appendingPathComponent(shown)))
        Self.report("the picture the model saw: \(Int(picture.size.width))×\(Int(picture.size.height)), kept at \(record.directory.appendingPathComponent(shown).path)")
        XCTAssertGreaterThan(picture.size.width, 200)
        if let copy = Self.environment["VIBEWAND_COMMAND_LIVE_KEEP"] {
            try? FileManager.default.copyItem(at: record.directory.appendingPathComponent(shown), to: URL(fileURLWithPath: copy))
        }
        try await bench.hold()
    }

    /// Seeing in plugin mode: the installed harness hands the picture to the model, and keeps it with the
    /// conversation in its own store, where its apps show the conversation.
    @MainActor
    func testLivePluginModeKeepsThePictureWithTheConversation() async throws {
        try Self.enabled("plugin-sight")
        guard CGPreflightScreenCaptureAccess() else { throw Self.stopped("The test process may not record the screen") }
        let bench = try Bench(harness: true, sight: true)
        defer { bench.leave() }
        let home = try XCTUnwrap(bench.plugin?.home)
        let (window, _) = try await document(bench, "the wand sees ZQ47 here\n")
        defer { window.close() }
        let spoken = try await bench.say("看一眼这个窗口，文档里写的那个四位编号是什么？只告诉我编号")
        XCTAssertTrue(spoken.calls.contains("ui_screenshot"), "\(spoken.calls)")
        XCTAssertEqual(spoken.hud.phase, .done)
        XCTAssertTrue(spoken.hud.text.uppercased().contains("ZQ47"), spoken.hud.text)
        // The kernel process lets go, and what the harness has of the conversation is on disk.
        bench.runtime.command.rest()
        try await bench.pause(3)
        let files = FileManager.default.enumerator(at: home, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        let kept = files.filter { !$0.path.contains("/profiles/") && !$0.hasDirectoryPath }.map { $0.path.components(separatedBy: "/dsh/").last ?? $0.lastPathComponent }
        Self.report("the harness's home holds: \(kept.sorted().map { String($0.prefix(60)) })")
        XCTAssertTrue(kept.contains { $0.hasPrefix("attachments/") }, "the picture is not in the harness's store: \(kept)")
        if let copy = Self.environment["VIBEWAND_COMMAND_LIVE_KEEP_HOME"] {
            try? FileManager.default.copyItem(at: home, to: URL(fileURLWithPath: copy))
        }
        try await bench.hold()
    }

    /// The pointer goes where the model points in the picture: a word it finds there is double-clicked, which
    /// selects it. The selection is read back from the document this test opened.
    @MainActor
    func testLiveModelPointsAtWhatItSeesInTheWindow() async throws {
        try Self.enabled("pointer")
        guard CGPreflightScreenCaptureAccess() else { throw Self.stopped("The test process may not record the screen") }
        let bench = try Bench(sight: true)
        defer { bench.leave() }
        let (window, _) = try await document(bench, "alpha\n\nbravo\n\ncharlie\n")
        defer { window.close() }
        // The pointer is the user's: it goes back where it was.
        let pointer = CGEvent(source: nil)?.location
        defer { if let pointer { SystemPointer.move(to: pointer) } }
        let spoken = try await bench.say("看一眼这个窗口，用指针双击文档里 bravo 这个词")
        XCTAssertTrue(spoken.calls.contains("ui_screenshot") && spoken.calls.contains("ui_click"), "\(spoken.calls)")
        try await bench.wait("the word selected by the double click") { window.selection == "bravo" }
        try await bench.hold()
    }

    /// Whether an app is sounding: one of its processes is sending audio out.
    private static func sounding(_ app: NSRunningApplication) -> Bool {
        func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<T>.size)
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes) == noErr else { return false }
        return processes.contains { process in
            var pid: pid_t = 0, running: UInt32 = 0
            guard read(process, kAudioProcessPropertyPID, &pid), read(process, kAudioProcessPropertyIsRunningOutput, &running), running != 0 else { return false }
            // A browser-built app plays through a helper process of its own.
            return pid == app.processIdentifier || ProcessTree.descends(pid, from: app.processIdentifier)
        }
    }

    /// A window that publishes no controls. NetEase Cloud Music draws its whole window itself, so a snapshot of it
    /// is empty and it is operated from its picture: the text read there, the pointer and the keyboard. What is
    /// read back is that the app is sounding. It is the user's own app and account: music plays for a moment and
    /// its queue changes; playback is stopped again when it was silent before, and the app is quit when the test started it.
    @MainActor
    private func playInNetEaseCloudMusic(_ bench: Bench) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw Self.stopped("The test process may not record the screen") }
        guard let location = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.netease.163music") else {
            throw Self.stopped("NetEase Cloud Music is not installed")
        }
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.163music").isEmpty
        let pointer = CGEvent(source: nil)?.location
        defer { if let pointer { SystemPointer.move(to: pointer) } }
        try await bench.idle()
        let app = try await NSWorkspace.shared.openApplication(at: location, configuration: NSWorkspace.OpenConfiguration())
        defer { if launched { app.terminate() } }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        try await bench.wait("NetEase Cloud Music in front with a window", seconds: 30) {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && Self.attribute(element, kAXFocusedWindowAttribute) != nil
        }
        // A window that has just opened is still loading its page.
        try await bench.pause(launched ? 8 : 1)
        let silent = !Self.sounding(app)
        let spoken = try await bench.say(Self.environment["VIBEWAND_COMMAND_LIVE_SAY"] ?? "在网易云音乐里搜一个适合编程时听的歌单，打开它并开始播放")
        Self.report("overlay detail: \(spoken.hud.detail)")
        XCTAssertTrue(spoken.calls.contains("ui_screenshot") && spoken.calls.contains("ui_click"), "\(spoken.calls)")
        XCTAssertEqual(spoken.hud.phase, .done, spoken.hud.text)
        try await bench.wait("NetEase Cloud Music sounding", seconds: 20) { Self.sounding(app) }
        // More of a page is brought into view with the keyboard. The page cannot be asked where it stands, so
        // it is looked at: lines in the middle of it that are still where they were say it did not move.
        let eye = InterfaceTools()
        func page() async -> Set<String> {
            Set((await eye.picture(pid: app.processIdentifier)).text.split(separator: "\n").filter { line in
                guard line.hasPrefix("t"), let place = line.split(separator: " ").last?.split(separator: ","), place.count == 2,
                      let x = Int(place[0]), let y = Int(place[1]) else { return false }
                return x > 400 && (250...800).contains(y)
            }.map(String.init))
        }
        let before = await page()
        let paged = try await bench.say("把这个歌单页面往下翻一页")
        XCTAssertTrue(paged.calls.contains("ui_key"), "\(paged.calls)")
        let after = await page(), stayed = before.intersection(after).count
        Self.report("of \(before.count) lines in the middle of the page, \(stayed) are where they were a page further down")
        XCTAssertGreaterThan(before.count, 5)
        XCTAssertLessThan(stayed * 3, before.count, "the page did not move: \(before.intersection(after).prefix(5))")
        try await bench.hold()
        guard silent, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
        // Space is the app's own key for play and pause; it is sent to the app alone.
        KeyStroke.parse("space")?.post(to: app.processIdentifier)
        try await bench.wait("playback stopped again", seconds: 10) { !Self.sounding(app) }
    }

    @MainActor
    func testLiveAWindowWithoutControlsIsOperatedFromItsPicture() async throws {
        try Self.enabled("netease")
        let bench = try Bench(sight: true)
        defer { bench.leave() }
        try await playInNetEaseCloudMusic(bench)
    }

    /// The same on the installed harness with its own tools handed over, which is how the owner runs it.
    @MainActor
    func testLivePluginModeOperatesAWindowWithoutControlsFromItsPicture() async throws {
        try Self.enabled("plugin-netease")
        let bench = try Bench(harness: true, tools: .all, sight: true)
        defer { bench.leave() }
        try await playInNetEaseCloudMusic(bench)
    }

    /// Plugin mode with the harness's own tools handed over: one command uses a tool of the harness and a tool of
    /// VibeWand's, and the record shows both.
    @MainActor
    func testLivePluginModeWithTheHarnessToolsOperatesARealWindow() async throws {
        try Self.enabled("plugin-tools")
        let bench = try Bench(harness: true, tools: .all)
        defer { bench.leave() }
        let (window, _) = try await document(bench)
        defer { window.close() }
        let spoken = try await bench.say("用 bash 工具运行 echo wand-$((40+2)) ，然后把它输出的那个词输入到这个文档里")
        XCTAssertEqual(spoken.hud.phase, .done, spoken.hud.text)
        XCTAssertTrue(spoken.calls.contains("bash") && spoken.calls.contains("ui_type"), "\(spoken.calls)")
        try await bench.wait("the command's output in the document") { window.text.contains("wand-42") }
        Self.report("overlay detail: \(spoken.hud.detail)")
        try await bench.hold()
    }

    /// The permission modes with a real model: every step put to the user, then nothing asked at all.
    /// The overlay's line under the command names the model and how full its context is.
    @MainActor
    func testLivePermissionModes() async throws {
        try Self.enabled("permission")
        let bench = try Bench(permission: .ask)
        defer { bench.leave() }
        let (window, _) = try await document(bench)
        defer { window.close() }

        var spoken = try await bench.say("输入 asked first") { _ in 0 }
        XCTAssertEqual(spoken.hud.phase, .done)
        XCTAssertFalse(spoken.questions.isEmpty, "typing was not put to the user")
        try await bench.wait("the confirmed words in the document") { window.text.contains("asked first") }
        Self.report("overlay detail: \(spoken.hud.detail)")
        XCTAssertTrue(spoken.hud.detail.contains("deepseek") && spoken.hud.detail.contains("%"), spoken.hud.detail)

        spoken = try await bench.say("输入 never typed")
        XCTAssertFalse(spoken.questions.isEmpty, "typing was not put to the user")
        try await bench.pause(1)
        XCTAssertFalse(window.text.contains("never typed"), "A refused step was carried out")

        // Switching apps is navigation, and under this mode navigation is asked about too.
        let calculator = "com.apple.calculator"
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: calculator).isEmpty
        defer { if launched { NSRunningApplication.runningApplications(withBundleIdentifier: calculator).first?.terminate() } }
        spoken = try await bench.say("打开计算器") { _ in 0 }
        XCTAssertEqual(spoken.questions.count, 1, "switching apps was not put to the user: \(spoken.questions)")
        try await bench.wait("Calculator in front after the confirmation") { Self.frontBundle() == calculator }
        spoken = try await bench.say("切回文本编辑") { _ in 0 }
        try await bench.wait("the document back in front") { window.owned }

        // Bypass: Return in a multi-line field, which waits for the user in the other modes, goes straight through.
        bench.runtime.command.settings.setPermission(.bypass)
        let lines = window.text.components(separatedBy: "\n").count
        spoken = try await bench.say("按一下回车键")
        XCTAssertEqual(spoken.questions, [], "bypass asked a question")
        try await bench.wait("Return typed without a question") { window.text.components(separatedBy: "\n").count == lines + 1 }
        try await bench.hold()
    }

    /// Reads and presses, and nothing else: an editor takes no keys from a test.
    @MainActor private final class PressOnly: ToolHost {
        let tools: CommandTools
        private(set) var performed: [String] = []
        init(_ tools: CommandTools) { self.tools = tools }
        // The tools' own judgement stands: with nobody to ask, a press that would send or delete is declined.
        func confirm(_ tool: String, _ arguments: JSONValue, every: Bool) async -> Bool? { await tools.confirm(tool, arguments, every: every) }
        func perform(_ tool: String, _ arguments: JSONValue) async -> ToolOutcome {
            performed.append(tool)
            guard ["list_targets", "ui_snapshot", "ui_press"].contains(tool) else {
                return .failure("\(tool) is not available in this window. Read it with ui_snapshot and press with ui_press.")
            }
            return await tools.perform(tool, arguments)
        }
    }

    /// An Electron editor: its tabs are read from the accessibility tree and one is pressed by name.
    @MainActor
    func testLiveTabsInVisualStudioCode() async throws {
        try Self.enabled("code")
        let code = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wand-acceptance-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = ["wand-alpha.txt", "wand-beta.txt", "wand-gamma.txt"].map { folder.appendingPathComponent($0) }
        for file in files { try "\(file.lastPathComponent)\n".write(to: file, atomically: true, encoding: .utf8) }
        let bench = try Bench(scripted: ScriptedKernel())
        defer { bench.leave(); try? FileManager.default.removeItem(at: folder) }
        try await bench.idle()
        let opener = Process()
        opener.executableURL = code.appendingPathComponent("Contents/Resources/app/bin/code")
        opener.arguments = ["--new-window"] + files.map(\.path)
        try opener.run()
        // The first file named is the one shown.
        let window = try await Window.find("com.microsoft.VSCode", titled: "wand-alpha.txt", seconds: 30)
        defer { window.close() }
        try await bench.enter(window)

        // A kernel of this test's own, on the shipped harness, so that only presses reach VS Code.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vw-command-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let harness = try XCTUnwrap(CommandSettings.locate(.builtIn), "Set VIBEWAND_KERNEL_RESOURCES to the folder holding the assembled kernel")
        let route = ModelRoute(wire: .openAIChat, baseURL: "https://api.deepseek.com", model: "deepseek-flash", key: try Self.key())
        let kernel = try await KernelSession.open(try harness.launch(version: Harness.verified[0], support: home, models: .route(route)))
        defer { Task { await kernel.shutdown() } }
        let tools = CommandTools(adapter: bench.runtime.adapter)
        for (words, tab) in [("打开 wand beta 那个标签页", "wand-beta.txt"), ("不是这个，换成 gamma 那个", "wand-gamma.txt")] {
            guard window.owned else { throw Self.stopped("The test window lost the keyboard; run stopped") }
            tools.captureSource()
            let host = PressOnly(tools), gateway = Gateway(host: host)
            let prompt = CoordinatorPrompt.task(words, frontApp: tools.source?.name ?? "", window: tools.source?.window ?? "")
            _ = try await kernel.run(prompt, tools: { await gateway.call($0, $1) }) { _ in }
            let ending = await gateway.ending
            Self.report("“\(words)” → \(host.performed.joined(separator: " ")) → \(String(describing: ending))")
            XCTAssertTrue(host.performed.contains("ui_press"), "\(host.performed)")
            try await bench.wait("\(tab) shown") { window.title.contains(tab) }
        }
        try await bench.hold()
    }

    /// Codex's own chat list and link: the chat named in the command is the one the window shows afterwards.
    @MainActor
    func testLiveCodexChatIsOpenedByItsLink() async throws {
        try Self.enabled("codex")
        let codexID = "com.openai.codex"
        let codex = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: codexID).first, "Codex is not running")
        let executable = try XCTUnwrap(CodexAppServer.locate(desktopApp: codex.bundleURL))
        let server = try CodexAppServer(executable: executable)
        let chats = try await server.sessions(limit: 60)
        server.stop()

        /// Codex shows the open chat's title in the strip at the top of its window; the sidebar's copies sit lower.
        func shown() -> Set<String> {
            let app = AXUIElementCreateApplication(codex.processIdentifier)
            guard let window = Self.attribute(app, kAXFocusedWindowAttribute), let bounds = Self.frame(window as! AXUIElement) else { return [] }
            var texts: Set<String> = [], queue = [window as! AXUIElement], index = 0
            while index < queue.count, index < 6000 {
                let node = queue[index]; index += 1
                guard Self.attribute(node, kAXRoleAttribute) as? String == "AXStaticText" else {
                    queue += Self.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
                    continue
                }
                if let frame = Self.frame(node), frame.minY < bounds.minY + 45, let text = Self.attribute(node, kAXValueAttribute) as? String { texts.insert(text) }
            }
            return texts
        }

        let bench = try Bench()
        defer { bench.leave() }
        try await bench.idle()
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(codex.processIdentifier), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        codex.activate(options: [])
        try await bench.wait("Codex in front") { Self.frontBundle() == codexID }
        // What the strip shows before anything is asked: the open chat's title is in it, and must be again at the end.
        var before: Set<String> = []
        try await bench.wait("the title strip readable", seconds: 10) { before = shown(); return before.count > 1 }
        let wanted = try XCTUnwrap(chats.first { $0.title.count >= 4 && !before.contains($0.title) })

        let (window, _) = try await document(bench)
        defer { window.close() }
        var spoken = try await bench.say("切到 Codex 里「\(wanted.title)」那个会话") { _ in 0 }
        XCTAssertEqual(spoken.hud.phase, .done)
        XCTAssertTrue(spoken.calls.contains("open_session"), "\(spoken.calls)")
        try await bench.wait("Codex in front") { Self.frontBundle() == codexID }
        var during: Set<String> = []
        try await bench.wait("the named chat shown", seconds: 10) { during = shown(); return during.contains(wanted.title) }
        try await bench.hold()

        // Back to where the user was, by the window's own Back button: the interface tools on an Electron app.
        let earlier = before.subtracting(during)
        XCTAssertFalse(earlier.isEmpty, "The earlier chat had no title to return to")
        spoken = try await bench.say("点一下窗口左上角的后退按钮")
        XCTAssertTrue(spoken.calls.contains("ui_press"), "\(spoken.calls)")
        try await bench.wait("the earlier chat shown again", seconds: 10) { shown().isSuperset(of: earlier) }
    }

    /// Codex's model button opens a popover at the end of a long window: an effort row set with the arrow keys and
    /// read back from what the popover announces, and a model list behind "Select model". Both are changed by a
    /// spoken command and read back from the button, and both are put back before the test ends.
    @MainActor
    func testLiveCodexEffortAndModelAreSetInTheirPopover() async throws {
        try Self.enabled("codex-model")
        let codexID = "com.openai.codex"
        let codex = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: codexID).first, "Codex is not running")
        let pid = codex.processIdentifier, application = AXUIElementCreateApplication(pid)

        func nodes(_ role: String) -> [AXUIElement] {
            guard let window = Self.attribute(application, kAXFocusedWindowAttribute) else { return [] }
            var found: [AXUIElement] = [], stack = [window as! AXUIElement], visited = 0
            while let node = stack.popLast(), visited < 20_000 {
                visited += 1
                if Self.attribute(node, kAXRoleAttribute) as? String == role { found.append(node) }
                stack += (Self.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).reversed()
            }
            return found
        }
        func title(_ node: AXUIElement) -> String { Self.attribute(node, kAXTitleAttribute) as? String ?? "" }
        /// The composer's button is named after the model and its effort; while its popover is open it is named after the popover.
        var buttonID = ""
        func button() -> AXUIElement? {
            nodes("AXPopUpButton").first {
                buttonID.isEmpty ? ApplicationProfile.isCodexModelTrigger(hint: title($0).lowercased()) : Self.attribute($0, "AXDOMIdentifier") as? String == buttonID
            }
        }
        func open() -> Bool { button().map { Self.attribute($0, "AXExpanded") as? Bool == true } ?? false }
        /// The button opens its popover; with Codex in front only Escape closes it again.
        func show(_ wanted: Bool) async throws {
            for _ in 0..<2 where open() != wanted {
                if wanted { _ = button().map { AXUIElementPerformAction($0, kAXPressAction as CFString) } } else { KeyStroke(code: 53).post(to: pid) }
                try await Task.sleep(nanoseconds: 700_000_000)
            }
        }
        /// "GPT-6 Astra Extra High, 4 of 5." while the popover shows its effort row.
        func level() -> (name: String, step: Int)? {
            for text in nodes("AXStaticText").compactMap({ Self.attribute($0, kAXValueAttribute) as? String }) {
                guard let match = text.firstMatch(of: #/^(.+), (\d+) of \d+\.$/#), let step = Int(match.2) else { continue }
                return (String(match.1), step)
            }
            return nil
        }
        func item(_ name: String) -> AXUIElement? { nodes("AXMenuItem").first { title($0) == name } }
        func arrow(_ code: CGKeyCode) async throws {
            if let power = item("Power") { AXUIElementSetAttributeValue(power, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
            KeyStroke(code: code).post(to: pid)
            try await Task.sleep(nanoseconds: 400_000_000)
        }

        let bench = try Bench()
        defer { bench.leave() }
        try await bench.idle()
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        codex.activate(options: [])
        try await bench.wait("Codex in front") { Self.frontBundle() == codexID }
        var before = ""
        try await bench.wait("the model button readable", seconds: 10) { before = button().map(title) ?? ""; return !before.isEmpty }
        buttonID = button().flatMap { Self.attribute($0, "AXDOMIdentifier") as? String } ?? ""
        // Where things stand, read from the popover itself: the step of the effort row and the model that is checked.
        try await show(true)
        let start = try XCTUnwrap(level(), "The popover does not announce its effort")
        _ = item("Select model").map { AXUIElementPerformAction($0, kAXPressAction as CFString) }
        try await Task.sleep(nanoseconds: 700_000_000)
        let models = nodes("AXMenuItem").map(title).filter { !$0.isEmpty && !$0.hasPrefix("Default") }
        let checked = try XCTUnwrap(nodes("AXMenuItem").first { (Self.attribute($0, kAXValueAttribute) as? NSNumber)?.intValue == 1 }.map(title), "No model is checked")
        try await show(false)
        XCTAssertFalse(open())
        Self.report("Codex stands at “\(before)”, step \(start.step); models: \(models.joined(separator: ", "))")

        /// Puts the model and the effort back by the popover's own controls, whatever the commands left behind.
        func putBack() async throws {
            // Start from the popover's first view, whichever one a command left showing.
            try await show(false)
            guard button().map(title) != before else { return }
            try await show(true)
            if !(level()?.name.hasPrefix(checked) ?? false) {
                _ = item("Select model").map { AXUIElementPerformAction($0, kAXPressAction as CFString) }
                try await Task.sleep(nanoseconds: 700_000_000)
                _ = item(checked).map { AXUIElementPerformAction($0, kAXPressAction as CFString) }
                try await Task.sleep(nanoseconds: 900_000_000)
                try await show(false); try await show(true)
            }
            for _ in 0..<8 {
                guard let now = level(), now.step != start.step else { break }
                try await arrow(now.step < start.step ? 124 : 123)
            }
            try await show(false)
            Self.report("put back by the test: “\(button().map(title) ?? "")”")
        }

        do {
            // The user's own words, as the recogniser wrote them.
            var spoken = try await bench.say("强度调到 low。")
            var shown = ""
            try await bench.wait("another effort on the button", seconds: 10) { shown = button().map(title) ?? ""; return !open() && !shown.isEmpty && shown != before }
            Self.report("after the effort command: “\(shown)”")
            XCTAssertEqual(spoken.hud.phase, .done, spoken.hud.text)
            XCTAssertTrue(spoken.calls.contains("ui_key"), "\(spoken.calls)")
            try await bench.hold()

            let other = try XCTUnwrap(models.first { $0 != checked }, "Only one model is offered")
            spoken = try await bench.say("把模型换成 \(other)。")
            try await bench.wait("the other model on the button", seconds: 10) { shown = button().map(title) ?? ""; return !open() && shown.hasPrefix(other) }
            Self.report("after the model command: “\(shown)”")
            XCTAssertEqual(spoken.hud.phase, .done, spoken.hud.text)
            try await bench.hold()

            spoken = try await bench.say("把模型换回 \(checked)，强度调回去，让按钮显示 \(before)。")
            Self.report("after the command that undoes both: “\(button().map(title) ?? "")”")
        } catch {
            try? await putBack()
            throw error
        }
        try await putBack()
        try await bench.wait("the model and effort as they were", seconds: 10) { !open() && button().map(title) == before }
    }

    /// An app without a chat list: its own search is opened with the keywords in it, and the dial takes over from there.
    @MainActor
    func testLiveSearchIsOpenedWithTheKeywords() async throws {
        // Codex is asked for a word none of its listed chats has, so that its own search is what remains.
        let apps = ["claude": ("Claude", "com.anthropic.claudefordesktop", "vibewand"), "feishu": ("飞书", "com.electron.lark", "vibewand"),
                    "codex": ("Codex", "com.openai.codex", "zzqx")]
        guard let name = apps.keys.first(where: { (try? Self.enabled("search-\($0)")) != nil }), let (spokenName, bundleID, keyword) = apps[name] else {
            throw XCTSkip("Requires explicitly enabled live command acceptance: search-claude, search-feishu or search-codex")
        }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, "\(spokenName) is not running")
        let bench = try Bench()
        defer { bench.leave() }
        let (window, _) = try await document(bench)
        defer { window.close() }

        let spoken = try await bench.say("在 \(spokenName) 里搜一下 \(keyword)")
        XCTAssertTrue(spoken.calls.contains("search_in_app"), "\(spoken.calls)")
        XCTAssertFalse(spoken.failed.contains("search_in_app"))
        try await bench.wait("\(spokenName) in front") { Self.frontBundle() == bundleID }
        // Only a search that is known to be open is sent any key: turning must select, and back must close it.
        try await bench.wait("the search recognised as a list to pick from") { bench.runtime.snapshot.scope == .sessions }
        // The keyboard is not always reported on the search field itself, so every field in the window is asked.
        func typed() -> Bool {
            guard let window = Self.attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else { return false }
            var queue = [window as! AXUIElement], index = 0
            while index < queue.count, index < 6000 {
                let node = queue[index]; index += 1
                if ["AXTextField", "AXTextArea", "AXComboBox"].contains(Self.attribute(node, kAXRoleAttribute) as? String ?? "") {
                    if (Self.attribute(node, kAXValueAttribute) as? String ?? "").lowercased().contains(keyword) { return true }
                } else { queue += Self.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
            }
            return false
        }
        try await bench.hold()
        var found = false
        for _ in 0..<30 where !found { found = typed(); try await bench.pause(0.1) }
        bench.runtime.handle(.right, phase: .pulse)
        try await bench.pause(0.4)
        XCTAssertEqual(bench.runtime.snapshot.scope, .sessions)
        bench.runtime.handle(.escape, phase: .down); bench.runtime.handle(.escape, phase: .up)
        try await bench.wait("the search closed") { bench.runtime.snapshot.scope != .sessions }
        XCTAssertTrue(found, "The keywords are not in the search")
    }

    /// The keyboard as the device, with real key events: a combination reaches VibeWand and not the document,
    /// holding the dictation combination types what was said, every other key is the document's, and a
    /// combination pressed with the command key's own modifier is not taken for a command, and a key with no
    /// modifier and no place in any list is recorded by pressing it and then stands for a control. Scripted, so
    /// no model is involved. The keys are synthetic and none of them holds ⌥.
    @MainActor
    func testLiveKeyboardLayoutTakesItsCombinationsAndLeavesOtherKeys() async throws {
        try Self.enabled("keyboard-layout")
        var layout = KeyboardLayout.standard
        layout.chords[DeviceControl.voice.rawValue] = KeyChord(code: ApplicationKey.k.keyCode, control: true)
        layout.chords[DeviceControl.right.rawValue] = KeyChord(code: ApplicationKey.right.keyCode, command: true, control: true)
        let bench = try Bench(scripted: ScriptedKernel([]), keyboard: layout)
        defer { bench.leave() }
        var seen: Set<DeviceControl> = []
        bench.runtime.onSnapshot = { seen.formUnion($0.pressed) }
        let (window, _) = try await document(bench)
        defer { window.close() }
        try await bench.wait("the keyboard listening as the device") { bench.runtime.snapshot.connected }
        let hotkey = bench.runtime.command.settings.hotkey, source = CGEventSource(stateID: .privateState)
        func post(_ code: CGKeyCode, flags: CGEventFlags = [], down: Bool, modifier: Bool = false) throws {
            guard window.owned else { throw Self.stopped("The test window lost the keyboard; run stopped") }
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down))
            if modifier { event.type = .flagsChanged }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        func press(_ key: ApplicationKey, flags: CGEventFlags = []) throws {
            try post(key.keyCode, flags: flags, down: true); try post(key.keyCode, flags: flags, down: false)
        }
        let held = CGKeyCode(try XCTUnwrap(hotkey.keyCode))
        // However the run ends, no modifier is left held: a release with nothing down, which types nothing anywhere.
        defer {
            let release = CGEvent(keyboardEventSource: source, virtualKey: held, keyDown: false)
            release?.type = .flagsChanged; release?.flags = []
            release?.post(tap: .cghidEventTap)
        }

        // ⌃K reaching TextEdit would cut the line. Held as the dictation combination, it dictates.
        bench.willHear("键盘听写")
        try post(ApplicationKey.k.keyCode, flags: .maskControl, down: true)
        try await bench.wait("the held combination starts dictation") { bench.runtime.voiceInput.state == .recording }
        XCTAssertTrue(seen.contains(.voice))
        try post(ApplicationKey.k.keyCode, flags: .maskControl, down: false)
        try await bench.wait("what was said typed into the document") { window.text.contains("键盘听写") }
        XCTAssertTrue(window.text.hasSuffix("first line\n"), "the combination reached the document: \(window.text)")

        // A key that is no combination is the document's. A digit, which an input method passes on as it is.
        let before = window.text
        try press(.one)
        try await bench.wait("a plain key typed into the document") { window.text.count == before.count + 1 && window.text.contains("1") }
        let text = window.text

        // The command key held on its own starts a command; a combination pressed with it says it was a modifier.
        try post(held, flags: hotkey.flag, down: true, modifier: true)
        try await bench.wait("\(hotkey.title) heard as the command key") { bench.runtime.command.hud.phase == .listening }
        try press(.right, flags: [.maskControl, .maskCommand])
        try await bench.wait("the combination turned and ended the command") { seen.contains(.right) && bench.runtime.command.hud.phase != .listening }
        try post(held, down: false, modifier: true)
        try await bench.pause(0.5)
        XCTAssertNotEqual(bench.runtime.command.hud.phase, .listening)
        XCTAssertEqual(window.text, text)

        // A key no list of names would offer is recorded by pressing it, the way the settings record one: the
        // number pad's 5, alone. Until then it is the document's; recorded, it stands for its control and types nothing.
        let extra: CGKeyCode = 87
        try post(extra, down: true); try post(extra, down: false)
        try await bench.wait("the extra key typed while it stood for nothing") { window.text.count == text.count + 1 }
        var recorded: KeyChord?
        KeyboardInputSource.capture = { recorded = $0; KeyboardInputSource.capture = nil }
        defer { KeyboardInputSource.capture = nil }
        try post(extra, down: true); try post(extra, down: false)
        try await bench.wait("the pressed key recorded") { recorded != nil }
        XCTAssertEqual(recorded, KeyChord(code: extra))
        bench.keys?.layout.chords[DeviceControl.left.rawValue] = recorded
        seen = []
        try post(extra, down: true); try post(extra, down: false)
        try await bench.wait("the recorded key standing for its control") { seen.contains(.left) }
        try await bench.pause(0.3)
        XCTAssertEqual(window.text.count, text.count + 1, "a recorded key reached the document: \(window.text)")
        try await bench.hold()
    }

    /// The keyboard: the command key held on its own speaks a command, and while a question waits the arrows and
    /// Return answer it without reaching the app in front. Scripted, so no model is involved. The keys are
    /// synthetic; a key that another program takes first, as an input method may, has to be pressed by hand.
    @MainActor
    func testLiveKeyboardSpeaksAndAnswers() async throws {
        try Self.enabled("keyboard")
        let options: [JSONValue] = [["id": "a", "label": "甲"], ["id": "b", "label": "乙"], ["id": "c", "label": "丙"]]
        let kernel = ScriptedKernel([("choose", ["question": "选哪一个", "options": .array(options)]), ("finish", ["summary": "好了"])])
        let bench = try Bench(scripted: kernel)
        defer { bench.leave() }
        let (window, _) = try await document(bench)
        defer { window.close() }
        let text = window.text
        bench.willHear("随便选一个")
        let hotkey = bench.runtime.command.settings.hotkey, source = CGEventSource(stateID: .privateState)
        func post(_ code: CGKeyCode, down: Bool, modifier: Bool = false) throws {
            guard window.owned else { throw Self.stopped("The test window lost the keyboard; run stopped") }
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down))
            if modifier {
                event.type = .flagsChanged
                var flags = CGEventSource.flagsState(.combinedSessionState)
                if down { flags.insert(hotkey.flag) } else { flags.remove(hotkey.flag) }
                event.flags = flags
            }
            event.post(tap: .cghidEventTap)
        }
        func press(_ code: CGKeyCode) throws { try post(code, down: true); try post(code, down: false) }
        let held = CGKeyCode(try XCTUnwrap(hotkey.keyCode))

        try post(held, down: true, modifier: true)
        try await bench.wait("\(hotkey.title) heard as the command key") { bench.runtime.command.hud.phase == .listening }
        try await bench.wait("recording") { bench.runtime.voiceInput.state == .recording }
        try post(held, down: false, modifier: true)
        try await bench.wait("the question shown") { bench.runtime.command.hud.phase == .choosing }
        try press(125)
        try await bench.wait("the arrow moved the selection") { bench.runtime.command.hud.selection == 1 }
        try press(36)
        try await bench.wait("the task ends") { bench.runtime.command.hud.phase == .done }
        XCTAssertTrue(kernel.outcomes.first?.text.contains("\"b\"") == true, "\(kernel.outcomes.first?.text ?? "")")
        XCTAssertEqual(window.text, text, "A key meant for the question reached the document")
        try await bench.hold()
    }
}
