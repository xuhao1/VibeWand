import XCTest
import SpeechInput
import WandAgent
@testable import VibeKeyBridge

/// Opt-in: a real kernel on the voice service's own model, which hears recordings and acts on them, with a
/// stand-in for the desktop. VIBEWAND_LISTENING_LIVE names the recordings of spoken commands, separated by commas
/// and run as one conversation; VIBEWAND_QWEN_ENDPOINT and VIBEWAND_QWEN_KEY the Realtime service
/// (VIBEWAND_QWEN_MODEL its model, when not the default); VIBEWAND_KERNEL_RESOURCES the folder holding the
/// assembled kernel. VIBEWAND_LISTENING_LIVE_TOOLS=all runs instead on the DeepSeek Harness installed on this
/// Mac, in a home of the test's own, with that harness's tools and the window's picture mounted as well: the
/// longest list of tools the model is ever told of. The ordinary suite skips it.
@MainActor
final class ListeningLiveTests: XCTestCase {
    private final class Desk: ToolHost {
        var performed: [String] = []
        func perform(_ tool: String, _ arguments: JSONValue) async -> ToolOutcome {
            performed.append("\(tool) \(arguments.text)")
            switch tool {
            case "list_targets": return .ok(["apps": [["id": "codex", "name": "Codex", "running": true, "sessions": "list"],
                                                      ["id": "claude", "name": "Claude", "running": true, "sessions": "search"]],
                                             "front": ["name": "Finder", "window": ""]])
            case "find_sessions": return .ok(["sessions": [
                ["id": "t-101", "title": "VibeWand 麦克风延迟排查", "folder": "VibekeyPluginCodex", "updated": "2026-10-05 14:10"],
                ["id": "t-090", "title": "修复登录问题", "folder": "webapp", "updated": "2026-10-03 09:00"]]])
            case "open_session": return .ok(["opened": arguments["id"] ?? nil, "front": true])
            case "activate_app": return .ok(["front": arguments["app"] ?? arguments["name"] ?? "", "running": true])
            default: return .ok("ok")
            }
        }
        func confirm(_ tool: String, _ arguments: JSONValue, every: Bool) async -> Bool? { nil }
    }

    /// VibeWand's own lines are spoken by the voice service's synthesis, in the voice the model answers in.
    /// VIBEWAND_LISTENING_LIVE_READ holds the lines, separated by "|".
    func testVibeWandsOwnLinesAreSpokenInTheModelsVoice() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let lines = environment["VIBEWAND_LISTENING_LIVE_READ"]?.components(separatedBy: "|"), let key = environment["VIBEWAND_QWEN_KEY"],
              let endpoint = environment["VIBEWAND_QWEN_ENDPOINT"] else { throw XCTSkip("Set VIBEWAND_LISTENING_LIVE_READ, VIBEWAND_QWEN_ENDPOINT and VIBEWAND_QWEN_KEY") }
        var configuration = SpeechConfiguration()
        configuration.provider = .qwenRealtime; configuration.endpoint = endpoint
        let listener = ListeningModel(service: { (configuration, key) })
        for line in lines {
            var sound = 0, first: TimeInterval?
            let started = Date()
            try await listener.read(line) { sound += $0.count; first = first ?? Date().timeIntervalSince(started) }
            print("READING \(line) → \(String(format: "%.1f", Double(sound) / 2 / QwenRealtimeConversation.sampleRate))s of speech, the first of it after \(String(format: "%.1f", first ?? 0))s")
            XCTAssertGreaterThan(sound, 0)
        }
    }

    /// The words handed to the kernel as the recogniser's reading are a mishearing on purpose: what is done has to
    /// come from the recording. VIBEWAND_LISTENING_LIVE_WORDS gives the readings instead, one for each recording and
    /// separated by "|", and VIBEWAND_LISTENING_LIVE_EXPECT what the first command's tool calls must name, when
    /// its recording is not "打开备忘录".
    func testSpokenCommandsAreActedOnAsHeardAndAnsweredAloud() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let clips = environment["VIBEWAND_LISTENING_LIVE"]?.split(separator: ",").map(String.init), let key = environment["VIBEWAND_QWEN_KEY"],
              let endpoint = environment["VIBEWAND_QWEN_ENDPOINT"] else {
            throw XCTSkip("Set VIBEWAND_LISTENING_LIVE, VIBEWAND_QWEN_ENDPOINT, VIBEWAND_QWEN_KEY and VIBEWAND_KERNEL_RESOURCES to run on a real model")
        }
        let whole = environment["VIBEWAND_LISTENING_LIVE_TOOLS"] == "all"
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vw-listening-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let found = whole
            ? Harness.installed(desktopApp: URL(fileURLWithPath: environment["VIBEWAND_HARNESS_APP"] ?? "/Applications/DeepSeek Harness.app"),
                                bundles: repository.appendingPathComponent("kernel"), home: home.appendingPathComponent("dsh"))
            : environment["VIBEWAND_KERNEL_RESOURCES"].flatMap { Harness.shipped(resources: URL(fileURLWithPath: $0)) }
        guard let harness = found, let version = await harness.version() else { throw XCTSkip("No harness to run on") }
        var configuration = SpeechConfiguration()
        configuration.provider = .qwenRealtime; configuration.endpoint = endpoint
        configuration.model = environment["VIBEWAND_QWEN_MODEL"] ?? configuration.model

        let listener = ListeningModel(service: { (configuration, key) })
        var sound = 0
        listener.speaks = { true }
        listener.onSound = { sound += $0.count }
        let route = try await listener.route(model: configuration.model)
        let mounted = ToolCatalog.mounted(sight: whole)
        let kernel = try await KernelSession.open(try harness.launch(version: version, support: home.appendingPathComponent("support"), models: .route(route),
                                                                     tools: whole ? .all : .own, sight: whole, hearing: true), tools: mounted)
        let expected = (environment["VIBEWAND_LISTENING_LIVE_EXPECT"] ?? "备忘录,Notes").split(separator: ",")
        let readings = environment["VIBEWAND_LISTENING_LIVE_WORDS"]?.components(separatedBy: "|") ?? []
        for (index, clip) in clips.enumerated() {
            let desk = Desk(), gateway = Gateway(tools: mounted, host: desk)
            kernel.approve = { await gateway.approve($0, $1) }
            var own: [String] = []
            let prompt = CoordinatorPrompt.task(index < readings.count ? readings[index] : "打开背网路", frontApp: "Finder", window: "")
            listener.hear(prompt, try SpeechAudio.read(from: URL(fileURLWithPath: clip)))
            var said = "", used = 0
            let started = Date(), before = sound
            let reason = try await kernel.run(prompt, tools: { await gateway.call($0, $1) }) { event in
                if case .message(let text) = event { said += text }
                if case .usage(let tokens, _) = event { used = tokens }
                // A harness's own tools never pass the desk.
                if case .toolStarted(_, let name, let input) = event, !name.hasPrefix(TaskJournal.mounted) { own.append("\(name) \(input.text.prefix(120))") }
            }
            listener.settle()
            let ending = await gateway.ending
            print("LISTENING \(URL(fileURLWithPath: clip).lastPathComponent) took \(String(format: "%.1f", Date().timeIntervalSince(started)))s · calls \(desk.performed + own)"
                  + " · ending \(String(describing: ending)) · said \(said)"
                  + " · speech \(String(format: "%.1f", Double(sound - before) / 2 / QwenRealtimeConversation.sampleRate))s · context \(used)")
            XCTAssertEqual(reason, "end_turn")
            XCTAssertFalse(said.isEmpty, "the model said nothing")
            XCTAssertGreaterThan(sound, before, "nothing was spoken")
            if index == 0 { XCTAssertTrue((desk.performed + own).contains { call in expected.contains { call.contains($0) } }, "\(desk.performed + own)") }
        }
        await kernel.shutdown()
    }
}
