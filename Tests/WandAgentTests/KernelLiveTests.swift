import AppKit
import XCTest
@testable import WandAgent

/// Opt-in: drives a real harness and a real model, with a stand-in for the desktop. Set
/// DEEPSEEK_VIBEWAND_DEV to a key. The shipped harness is the assembled `kernel` in the folder
/// VIBEWAND_KERNEL_RESOURCES names (as the app bundle holds it); the installed one is the DeepSeek Harness
/// on this Mac (VIBEWAND_HARNESS_APP names its app when it is not in /Applications), always pointed at a
/// home of the test's own. The ordinary suite skips these. The model is DeepSeek's.
final class KernelLiveTests: XCTestCase {
    private var home: URL!
    private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let openAI = ModelRoute(wire: .openAIChat, baseURL: "https://api.deepseek.com", model: "deepseek-flash")
    private static let anthropic = ModelRoute(wire: .anthropic, baseURL: "https://api.deepseek.com/anthropic", model: "deepseek-flash")
    override func setUp() { home = FileManager.default.temporaryDirectory.appendingPathComponent("vw-live-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: home) }
    private func key() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_VIBEWAND_DEV"], !key.isEmpty else { throw XCTSkip("Set DEEPSEEK_VIBEWAND_DEV to run against a real model") }
        return key
    }

    // MARK: The two harnesses

    /// The harness VibeWand ships, in a folder of the test's own.
    private func shipped() throws -> Harness {
        guard let resources = ProcessInfo.processInfo.environment["VIBEWAND_KERNEL_RESOURCES"],
              let harness = Harness.shipped(resources: URL(fileURLWithPath: resources)) else {
            throw XCTSkip("Set VIBEWAND_KERNEL_RESOURCES to the folder holding the assembled kernel")
        }
        return harness
    }
    private func session(_ route: ModelRoute = KernelLiveTests.openAI, key wrong: String? = nil, tools: [ToolDefinition] = ToolCatalog.all,
                         sight: Bool = false, resume: String? = nil) async throws -> KernelSession {
        let harness = try shipped()
        var route = route
        route.key = try wrong ?? key()
        let launch = try harness.launch(version: Harness.verified[0], support: home.appendingPathComponent("kernel"), models: .route(route), sight: sight, keeping: resume)
        return try await KernelSession.open(launch, tools: tools, resume: resume)
    }

    /// The DeepSeek Harness installed on this Mac, pointed at a home of the test's own so that the user's is never touched.
    /// Its model is a provider row of the kind the harness's apps write, reaching DeepSeek with the test's key.
    private func installed(peer: String? = nil) throws -> Harness {
        let app = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VIBEWAND_HARNESS_APP"] ?? "/Applications/DeepSeek Harness.app")
        var bundles = repository.appendingPathComponent("kernel")
        if let peer {
            // The same bundles, with the coordinator declaring another harness version than the one installed.
            bundles = home.appendingPathComponent("bundles")
            try FileManager.default.createDirectory(at: bundles, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: repository.appendingPathComponent("kernel/coordinator"), to: bundles.appendingPathComponent("coordinator"))
            let manifest = bundles.appendingPathComponent("coordinator/package.json")
            guard case .object(var members)? = JSONValue(data: try Data(contentsOf: manifest)) else { throw CocoaError(.fileReadCorruptFile) }
            members["peerDependencies"] = ["@deepseek-ai/dsh": .string(peer)]
            try Data(JSONValue.object(members).text.utf8).write(to: manifest)
        }
        guard let harness = Harness.installed(desktopApp: app, bundles: bundles, home: home.appendingPathComponent("dsh")) else {
            throw XCTSkip("Install DeepSeek Harness to run the coordinator on it")
        }
        let desktop = home.appendingPathComponent("dsh/profiles/desktop")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try """
            - id: ui-chat
              name: "@deepseek-ai/dsh-client-ui-chat"
              config:
                transcriptView: standard
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
    private func session(on harness: Harness, tools scope: Harness.Tools = .own, permission: PermissionMode = .risky,
                         mounted: [ToolDefinition] = ToolCatalog.all, sight: Bool = false, resume: String? = nil) async throws -> (KernelSession, KernelLaunch) {
        let reported = await harness.version()
        let version = try XCTUnwrap(reported, "the harness did not say its version")
        var launch = try harness.launch(version: version, support: home.appendingPathComponent("support"), models: .harness(nil),
                                        tools: scope, permission: permission, sight: sight, keeping: resume)
        // In use the harness finds its keys in its own home. Here the key is handed over in the environment and written nowhere.
        launch.environment["WAND_TEST_API_KEY"] = try key()
        return (try await KernelSession.open(launch, tools: mounted, resume: resume), launch)
    }

    private func desktop() -> FakeHost {
        let host = FakeHost()
        host.result = { tool, arguments in
            switch tool {
            case "list_targets": return .ok(["apps": [["id": "codex", "name": "Codex", "running": true, "sessions": "list"],
                                                      ["id": "claude", "name": "Claude", "running": true, "sessions": "search"]],
                                             "front": ["name": "Visual Studio Code", "window": "Runtime.swift"]])
            case "find_sessions": return .ok(["sessions": [
                ["id": "t-101", "title": "VibeWand 麦克风延迟排查", "folder": "VibekeyPluginCodex", "updated": "2026-10-05 14:10"],
                ["id": "t-090", "title": "修复登录问题", "folder": "webapp", "updated": "2026-10-03 09:00"]]])
            case "open_session": return .ok(["opened": arguments["id"] ?? nil, "front": true])
            default: return .ok("ok")
            }
        }
        return host
    }
    /// One instruction through a gateway, with the tools the model called and how it ended.
    private func run(_ kernel: KernelSession, _ words: String, host: FakeHost, mounted: [ToolDefinition] = ToolCatalog.all) async throws -> (tools: [String], ending: Gateway.Ending?) {
        let gateway = Gateway(tools: mounted, host: host)
        kernel.approve = { await gateway.approve($0, $1) }
        var tools: [String] = []
        let reason = try await kernel.run(CoordinatorPrompt.task(words, frontApp: "Visual Studio Code", window: "Runtime.swift"), tools: { await gateway.call($0, $1) }) {
            if case .toolStarted(_, let name, _) = $0 { tools.append(name) }
        }
        XCTAssertEqual(reason, "end_turn")
        return (tools, await gateway.ending)
    }

    // MARK: The shipped harness

    func testAnInstructionRunsThroughTheKernelToTheGateway() async throws {
        let kernel = try await session()
        defer { Task { await kernel.shutdown() } }
        let host = desktop()
        let first = try await run(kernel, "切到 Codex 里讨论 VibeWand 麦克风的那个会话", host: host)
        XCTAssertTrue(host.performed.contains("find_sessions"), "\(host.performed)")
        XCTAssertEqual(host.performed.last, "open_session", "\(host.performed)")
        guard case .finished(let summary) = first.ending else { return XCTFail("the model did not finish: \(String(describing: first.ending))") }
        XCTAssertFalse(summary.isEmpty)
        // The kernel names tools by the server that mounted them; nothing else is on offer.
        XCTAssertTrue(first.tools.allSatisfy { $0.hasPrefix(TaskJournal.mounted) }, "\(first.tools)")

        // The same conversation carries on, so a correction has something to refer to.
        let second = try await run(kernel, "不是这个，是修登录的那个", host: host)
        XCTAssertEqual(host.performed.last, "open_session", "\(host.performed)")
        XCTAssertNotNil(second.ending)
    }

    /// A conversation outlives the process that held it: the next process takes it up with everything said so far.
    func testAConversationIsTakenUpAgainByALaterProcessAndOthersAreDiscarded() async throws {
        // A conversation nobody will take up again, then the one that is kept.
        let other = try await session()
        _ = try await other.run(CoordinatorPrompt.task("只回复：好", frontApp: "", window: ""), tools: { _, _ in .failure("none") }) { _ in }
        let spent = try XCTUnwrap(other.session)
        await other.shutdown()
        let first = try await session()
        _ = try await first.run(CoordinatorPrompt.task("我手上这个项目叫“青柠七号”。现在只回复：好", frontApp: "", window: ""), tools: { _, _ in .failure("none") }) { _ in }
        let kept = try XCTUnwrap(first.session)
        await first.shutdown()

        let later = try await session(resume: kept)
        defer { Task { await later.shutdown() } }
        XCTAssertEqual(later.session, kept, "the conversation was not taken up again")
        var said = ""
        _ = try await later.run(CoordinatorPrompt.task("我刚才说我手上的项目叫什么？只说名字", frontApp: "", window: ""), tools: { _, _ in .failure("none") }) {
            if case .message(let text) = $0 { said += text }
        }
        XCTAssertTrue(said.contains("青柠"), said)
        // The shipped harness's store is read by nothing else: only the conversation that was kept is in it.
        let store = home.appendingPathComponent("kernel/sessions")
        let conversations = try FileManager.default.contentsOfDirectory(atPath: store.path).flatMap { try FileManager.default.contentsOfDirectory(atPath: store.appendingPathComponent($0).path) }
        XCTAssertEqual(conversations, [kept], "\(spent) should be gone")

        // A conversation that is gone cannot be taken up; the first instruction then opens a new one.
        await later.shutdown()
        let fresh = try await session(resume: "00000000-0000-4000-8000-000000000000")
        defer { Task { await fresh.shutdown() } }
        XCTAssertNil(fresh.session)
        _ = try await fresh.run(CoordinatorPrompt.task("只回复：好", frontApp: "", window: ""), tools: { _, _ in .failure("none") }) { _ in }
        XCTAssertNotNil(fresh.session)
    }

    /// The other protocol, with thinking turned off and a context length of the user's choosing.
    func testTheSameServiceIsReachedOverTheAnthropicProtocolWithTheChosenSettings() async throws {
        var route = Self.anthropic
        route.reasoning = .off; route.contextWindow = 64_000
        let kernel = try await session(route)
        defer { Task { await kernel.shutdown() } }
        let host = desktop(), gateway = Gateway(host: host)
        var thoughts = "", usage: [KernelEvent] = []
        let reason = try await kernel.run(CoordinatorPrompt.task("列出可以操作的应用，然后结束", frontApp: "", window: ""), tools: { await gateway.call($0, $1) }) {
            if case .thought(let text) = $0 { thoughts += text }
            if case .usage = $0 { usage.append($0) }
        }
        XCTAssertEqual(reason, "end_turn")
        XCTAssertTrue(host.performed.contains("list_targets"), "\(host.performed)")
        XCTAssertEqual(thoughts, "", "thinking was asked to be off")
        guard case .usage(let used, let size)? = usage.last else { return XCTFail("the kernel reported no context use") }
        XCTAssertEqual(size, 64_000)
        XCTAssertGreaterThan(used, 100)
    }

    /// With seeing turned on the model has one more tool, and what the tool shows reaches it as a picture.
    func testAPictureAToolShowsReachesTheModel() async throws {
        var route = Self.openAI
        route.images = true
        let mounted = ToolCatalog.mounted(sight: true)
        let kernel = try await session(route, tools: mounted, sight: true)
        defer { Task { await kernel.shutdown() } }
        let host = desktop()
        let picture = try Self.picture(of: .systemGreen)
        host.result = { tool, _ in tool == "ui_screenshot" ? ToolOutcome(text: "window \"Untitled\", 320×200 px, no snapshot to mark yet", image: picture) : .ok("ok") }
        let outcome = try await run(kernel, "看一眼窗口，告诉我它整个是什么颜色，用一个英文单词", host: host, mounted: mounted)
        XCTAssertTrue(host.performed.contains("ui_screenshot"), "\(host.performed)")
        guard case .finished(let summary) = outcome.ending else { return XCTFail("the model did not finish: \(String(describing: outcome.ending))") }
        XCTAssertTrue(summary.lowercased().contains("green") || summary.contains("绿"), summary)
    }
    private static func picture(of colour: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { colour.setFill(); $0.fill(); return true }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))
    }

    /// What Settings does when asked to fetch the models an address serves.
    func testTheServiceListsItsModels() async throws {
        let key = try key()
        let listed = try await ModelListing.fetch(wire: .openAIChat, baseURL: Self.openAI.baseURL, key: key)
        let flash = try XCTUnwrap(listed.first { $0.id == Self.openAI.model }, "\(listed.map(\.id))")
        XCTAssertGreaterThan(flash.contextWindow ?? 0, 100_000)
        do {
            _ = try await ModelListing.fetch(wire: .openAIChat, baseURL: Self.openAI.baseURL, key: "sk-not-a-key")
            XCTFail("a wrong key listed models")
        } catch { XCTAssertEqual(error as? ModelListing.Failure, .status(401)) }
        do {
            _ = try await ModelListing.fetch(wire: .openAIChat, baseURL: "http://127.0.0.1:9/v1", key: nil)
            XCTFail("nothing listens there")
        } catch { XCTAssertEqual(error as? ModelListing.Failure, .unreachable) }
    }

    func testAWrongKeyIsReportedInTheServicesOwnWords() async throws {
        let kernel = try await session(key: "sk-not-a-key")
        defer { Task { await kernel.shutdown() } }
        do {
            _ = try await kernel.run("Reply with the single word: ok", tools: { _, _ in .failure("none") }) { _ in }
            XCTFail("a wrong key was accepted")
        } catch let error as RPCError {
            XCTAssertTrue(error.message.contains("401"), error.message)
        }
    }

    func testStopInterruptsATurnThatIsWaitingOnATool() async throws {
        let kernel = try await session()
        defer { Task { await kernel.shutdown() } }
        let host = desktop(); host.delay = 20_000_000_000
        let gateway = Gateway(host: host)
        let started = Date()
        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); await gateway.stop(); kernel.cancel() }
        let reason = try await kernel.run(CoordinatorPrompt.task("列出可以操作的应用", frontApp: "", window: ""),
                                          tools: { await gateway.call($0, $1) }) { _ in }
        XCTAssertEqual(reason, "cancelled")
        XCTAssertLessThan(Date().timeIntervalSince(started), 12)
    }

    // MARK: An installed harness

    /// The same coordinator, as a plugin of the installed harness: it takes the model from the user's own profile,
    /// runs an instruction through the gateway and keeps the conversation in the harness's store, under no project.
    func testTheCoordinatorRunsAsAPluginOfTheInstalledHarness() async throws {
        let harness = try installed()
        XCTAssertEqual(harness.defaultModel, Harness.Model(provider: "wand-test", model: "deepseek-flash"))
        let (kernel, launch) = try await session(on: harness)
        // Starting it opened no conversation: one the user never spoke into would only litter their harness.
        let store = home.appendingPathComponent("dsh/sessions")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))

        let host = desktop()
        let outcome = try await run(kernel, "切到 Codex 里讨论 VibeWand 麦克风的那个会话", host: host)
        XCTAssertEqual(host.performed.last, "open_session", "\(host.performed)")
        guard case .finished = outcome.ending else { await kernel.shutdown(); return XCTFail("the model did not finish: \(String(describing: outcome.ending))") }
        // Nothing but VibeWand's tools is on offer, on the user's harness as on the shipped one.
        XCTAssertTrue(outcome.tools.allSatisfy { $0.hasPrefix(TaskJournal.mounted) }, "\(outcome.tools)")
        // The harness lists its own DeepSeek route beside the one copied from the profile.
        XCTAssertTrue(kernel.options.models.contains { $0.provider == "wand-test" && $0.model == "deepseek-flash" }, "\(kernel.options.models.map(\.id))")
        XCTAssertTrue(kernel.options.models.contains { $0.provider == "deepseek-official" }, "\(kernel.options.models.map(\.id))")
        let kept = try XCTUnwrap(kernel.session)
        await kernel.shutdown()

        // Its summary, with the title the harness's apps list it under, was written as the process let go of it.
        let cached = home.appendingPathComponent("dsh/storages/session_projcache/sessions/\(kept).json")
        let title = JSONValue(data: try Data(contentsOf: cached))?["record"]?["rows"]?["title"]?["val"]?.string ?? ""
        XCTAssertTrue(title.hasPrefix("VibeWand · 切到 Codex"), title)
        print("Harness lists the conversation as: \(title)")
        // The conversation is in the harness's own store, filed under VibeWand's folder, which is no project of the user's.
        let folders = try FileManager.default.contentsOfDirectory(atPath: store.path)
        XCTAssertEqual(folders.count, 1)
        XCTAssertTrue(folders[0].hasSuffix("-support-VibeWand--"), folders[0])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.appendingPathComponent(folders[0]).path), [kept])
        let log = try String(contentsOf: try XCTUnwrap(launch.log), encoding: .utf8)
        XCTAssertFalse(log.contains("is incompatible") || log.contains("did not activate"), String(log.prefix(400)))

        // A later process takes the same conversation up, and nothing in the user's store is discarded for it.
        let (later, _) = try await session(on: harness, resume: kept)
        defer { Task { await later.shutdown() } }
        XCTAssertEqual(later.session, kept)
        let second = try await run(later, "不是这个，是修登录的那个", host: host)
        XCTAssertNotNil(second.ending)
        XCTAssertEqual(host.performed.last, "open_session")
    }

    /// The other tool scope: the harness's own agent with every tool it ships, VibeWand's beside them, and the
    /// harness asking through VibeWand before a step leaves its sandbox.
    func testTheWholeHarnessBringsItsOwnToolsAndAsksThroughVibeWandBeforeLeavingItsSandbox() async throws {
        let harness = try installed()
        let (kernel, _) = try await session(on: harness, tools: .all, permission: .risky)
        defer { Task { await kernel.shutdown() } }
        // Somewhere the sandbox does not let a command write: outside the working folder and outside temporary storage.
        let target = repository.appendingPathComponent("output/live-sandbox-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: target) }
        let host = desktop()
        host.allow = false
        let refused = try await run(kernel, "用 bash 工具执行这一条命令：echo hi > \(target.path) 。如果被沙箱拦下，就按提示申请更大权限重试一次。做完用 finish 说结果。", host: host)
        XCTAssertTrue(refused.tools.contains("bash"), "\(refused.tools)")
        XCTAssertEqual(host.confirmations, ["bash"], "the harness did not ask through VibeWand")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "a declined step ran")
        XCTAssertNotNil(refused.ending, "VibeWand's own tools are mounted beside the harness's: finish was not called")

        host.allow = true
        _ = try await run(kernel, "再试一次同一条命令，这次我会同意。", host: host)
        XCTAssertEqual(host.confirmations, ["bash", "bash"])
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "hi\n")
    }

    /// The harness itself enforces the versions the bundle declares: a bundle declaring another one is not loaded.
    func testTheHarnessRefusesABundleThatDeclaresAnotherVersion() async throws {
        let harness = try installed(peer: "0.1.0")
        let reported = await harness.version()
        let version = try XCTUnwrap(reported)
        // VibeWand's own check passes, as it would for a bundle whose manifest and VibeWand's list had drifted apart.
        var launch = try harness.launch(version: version, support: home.appendingPathComponent("support"), models: .harness(nil))
        launch.environment["WAND_TEST_API_KEY"] = try key()
        do {
            let kernel = try await KernelSession.open(launch)
            defer { Task { await kernel.shutdown() } }
            _ = try await kernel.run("Reply with the single word: ok", tools: { _, _ in .failure("none") }) { _ in }
            XCTFail("a bundle declaring another harness version was loaded")
        } catch {}
        let log = try String(contentsOf: try XCTUnwrap(launch.log), encoding: .utf8)
        XCTAssertTrue(log.contains("is incompatible with dsh \(version)"), String(log.prefix(400)))
    }

    /// Optional: the model rows of a real profile compose on the installed harness. Point VIBEWAND_HARNESS_SETTINGS at
    /// a profile's cordis.patch.yml; it is read, never written, and no model is called with the user's own keys.
    func testAProfilesModelRowsComposeOnTheInstalledHarness() async throws {
        guard let path = ProcessInfo.processInfo.environment["VIBEWAND_HARNESS_SETTINGS"] else { throw XCTSkip("Set VIBEWAND_HARNESS_SETTINGS to a profile's cordis.patch.yml") }
        let harness = try installed()
        let settings = try String(contentsOfFile: path, encoding: .utf8)
        try settings.write(to: home.appendingPathComponent("dsh/profiles/desktop/cordis.patch.yml"), atomically: true, encoding: .utf8)
        for scope in Harness.Tools.allCases {
            let (kernel, launch) = try await session(on: harness, tools: scope)
            defer { Task { await kernel.shutdown() } }
            // The turn itself may fail for want of a key; the conversation it opens first says what the harness can serve.
            _ = try? await kernel.run("Reply with the single word: ok", tools: { _, _ in .failure("none") }) { _ in }
            let chosen = harness.defaultModel
            print("Harness composition (\(scope.rawValue)): default \(chosen.provider)/\(chosen.model); serves \(kernel.options.models.map(\.id))")
            XCTAssertTrue(kernel.options.models.contains { $0.provider == chosen.provider && $0.model == chosen.model },
                          "the profile's default model is not among the models the harness lists")
            let log = (try? String(contentsOf: try XCTUnwrap(launch.log), encoding: .utf8)) ?? ""
            XCTAssertFalse(log.contains("ValidationError") || log.contains("did not activate"), String(log.prefix(600)))
        }
    }
}
