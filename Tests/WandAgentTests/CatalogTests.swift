import XCTest
@testable import WandAgent

final class CatalogTests: XCTestCase {
    /// The catalog is the model's whole reach. A tool added here must be a deliberate decision.
    func testTheCatalogIsExactlyTheDesignedToolList() {
        XCTAssertEqual(ToolCatalog.all.map(\.name), [
            "list_targets", "find_sessions", "open_session", "search_in_app", "activate_app", "choose", "finish", "need_user",
            "ui_snapshot", "ui_press", "ui_key", "ui_menu", "ui_type"
        ])
        for tool in ToolCatalog.mounted(sight: true) {
            XCTAssertEqual(tool.schema["type"]?.string, "object", tool.name)
            let properties = tool.schema["properties"] ?? [:]
            for required in tool.schema["required"]?.array ?? [] {
                XCTAssertNotNil(properties[required.string ?? ""], "\(tool.name) requires an undeclared \(required)")
            }
            XCTAssertFalse(tool.summary.contains("\n"), tool.name)
        }
        XCTAssertFalse(ToolCatalog.all.contains { $0.effect == .submit })
    }

    /// Seeing the window is two more tools, mounted only when the user has turned it on: the window's picture,
    /// and the pointer at a place in it. Without it no point is ever clicked.
    func testThePictureOfTheWindowAndThePointerAreMountedOnlyWhenTheUserLetsTheModelSee() {
        XCTAssertEqual(ToolCatalog.mounted(sight: false), ToolCatalog.all)
        XCTAssertEqual(ToolCatalog.mounted(sight: true).map(\.name), ToolCatalog.all.map(\.name) + ["ui_screenshot", "ui_click"])
        XCTAssertEqual(ToolCatalog.seeing.map(\.effect), [.read, .navigate])
        XCTAssertFalse(ToolCatalog.all.contains { ToolCatalog.seeing.contains($0) })
        // A place is an id or a point of the picture, so neither is required.
        XCTAssertNotNil(ToolCatalog.click.schema["properties"]?["id"])
        XCTAssertEqual(ToolCatalog.click.schema["properties"]?["x"]?["type"], "integer")
        XCTAssertEqual(ToolCatalog.click.schema["properties"]?["y"]?["type"], "integer")
        XCTAssertEqual(ToolCatalog.click.schema["properties"]?["count"]?["maximum"], 2)
        XCTAssertEqual(ToolCatalog.click.schema["required"], [])
        // The model is told of them only then, and of a harness's own tools only when they are mounted.
        for name in ["ui_screenshot", "ui_click", "harness"] { XCTAssertFalse(CoordinatorPrompt.system.contains(name), name) }
        XCTAssertEqual(CoordinatorPrompt.system(instructions: " "), CoordinatorPrompt.system)
        let seeing = CoordinatorPrompt.system(instructions: "", sight: true)
        XCTAssertTrue(seeing.hasPrefix(CoordinatorPrompt.system))
        for name in ["ui_screenshot", "ui_click", "publish no controls", "pagedown"] { XCTAssertTrue(seeing.contains(name), name) }
        let whole = CoordinatorPrompt.system(instructions: "叫我老徐", tools: .all)
        XCTAssertTrue(whole.contains("this harness's own") && !whole.contains("ui_screenshot") && whole.hasSuffix("叫我老徐"))
    }

    func testDestructiveAndSendingControlsNeedTheUser() {
        for label in ["Delete", "Move to Trash", "Don't Save", "Discard Changes", "Send", "发送", "删除会话", "不保存", "退出登录", "Submit feedback",
                      // Handing an agent more reach is the user's call too: Codex asks this when its effort is pushed to the top.
                      "Use Full access", "Allow", "Approve for this session", "始终允许", "授权访问"] {
            XCTAssertTrue(ControlRisk.needsConfirmation(label), label)
        }
        for label in ["Runtime.swift", "Close Tab", "关闭标签页", "Open Recent", "下一个", "Search", "Save", "Explorer"] {
            XCTAssertFalse(ControlRisk.needsConfirmation(label), label)
        }
    }

    func testTaskPromptOpensWithVibeWandsNameAndTheWordsUnchangedThenTheirContext() {
        let prompt = CoordinatorPrompt.task("把这段报错交给 Codex，先不要改代码", frontApp: "Visual Studio Code",
                                           window: "Runtime.swift — VibeWand", now: Date(timeIntervalSince1970: 1_791_186_000))
        let lines = prompt.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        // A runtime titles a conversation from its opening words, so a list of them shows whose it is and what was asked.
        XCTAssertEqual(lines[0], "VibeWand · 把这段报错交给 Codex，先不要改代码")
        XCTAssertNotNil(lines[1].range(of: #"^\d\d:\d\d [A-Z][a-z]{2} 2026-10-0\d\. The user was in Visual Studio Code, window "Runtime\.swift — VibeWand"$"#, options: .regularExpression), lines[1])
        // With a one-word command the title's five words end on the time, not on a stray word of context.
        let short = CoordinatorPrompt.task("打开计算器", frontApp: "", window: "", now: Date(timeIntervalSince1970: 1_791_186_000))
        XCTAssertNotNil(short.split(whereSeparator: \.isWhitespace).prefix(5).joined(separator: " ")
            .range(of: #"^VibeWand · 打开计算器 \d\d:\d\d [A-Z][a-z]{2}$"#, options: .regularExpression), short)
        XCTAssertEqual(short.split(separator: "\n").count, 2)
    }

    func testKernelEventsAreReadFromSessionUpdates() {
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "好的"]]), .message("好的"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "agent_thought_chunk", "content": ["type": "text", "text": "two fit"]]), .thought("two fit"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call", "toolCallId": "c1", "title": "mcp__vibewand__find_sessions", "status": "in_progress"]),
                       .toolStarted(id: "c1", name: "mcp__vibewand__find_sessions"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "failed"]), .toolEnded(id: "c1", failed: true))
        // A tool of the runtime's own comes with what it was called with and what it answered.
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call", "toolCallId": "c2", "title": "bash", "rawInput": ["command": "ls"]]),
                       .toolStarted(id: "c2", name: "bash", input: ["command": "ls"]))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call_update", "toolCallId": "c2", "status": "completed", "content": [
            ["type": "content", "content": ["type": "text", "text": "a.txt"]], ["type": "content", "content": ["type": "image", "data": "…"]],
            ["type": "content", "content": ["type": "text", "text": "b.txt"]]]]), .toolEnded(id: "c2", failed: false, text: "a.txt\nb.txt"))
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
