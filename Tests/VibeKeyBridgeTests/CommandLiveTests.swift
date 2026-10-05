import AppKit
import ApplicationServices
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
    private static func kernel(home: URL) async throws -> KernelSession {
        guard let install = environment["VIBEWAND_KERNEL_RESOURCES"].flatMap({ KernelInstall(resources: URL(fileURLWithPath: $0)) }),
              let key = environment["DEEPSEEK_VIBEWAND_DEV"], !key.isEmpty else {
            throw stopped("Set DEEPSEEK_VIBEWAND_DEV to a key and VIBEWAND_KERNEL_RESOURCES to the folder holding the assembled kernel")
        }
        // DeepSeek's service over the protocol most endpoints speak; thinking can be set for a run.
        let reasoning = environment["VIBEWAND_COMMAND_LIVE_REASONING"].flatMap(ModelRoute.Reasoning.init(rawValue:)) ?? .automatic
        let route = ModelRoute(wire: .openAIChat, baseURL: "https://api.deepseek.com", model: environment["VIBEWAND_COMMAND_LIVE_MODEL"] ?? "deepseek-flash",
                               key: key, reasoning: reasoning)
        return try await KernelSession.open(try install.launch(home: home, route: route))
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

        static func find(_ bundleID: String, titled marker: String, seconds: Double = 20) async throws -> Window {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    let windows = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
                    if let window = windows.first(where: { (attribute($0, kAXTitleAttribute) as? String ?? "").contains(marker) }) {
                        return Window(app: app, element: window)
                    }
                }
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
        func close() {
            guard let button = attribute(element, kAXCloseButtonAttribute) else { return }
            _ = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    // MARK: The bench

    private final class Words: @unchecked Sendable { var text = "" }
    /// Says a key is there, so the settings count as usable; the key itself goes to the kernel from the environment.
    private struct KeyOnFile: SpeechCredentialStore {
        func read(account: String) throws -> String? { nil }
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
        private var previous: NSRunningApplication?

        init(scripted: ScriptedKernel? = nil, permission: PermissionMode = .risky) throws {
            let words = Words(), suite = "VibeWand.CommandLive.\(UUID().uuidString)"
            let support = FileManager.default.temporaryDirectory.appendingPathComponent("vw-command-live-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            guard let defaults = UserDefaults(suiteName: suite) else { throw stopped("No preferences for the test") }
            let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults),
                                             engineFactory: { _ in TranscriptReplayEngine(previews: [words.text]) })
            let settings = CommandSettings(defaults: defaults, credentials: KeyOnFile())
            settings.setPermission(permission)
            let templates = DeviceTemplateStore(defaults: defaults)
            runtime = BridgeRuntime(source: UnconfiguredHIDSource(template: templates.selectedTemplate), templates: templates,
                                    sourceFactory: { _, id in UnconfiguredHIDSource(template: id.template) }, voiceInput: voice) {
                let command = CommandController(settings: settings, tools: CommandTools(adapter: $0), voice: $1, support: support)
                command.openKernel = { if let scripted { return scripted }; return try await kernel(home: support.appendingPathComponent("kernel")) }
                return command
            }
            self.words = words; self.support = support; self.suite = suite
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

        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vw-command-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let kernel = try await Self.kernel(home: home)
        defer { kernel.shutdown() }
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
