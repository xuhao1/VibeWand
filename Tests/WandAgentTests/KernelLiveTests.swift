import XCTest
@testable import WandAgent

/// Opt-in: drives a real kernel and a real model, with a stand-in for the desktop.
/// Set DEEPSEEK_VIBEWAND_DEV to a key, and either VIBEWAND_KERNEL_RESOURCES to a
/// folder holding the assembled `kernel` (as the app bundle does) or
/// VIBEWAND_KERNEL to a `dsh` launcher. The ordinary suite skips these.
/// The model is DeepSeek's, reached over each protocol its service speaks. The plugin-mode tests also need
/// DeepSeek Harness installed (VIBEWAND_HARNESS_APP names its app when it is not in /Applications).
final class KernelLiveTests: XCTestCase {
    private var home: URL!
    private static let openAI = ModelRoute(wire: .openAIChat, baseURL: "https://api.deepseek.com", model: "deepseek-flash")
    private static let anthropic = ModelRoute(wire: .anthropic, baseURL: "https://api.deepseek.com/anthropic", model: "deepseek-flash")
    private func session(_ route: ModelRoute = KernelLiveTests.openAI, key wrong: String? = nil) async throws -> KernelSession {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundled = environment["VIBEWAND_KERNEL_RESOURCES"].flatMap { KernelInstall(resources: URL(fileURLWithPath: $0)) }
        let launched = environment["VIBEWAND_KERNEL"].map { KernelInstall(command: [$0], profile: repository.appendingPathComponent("kernel/profile")) }
        guard let install = bundled ?? launched, let key = environment["DEEPSEEK_VIBEWAND_DEV"], !key.isEmpty else {
            throw XCTSkip("Set DEEPSEEK_VIBEWAND_DEV and a kernel location to run against a real kernel")
        }
        home = FileManager.default.temporaryDirectory.appendingPathComponent("vw-live-\(UUID().uuidString)")
        var route = route
        route.key = wrong ?? key
        return try await KernelSession.open(try install.launch(home: home, route: route))
    }
    override func tearDown() { if let home { try? FileManager.default.removeItem(at: home) } }

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

    func testAnInstructionRunsThroughTheKernelToTheGateway() async throws {
        let kernel = try await session()
        defer { kernel.shutdown() }
        let host = desktop(), gateway = Gateway(host: host)
        var tools: [String] = []
        let prompt = CoordinatorPrompt.task("切到 Codex 里讨论 VibeWand 麦克风的那个会话", frontApp: "Visual Studio Code", window: "Runtime.swift")
        let reason = try await kernel.run(prompt, tools: { await gateway.call($0, $1) }) {
            if case .toolStarted(_, let name) = $0 { tools.append(name) }
        }
        XCTAssertEqual(reason, "end_turn")
        XCTAssertTrue(host.performed.contains("find_sessions"), "\(host.performed)")
        XCTAssertEqual(host.performed.last, "open_session", "\(host.performed)")
        let ending = await gateway.ending
        guard case .finished(let summary) = ending else { return XCTFail("the model did not finish: \(String(describing: ending))") }
        XCTAssertFalse(summary.isEmpty)
        // The kernel names tools by the server that mounted them; nothing else is on offer.
        XCTAssertTrue(tools.allSatisfy { $0.hasPrefix("mcp__vibewand__") }, "\(tools)")

        // The same conversation carries on, so a correction has something to refer to.
        let second = Gateway(host: host)
        _ = try await kernel.run(CoordinatorPrompt.task("不是这个，是修登录的那个", frontApp: "Codex", window: ""), tools: { await second.call($0, $1) }) { _ in }
        XCTAssertEqual(host.performed.last, "open_session", "\(host.performed)")
        let secondEnding = await second.ending
        XCTAssertNotNil(secondEnding)
    }

    /// The other protocol, with thinking turned off and a context length of the user's choosing.
    func testTheSameServiceIsReachedOverTheAnthropicProtocolWithTheChosenSettings() async throws {
        var route = Self.anthropic
        route.reasoning = .off; route.contextWindow = 64_000
        let kernel = try await session(route)
        defer { kernel.shutdown() }
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

    /// What Settings does when asked to fetch the models an address serves.
    func testTheServiceListsItsModels() async throws {
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_VIBEWAND_DEV"], !key.isEmpty else { throw XCTSkip("Set DEEPSEEK_VIBEWAND_DEV") }
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

    // MARK: Plugin mode

    /// The DeepSeek Harness installed on this Mac, pointed at a home of the test's own so that the user's is never touched.
    /// The model is a provider row of the kind the harness's apps write, reaching DeepSeek with the test's key.
    private func harness(peer: String? = nil) throws -> (plugin: HarnessPlugin, key: String) {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = URL(fileURLWithPath: environment["VIBEWAND_HARNESS_APP"] ?? "/Applications/DeepSeek Harness.app")
        home = FileManager.default.temporaryDirectory.appendingPathComponent("vw-live-\(UUID().uuidString)")
        var bundle = repository.appendingPathComponent("kernel/plugin")
        if let peer {
            // The same bundle, declaring another harness version than the one installed.
            let copy = home.appendingPathComponent("bundle")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: bundle, to: copy)
            let manifest = try String(contentsOf: copy.appendingPathComponent("package.json"), encoding: .utf8)
            try manifest.replacingOccurrences(of: HarnessPlugin.verified.joined(separator: " || "), with: peer)
                .write(to: copy.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
            bundle = copy
        }
        guard let key = environment["DEEPSEEK_VIBEWAND_DEV"], !key.isEmpty,
              let plugin = HarnessPlugin.locate(desktopApp: app, bundle: bundle, home: home.appendingPathComponent("dsh")) else {
            throw XCTSkip("Set DEEPSEEK_VIBEWAND_DEV and install DeepSeek Harness to run plugin mode against it")
        }
        let desktop = plugin.home.appendingPathComponent("profiles/desktop")
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
            - id: agent-default-model
              name: "@deepseek-ai/dsh-agent-default-model"
              config:
                provider: wand-test
                model: deepseek-flash

            """.write(to: desktop.appendingPathComponent("cordis.patch.yml"), atomically: true, encoding: .utf8)
        return (plugin, key)
    }

    /// The whole of plugin mode but the app: the installed harness loads VibeWand's bundle, takes the model from
    /// the user's own profile, runs an instruction through the gateway and keeps the conversation in its store.
    func testTheCoordinatorRunsAsAPluginOfTheInstalledHarness() async throws {
        let (plugin, key) = try harness()
        let reported = await plugin.version()
        let version = try XCTUnwrap(reported, "the harness did not say its version")
        XCTAssertTrue(HarnessPlugin.verified.contains(version), "the installed harness is \(version); the plugin declares \(HarnessPlugin.verified)")
        XCTAssertEqual(plugin.defaultModel, HarnessPlugin.Model(provider: "wand-test", model: "deepseek-flash"))
        var launch = try plugin.launch(version: version, allowUnverified: false, support: home.appendingPathComponent("support"), model: nil)
        // In use the harness finds its keys in its own home. Here the key is handed over in the environment and written nowhere.
        launch.environment["WAND_TEST_API_KEY"] = key
        let kernel = try await KernelSession.open(launch)
        defer { kernel.shutdown() }
        // Starting it opened no conversation: one the user never spoke into would only litter their harness.
        let store = plugin.home.appendingPathComponent("sessions")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))

        let host = desktop(), gateway = Gateway(host: host)
        var tools: [String] = [], usage: KernelEvent?
        let prompt = CoordinatorPrompt.task("切到 Codex 里讨论 VibeWand 麦克风的那个会话", frontApp: "Visual Studio Code", window: "Runtime.swift")
        let reason = try await kernel.run(prompt, tools: { await gateway.call($0, $1) }) {
            if case .toolStarted(_, let name) = $0 { tools.append(name) }
            if case .usage = $0 { usage = $0 }
        }
        XCTAssertEqual(reason, "end_turn")
        XCTAssertEqual(host.performed.last, "open_session", "\(host.performed)")
        let ending = await gateway.ending
        guard case .finished = ending else { return XCTFail("the model did not finish: \(String(describing: ending))") }
        // Nothing but VibeWand's tools is on offer, on the user's harness as on the built-in kernel.
        XCTAssertTrue(tools.allSatisfy { $0.hasPrefix("mcp__vibewand__") }, "\(tools)")
        XCTAssertNotNil(usage, "the harness reported no context use")
        // The harness lists its own DeepSeek route beside the one copied from the profile.
        XCTAssertTrue(kernel.options.models.contains { $0.provider == "wand-test" && $0.model == "deepseek-flash" }, "\(kernel.options.models.map(\.id))")
        XCTAssertTrue(kernel.options.models.contains { $0.provider == "deepseek-official" }, "\(kernel.options.models.map(\.id))")

        // The conversation is in the harness's own store, filed under the folder named VibeWand, where its apps list it.
        let folders = try FileManager.default.contentsOfDirectory(atPath: store.path)
        XCTAssertEqual(folders.count, 1)
        XCTAssertTrue(folders[0].hasSuffix("-support-VibeWand--"), folders[0])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.appendingPathComponent(folders[0]).path).count, 1)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: plugin.home.appendingPathComponent("storages/session_projcache/sessions").path).isEmpty)
    }

    /// The harness itself enforces the versions the bundle declares: a bundle declaring another one is not loaded.
    func testTheHarnessRefusesABundleThatDeclaresAnotherVersion() async throws {
        let (plugin, key) = try harness(peer: "0.1.0")
        let reported = await plugin.version()
        let version = try XCTUnwrap(reported)
        var launch = try plugin.launch(version: version, allowUnverified: false, support: home.appendingPathComponent("support"), model: nil)
        launch.environment["WAND_TEST_API_KEY"] = key
        do {
            let kernel = try await KernelSession.open(launch)
            defer { kernel.shutdown() }
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
        let (plugin, _) = try harness()
        let settings = try String(contentsOfFile: path, encoding: .utf8)
        try settings.write(to: plugin.home.appendingPathComponent("profiles/desktop/cordis.patch.yml"), atomically: true, encoding: .utf8)
        let reported = await plugin.version()
        let version = try XCTUnwrap(reported)
        let launch = try plugin.launch(version: version, allowUnverified: false, support: home.appendingPathComponent("support"), model: nil)
        let kernel = try await KernelSession.open(launch)
        defer { kernel.shutdown() }
        // The turn itself may fail for want of a key; the conversation it opens first says what the harness can serve.
        _ = try? await kernel.run("Reply with the single word: ok", tools: { _, _ in .failure("none") }) { _ in }
        let chosen = plugin.defaultModel
        print("Harness composition: default \(chosen.provider)/\(chosen.model); serves \(kernel.options.models.map(\.id))")
        XCTAssertTrue(kernel.options.models.contains { $0.provider == chosen.provider && $0.model == chosen.model },
                      "the profile's default model is not among the models the harness lists")
        let log = (try? String(contentsOf: try XCTUnwrap(launch.log), encoding: .utf8)) ?? ""
        XCTAssertFalse(log.contains("ValidationError") || log.contains("did not activate"), String(log.prefix(600)))
    }

    func testAWrongKeyIsReportedInTheServicesOwnWords() async throws {
        let kernel = try await session(key: "sk-not-a-key")
        defer { kernel.shutdown() }
        do {
            _ = try await kernel.run("Reply with the single word: ok", tools: { _, _ in .failure("none") }) { _ in }
            XCTFail("a wrong key was accepted")
        } catch let error as RPCError {
            XCTAssertTrue(error.message.contains("401"), error.message)
        }
    }

    func testStopInterruptsATurnThatIsWaitingOnATool() async throws {
        let kernel = try await session()
        defer { kernel.shutdown() }
        let host = desktop(); host.delay = 20_000_000_000
        let gateway = Gateway(host: host)
        let started = Date()
        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); await gateway.stop(); kernel.cancel() }
        let reason = try await kernel.run(CoordinatorPrompt.task("列出可以操作的应用", frontApp: "", window: ""),
                                          tools: { await gateway.call($0, $1) }) { _ in }
        XCTAssertEqual(reason, "cancelled")
        XCTAssertLessThan(Date().timeIntervalSince(started), 12)
    }
}
