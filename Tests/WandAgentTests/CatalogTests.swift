import XCTest
@testable import WandAgent

final class CatalogTests: XCTestCase {
    /// The catalog is the model's whole reach. A tool added here must be a deliberate decision.
    func testTheCatalogIsExactlyTheDesignedToolList() {
        XCTAssertEqual(ToolCatalog.all.map(\.name), [
            "list_targets", "find_sessions", "open_session", "search_in_app", "activate_app", "choose", "finish", "need_user",
            "ui_snapshot", "ui_press", "ui_key", "ui_menu", "ui_type"
        ])
        for tool in ToolCatalog.all {
            XCTAssertEqual(tool.schema["type"]?.string, "object", tool.name)
            let properties = tool.schema["properties"] ?? [:]
            for required in tool.schema["required"]?.array ?? [] {
                XCTAssertNotNil(properties[required.string ?? ""], "\(tool.name) requires an undeclared \(required)")
            }
            XCTAssertFalse(tool.summary.contains("\n"), tool.name)
        }
        XCTAssertFalse(ToolCatalog.all.contains { $0.effect == .submit })
    }

    func testDestructiveAndSendingControlsNeedTheUser() {
        for label in ["Delete", "Move to Trash", "Don't Save", "Discard Changes", "Send", "发送", "删除会话", "不保存", "退出登录", "Submit feedback"] {
            XCTAssertTrue(ControlRisk.needsConfirmation(label), label)
        }
        for label in ["Runtime.swift", "Close Tab", "关闭标签页", "Open Recent", "下一个", "Search", "Save", "Explorer"] {
            XCTAssertFalse(ControlRisk.needsConfirmation(label), label)
        }
    }

    func testTaskPromptLeadsWithTheWordsUnchangedThenTheirContext() {
        let prompt = CoordinatorPrompt.task("把这段报错交给 Codex，先不要改代码", frontApp: "Visual Studio Code",
                                           window: "Runtime.swift — VibeWand", now: Date(timeIntervalSince1970: 1_791_186_000))
        let lines = prompt.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        // A runtime titles a conversation from its opening words, so the command is what a list of them shows.
        XCTAssertEqual(lines[0], "Command: 把这段报错交给 Codex，先不要改代码")
        XCTAssertTrue(lines[1].hasPrefix("Now: 2026-10-0"))
        XCTAssertEqual(lines[2], "The user was in: Visual Studio Code, window \"Runtime.swift — VibeWand\"")
        XCTAssertEqual(CoordinatorPrompt.task("停", frontApp: "", window: "").split(separator: "\n").count, 2)
    }

    func testKernelEventsAreReadFromSessionUpdates() {
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "好的"]]), .message("好的"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "agent_thought_chunk", "content": ["type": "text", "text": "two fit"]]), .thought("two fit"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call", "toolCallId": "c1", "title": "mcp__vibewand__find_sessions", "status": "in_progress"]),
                       .toolStarted(id: "c1", name: "mcp__vibewand__find_sessions"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "failed"]), .toolEnded(id: "c1", failed: true))
        XCTAssertNil(KernelEvent.parse(["sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "in_progress"]))
        XCTAssertNil(KernelEvent.parse(["sessionUpdate": "usage_update", "used": 629]))
    }

    func testScriptedKernelReplaysItsCallsThroughTheGateway() async throws {
        let host = FakeHost(), gateway = Gateway(host: host)
        let kernel = ScriptedKernel([("find_sessions", ["app": "codex", "query": "麦克风"]), ("open_session", ["app": "codex", "id": "t-1"]),
                                     ("finish", ["summary": "已打开"])])
        var seen: [KernelEvent] = []
        let reason = try await kernel.run("Command: …", tools: { await gateway.call($0, $1) }) { seen.append($0) }
        XCTAssertEqual(reason, "end_turn")
        XCTAssertEqual(host.performed, ["find_sessions", "open_session"])
        XCTAssertEqual(seen.count, 6)
        let ending = await gateway.ending
        XCTAssertEqual(ending, .finished("已打开"))
    }
}
