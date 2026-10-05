import XCTest
@testable import WandAgent

/// Opt-in: drives a real kernel and a real model, with a stand-in for the desktop.
/// Set DEEPSEEK_VIBEWAND_DEV to a key, and either VIBEWAND_KERNEL_RESOURCES to a
/// folder holding the assembled `kernel` (as the app bundle does) or
/// VIBEWAND_KERNEL to a `dsh` launcher. The ordinary suite skips these.
/// The model is DeepSeek's, reached over each protocol its service speaks.
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
